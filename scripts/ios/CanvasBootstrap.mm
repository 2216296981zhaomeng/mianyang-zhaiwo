#import <Foundation/Foundation.h>
#import <objc/message.h>

// Give the canvas module its own Objective-C loader: DCloudUTSConfig is also
// defined by other UTS frameworks and is not a unique registration hook.
@interface ZWCanvasBootstrap : NSObject
@end

@implementation ZWCanvasBootstrap
+ (void)load {
    Class registrar = NSClassFromString(@"UniCanvasElementRegister");
    SEL selector = NSSelectorFromString(@"registerComponent");
    if (registrar && [registrar respondsToSelector:selector]) {
        ((void (*)(id, SEL))objc_msgSend)(registrar, selector);
    }
}
@end
