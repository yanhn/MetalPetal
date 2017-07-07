//
//  MTIColorInvertFilter.m
//  Pods
//
//  Created by YuAo on 27/06/2017.
//
//

#import "MTIColorInvertFilter.h"
#import "MTIFilterFunctionDescriptor.h"
#import "MTIImage.h"
#import "MTIKernel.h"
#import "MTIRenderPipelineKernel.h"

@implementation MTIColorInvertFilter
//四件事儿：1.干啥，通过kearnel来做，这个kearnel是个renderlinestate，同一个滤镜可以用同一个kearnel，一个kearnel生成了一个renderlinestate，返回给context，context会检查一下是否是相同的renderlinestate，如果是就不替换沿用原来的，否才替换。
//2.输出啥，通过textureDescriptor来设置了输出格式。
//3.输入啥，那个inputtexture，
//4.参数是啥，就是最后干的了，现在的参数传递思路是renderlinestate和computelinestate都不用管具体该咋给gpu传参，只是传递一个字典就可以。
//然后这个东西会在XX里解析，根据shader的reflection来检索名字，如果名字对了，检索数据类型，根据不同的数据类型会调用不同的传参的函数来进行传参。
//好处：1.可以维护一个cache，如果参数不变不传？，不必每帧都传参数，2.对renderline和computeline是透明的，也不必每个line都去根据program来找到location然后传。要传参数的时候可以一批都传完。
+ (MTIRenderPipelineKernel *)kernel {
    static MTIRenderPipelineKernel *kernel;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        kernel = [[MTIRenderPipelineKernel alloc] initWithVertexFunctionDescriptor:[[MTIFilterFunctionDescriptor alloc] initWithName:MTIFilterPassthroughVertexFunctionName]
                                                        fragmentFunctionDescriptor:[[MTIFilterFunctionDescriptor alloc] initWithName:@"colorInvert"]
                                                        colorAttachmentPixelFormat:MTLPixelFormatBGRA8Unorm_sRGB];
    });
    return kernel;
}

- (MTIImage *)outputImage {
    if (!self.inputImage) {
        return nil;
    }
    MTLTextureDescriptor *outputTextureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:self.class.kernel.pixelFormat width:self.inputImage.size.width height:self.inputImage.size.height mipmapped:NO];
    outputTextureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    return [self.class.kernel applyWithInputImages:@[self.inputImage] parameters:@{} outputTextureDescriptor:outputTextureDescriptor];
}

@end
