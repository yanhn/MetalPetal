//
//  MTIRenderPipelineKernel.m
//  Pods
//
//  Created by YuAo on 02/07/2017.
//
//

#import "MTIRenderPipelineKernel.h"
#import "MTIContext.h"
#import "MTIFilterFunctionDescriptor.h"
#import "MTIImage.h"
#import "MTIImagePromise.h"
#import "MTIVertex.h"
#import "MTIImageRenderingContext.h"
#import "MTITextureDescriptor.h"
#import "MTIRenderPipeline.h"
#import "MTITexturePool.h"

@interface MTIImageRenderingRecipe : NSObject <MTIImagePromise>

@property (nonatomic,copy,readonly) NSArray<MTIImage *> *inputImages;

@property (nonatomic,strong,readonly) MTIRenderPipelineKernel *kernel;

@property (nonatomic,copy,readonly) NSDictionary<NSString *, id> *fragmentFunctionParameters;

@property (nonatomic,copy,readonly) MTITextureDescriptor *textureDescriptor;

@end

@implementation MTIImageRenderingRecipe

- (MTIVertices *)verticesForRect:(CGRect)rect {
    CGFloat l = CGRectGetMinX(rect);
    CGFloat r = CGRectGetMaxX(rect);
    CGFloat t = CGRectGetMinY(rect);
    CGFloat b = CGRectGetMaxY(rect);
    
    return [[MTIVertices alloc] initWithVertices:(MTIVertex []){
        { .position = {l, t, 0, 1} , .textureCoordinate = { 0, 1 } },
        { .position = {r, t, 0, 1} , .textureCoordinate = { 1, 1 } },
        { .position = {l, b, 0, 1} , .textureCoordinate = { 0, 0 } },
        { .position = {r, b, 0, 1} , .textureCoordinate = { 1, 0 } }
    } count:4];
}

- (id<MTLTexture>)resolveWithContext:(MTIImageRenderingContext *)renderingContext error:(NSError * _Nullable __autoreleasing *)inOutError {
    NSError *error = nil;
    NSMutableArray<id<MTLTexture>> *inputTextures = [NSMutableArray array];
    for (MTIImage *image in self.inputImages) {
        if (error) {
            if (inOutError) {
                *inOutError = error;
            }
            return nil;
        }
#warning fetch resolve result from cache
        [inputTextures addObject:[image.promise resolveWithContext:renderingContext error:&error]];
    }
    
    MTIRenderPipeline *renderPipeline = [renderingContext.context kernelStateForKernel:self.kernel error:&error];
    
    if (error) {
        if (inOutError) {
            *inOutError = error;
        }
        return nil;
    }
    
    id<MTLTexture> renderTarget = [renderingContext.context.texturePool newRenderTargetForPromise:self];
    
    MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDescriptor.colorAttachments[0].texture = renderTarget;
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    MTIVertices *vertices = [self verticesForRect:CGRectMake(-1, -1, 2, 2)];
    
    __auto_type commandEncoder = [renderingContext.commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    [commandEncoder setRenderPipelineState:renderPipeline.state];
    
    if (vertices.count * sizeof(MTIVertex) < 4096) {
        //The setVertexBytes:length:atIndex: method is the best option for binding a very small amount (less than 4 KB) of dynamic buffer data to a vertex function. This method avoids the overhead of creating an intermediary MTLBuffer object. Instead, Metal manages a transient buffer for you.
        [commandEncoder setVertexBytes:vertices.buffer length:vertices.count * sizeof(MTIVertex) atIndex:0];
    } else {
#warning cache buffers
        id<MTLBuffer> verticesBuffer = [renderingContext.context.device newBufferWithBytes:vertices.buffer length:vertices.count * sizeof(MTIVertex) options:0];
        [commandEncoder setVertexBuffer:verticesBuffer offset:0 atIndex:0];
    }
    
    for (NSUInteger index = 0; index < inputTextures.count; index += 1) {
        [commandEncoder setFragmentTexture:inputTextures[index] atIndex:index];
        id<MTLSamplerState> samplerState = [renderingContext.context samplerStateWithDescriptor:self.inputImages[index].samplerDescriptor];
        [commandEncoder setFragmentSamplerState:samplerState atIndex:index];
    }
    
    //encode parameters
    //TODO其他类型参数的支持，这里用的是setBytes的方式，还可以换成setBuffer的方式。
    if (self.fragmentFunctionParameters.count > 0) {
        for (NSInteger index = 0; index < renderPipeline.reflection.fragmentArguments.count; index += 1) {
            MTLArgument *argument = renderPipeline.reflection.fragmentArguments[index];
            id value = self.fragmentFunctionParameters[argument.name];
            if (value) {
                switch (argument.bufferDataType) {
                    case MTLDataTypeFloat: {
                        float floatValue = [value floatValue];
                        [commandEncoder setFragmentBytes:&floatValue length:sizeof(floatValue) atIndex:argument.index];
                    } break;
                        
                    default:
                        break;
                }
            }
        }
    }
    
    [commandEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:vertices.count];
    [commandEncoder endEncoding];
    
    return renderTarget;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (instancetype)initWithKernel:(MTIRenderPipelineKernel *)kernel
                   inputImages:(NSArray<MTIImage *> *)inputImages
    fragmentFunctionParameters:(NSDictionary<NSString *,id> *)fragmentFunctionParameters
       outputTextureDescriptor:(MTLTextureDescriptor *)outputTextureDescriptor {
    if (self = [super init]) {
        _inputImages = inputImages;
        _kernel = kernel;
        _fragmentFunctionParameters = fragmentFunctionParameters;
        _textureDescriptor = [outputTextureDescriptor newMTITextureDescriptor];
    }
    return self;
}

@end

@interface MTIRenderPipelineKernel ()

@property (nonatomic,copy) MTIFilterFunctionDescriptor *vertexFunctionDescriptor;
@property (nonatomic,copy) MTIFilterFunctionDescriptor *fragmentFunctionDescriptor;
@property (nonatomic,copy) MTLVertexDescriptor *vertexDescriptor;
@property (nonatomic,copy) MTLRenderPipelineColorAttachmentDescriptor *colorAttachmentDescriptor;

@end

@implementation MTIRenderPipelineKernel

- (instancetype)initWithVertexFunctionDescriptor:(MTIFilterFunctionDescriptor *)vertexFunctionDescriptor fragmentFunctionDescriptor:(MTIFilterFunctionDescriptor *)fragmentFunctionDescriptor colorAttachmentPixelFormat:(MTLPixelFormat)colorAttachmentPixelFormat {
    MTLRenderPipelineColorAttachmentDescriptor *colorAttachmentDescriptor = [[MTLRenderPipelineColorAttachmentDescriptor alloc] init];
    colorAttachmentDescriptor.pixelFormat = colorAttachmentPixelFormat;
    colorAttachmentDescriptor.blendingEnabled = NO;
    return [self initWithVertexFunctionDescriptor:vertexFunctionDescriptor
                       fragmentFunctionDescriptor:fragmentFunctionDescriptor
                                 vertexDescriptor:nil
                        colorAttachmentDescriptor:colorAttachmentDescriptor];
}

- (instancetype)initWithVertexFunctionDescriptor:(MTIFilterFunctionDescriptor *)vertexFunctionDescriptor fragmentFunctionDescriptor:(MTIFilterFunctionDescriptor *)fragmentFunctionDescriptor vertexDescriptor:(MTLVertexDescriptor *)vertexDescriptor colorAttachmentDescriptor:(MTLRenderPipelineColorAttachmentDescriptor *)colorAttachmentDescriptor {
    if (self = [super init]) {
        _vertexFunctionDescriptor = [vertexFunctionDescriptor copy];
        _fragmentFunctionDescriptor = [fragmentFunctionDescriptor copy];
        _vertexDescriptor = [vertexDescriptor copy];
        _colorAttachmentDescriptor = [colorAttachmentDescriptor copy];
    }
    return self;
}

- (MTLPixelFormat)pixelFormat {
    return self.colorAttachmentDescriptor.pixelFormat;
}

- (MTIRenderPipeline *)newKernelStateWithContext:(MTIContext *)context error:(NSError * _Nullable __autoreleasing *)inOutError {
    MTLRenderPipelineDescriptor *renderPipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    renderPipelineDescriptor.vertexDescriptor = self.vertexDescriptor;
    
    NSError *error;
    id<MTLFunction> vertextFunction = [context functionWithDescriptor:self.vertexFunctionDescriptor error:&error];
    if (error) {
        if (inOutError) {
            *inOutError = error;
        }
        return nil;
    }
    
    id<MTLFunction> fragmentFunction = [context functionWithDescriptor:self.fragmentFunctionDescriptor error:&error];
    if (error) {
        if (inOutError) {
            *inOutError = error;
        }
        return nil;
    }
    
    renderPipelineDescriptor.vertexFunction = vertextFunction;
    renderPipelineDescriptor.fragmentFunction = fragmentFunction;
    
    renderPipelineDescriptor.colorAttachments[0] = self.colorAttachmentDescriptor;
    renderPipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatInvalid;
    renderPipelineDescriptor.stencilAttachmentPixelFormat = MTLPixelFormatInvalid;
    
    return [context renderPipelineWithDescriptor:renderPipelineDescriptor error:inOutError];
}

- (id)applyWithInputImages:(NSArray *)images parameters:(NSDictionary<NSString *,id> *)parameters outputTextureDescriptor:(MTLTextureDescriptor *)outputTextureDescriptor {
    NSParameterAssert(outputTextureDescriptor.pixelFormat == self.colorAttachmentDescriptor.pixelFormat);
    MTIImageRenderingRecipe *receipt = [[MTIImageRenderingRecipe alloc] initWithKernel:self
                                                                           inputImages:images
                                                            fragmentFunctionParameters:parameters
                                                               outputTextureDescriptor:outputTextureDescriptor];
    return [[MTIImage alloc] initWithPromise:receipt];
}

@end
