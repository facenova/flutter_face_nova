#import <Foundation/Foundation.h>

@interface LvGuard : NSObject
+ (BOOL)verifyLicense:(NSString *)token;
+ (NSData *)decryptModel:(int)modelId;
@end
