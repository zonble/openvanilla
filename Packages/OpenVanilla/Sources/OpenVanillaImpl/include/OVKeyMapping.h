#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import "OpenVanilla.h"

NS_ASSUME_NONNULL_BEGIN

@interface OVKeyMapping : NSObject

+ (UniChar)remapCode:(UniChar)code NS_SWIFT_NAME(remap(code:));

@end

NS_ASSUME_NONNULL_END
