#import <Foundation/Foundation.h>

@protocol AutoFillXCPServiceProtocol <NSObject>

- (void)getMessageWithReply:(void (^)(NSString *message, NSError *error))reply;

@end
