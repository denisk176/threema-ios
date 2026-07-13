#import "ThreemaFramework/ThreemaFramework-Swift.h"
#import "GCDAsyncSocket.h"

#ifndef ChatTcpSocket_h
#define ChatTcpSocket_h


#endif /* ChatTcpSocket_h */

@interface ChatTcpSocket : NSObject <SocketProtocol, GCDAsyncSocketDelegate>

@property (readonly) BOOL isIPv6;
@property (readonly) BOOL isProxyConnection;

- (nullable instancetype)initWithServer:(NSString * _Nonnull)server
                                  ports:(NSArray<NSNumber *> * _Nonnull)ports
                             preferIPv6:(BOOL)preferIPv6
                               delegate:(id<SocketProtocolDelegate> _Nonnull)delegate
                                  queue:(dispatch_queue_t _Nonnull)queue
                                  error:(NSError * _Nullable __autoreleasing * _Nullable)error;

@end
