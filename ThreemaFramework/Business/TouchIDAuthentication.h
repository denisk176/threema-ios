#import <Foundation/Foundation.h>

@interface TouchIDAuthentication : NSObject

+ (void)tryTouchIDAuthenticationCallback:(void(^)(BOOL success, NSError *error, NSData *data))callback
    NS_SWIFT_NAME(tryTouchIDAuthentication(callback:));

@end
