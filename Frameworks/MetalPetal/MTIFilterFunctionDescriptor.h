//
//  MTIFilterFunctionDescriptor.h
//  Pods
//
//  Created by YuAo on 25/06/2017.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTIFilterFunctionDescriptor : NSObject <NSCopying>

@property (nonatomic, copy, readonly, nullable) NSURL *libraryURL;

@property (nonatomic, copy, readonly) NSString *name;

- (instancetype)init NS_UNAVAILABLE;

//这个可以直接在shader.metal里面拿到，.metel就是cpp
- (instancetype)initWithName:(NSString *)name;

//这个是在预编译之后从default.matlib里面读的
- (instancetype)initWithName:(NSString *)name libraryURL:( NSURL * _Nullable )URL NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
