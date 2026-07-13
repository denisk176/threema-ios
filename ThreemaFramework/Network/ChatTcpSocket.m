#import <Foundation/Foundation.h>
#import "ChatTcpSocket.h"
#import "GCDAsyncSocketFactory.h"
#import "SocketProtocolDelegate.h"

#ifdef DEBUG
  static const DDLogLevel ddLogLevel = DDLogLevelAll;
#else
  static const DDLogLevel ddLogLevel = DDLogLevelWarning;
#endif

// Tracks the index of the last port that won a connection race. Shared across all instances
// so each new connection starts from the previously successful port.
static NSUInteger _lastConnectedPortIndex = 0;

@implementation ChatTcpSocket {
    NSString *_server;
    NSArray<NSNumber *> *_ports;
    id<SocketProtocolDelegate> _delegate;
    dispatch_queue_t _queue;
    BOOL _preferIPv6;

    // Sockets still racing to connect, with their corresponding port at the same index.
    // Cleared once a winner is chosen or all candidates fail.
    NSMutableArray<GCDAsyncSocket *> *pendingSockets;
    NSMutableArray<NSNumber *> *pendingPorts;

    // Set once a socket wins the race; nil until then.
    GCDAsyncSocket *activeSocket;
}

- (nullable instancetype)initWithServer:(NSString * _Nonnull)server
                                  ports:(NSArray<NSNumber *> * _Nonnull)ports
                             preferIPv6:(BOOL)preferIPv6
                               delegate:(id<SocketProtocolDelegate> _Nonnull)delegate
                                  queue:(dispatch_queue_t _Nonnull)queue
                                  error:(NSError * _Nullable __autoreleasing * _Nullable)error {
    self = [super init];
    if (self) {
        self->_server = server;
        self->_ports = ports;
        self->_delegate = delegate;
        self->_queue = queue;
        self->_preferIPv6 = preferIPv6;

        pendingSockets = [NSMutableArray array];
        pendingPorts = [NSMutableArray array];

        // Rotate from the last known-good port so it enters the race first.
        NSUInteger count = _ports.count;
        NSUInteger startPortIndex = (count > 0) ? (_lastConnectedPortIndex % count) : 0;
        for (NSUInteger i = 0; i < count; i++) {
            NSUInteger portIndex = (startPortIndex + i) % count;
            NSNumber *port = _ports[portIndex];
            GCDAsyncSocket *socket = [GCDAsyncSocketFactory proxyAwareAsyncSocketForHost:server
                                                                                  port:port
                                                                              delegate:self
                                                                         delegateQueue:queue];
            [socket setIPv4PreferredOverIPv6:!_preferIPv6];
            [pendingSockets addObject:socket];
            [pendingPorts addObject:port];
        }

        // All sockets share the same proxy configuration, so the first one is representative.
        GCDAsyncSocket *firstSocket = pendingSockets.firstObject;
        _isProxyConnection = (firstSocket != nil && ![firstSocket isMemberOfClass:[GCDAsyncSocket class]]);
    }
    return self;
}

- (BOOL)isIPv6 {
    return [activeSocket isIPv6];
}

- (BOOL)connect {
    DDLogInfo(@"[ChatTcpSocket] Connecting to %@ on ports %@ simultaneously...", _server, pendingPorts);

    NSMutableIndexSet *failedItems = [NSMutableIndexSet indexSet];
    for (NSUInteger i = 0; i < pendingSockets.count; i++) {
        NSError *err;
        if (![pendingSockets[i] connectToHost:_server
                                       onPort:[pendingPorts[i] unsignedShortValue]
                                  withTimeout:kConnectTimeout
                                        error:&err]) {
            DDLogWarn(@"[ChatTcpSocket] Could not start connect on port %@: %@", pendingPorts[i], err);
            [failedItems addIndex:i];
        }
    }

    [pendingSockets removeObjectsAtIndexes:failedItems];
    [pendingPorts removeObjectsAtIndexes:failedItems];

    if (pendingSockets.count == 0) {
        DDLogWarn(@"[ChatTcpSocket] All connect attempts failed to start");
        return NO;
    }
    return YES;
}

- (void)disconnect {
    // Give the socket time for pending writes, but force disconnect if it takes too long for them to complete
    if (activeSocket != nil) {
        [activeSocket disconnectAfterWriting];

        GCDAsyncSocket *socketToDisconnect = activeSocket;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDisconnectTimeout * NSEC_PER_SEC)), _queue, ^{
            if (self->activeSocket == socketToDisconnect) {
                DDLogInfo(@"[ChatTcpSocket] Socket still not disconnected - forcing disconnect now");
                [self->activeSocket disconnect];
            }
        });
    } else {
        // Race not yet decided — cancel all pending sockets.
        NSArray<GCDAsyncSocket *> *toCancel = [pendingSockets copy];
        [pendingSockets removeAllObjects];
        [pendingPorts removeAllObjects];
        for (GCDAsyncSocket *socket in toCancel) {
            [socket disconnect];
        }
    }
}

- (void)readWithLength:(uint32_t)length timeout:(int16_t)timeout tag:(int16_t)tag {
    [activeSocket readDataToLength:length withTimeout:timeout tag:tag];
}

- (void)writeWithData:(NSData * _Nonnull)data tag:(int16_t)tag {
    [activeSocket writeData:data withTimeout:kWriteTimeout tag:tag];
}

- (void)writeWithData:(NSData * _Nonnull)data {
}

#pragma mark - GCDAsyncSocketDelegate

- (void)socket:(GCDAsyncSocket *)sender didConnectToHost:(NSString *)host port:(UInt16)port {
    if (activeSocket != nil) {
        // Another socket already won the race — disconnect this latecomer silently.
        [sender disconnect];
        return;
    }

    NSUInteger winnerIndex = [pendingSockets indexOfObject:sender];
    if (winnerIndex == NSNotFound) {
        [sender disconnect];
        return;
    }

    activeSocket = sender;

    // Persist the winning port index so the next instance starts its race from here.
    NSNumber *winningPort = pendingPorts[winnerIndex];
    NSUInteger globalPortIndex = [_ports indexOfObject:winningPort];
    _lastConnectedPortIndex = (globalPortIndex != NSNotFound) ? globalPortIndex : 0;

    // Disconnect all other pending sockets. Their socketDidDisconnect callbacks
    // will be ignored because they are no longer in pendingSockets.
    NSArray<GCDAsyncSocket *> *defeatedSockets = [pendingSockets copy];
    [pendingSockets removeAllObjects];
    [pendingPorts removeAllObjects];
    for (GCDAsyncSocket *defeated in defeatedSockets) {
        if (defeated != activeSocket) {
            [defeated disconnect];
        }
    }

    DDLogInfo(@"[ChatTcpSocket] Connected to %@:%d", host, port);
    [_delegate didConnect];
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sender withError:(NSError *)error {
    if (sender == activeSocket) {
        NSInteger code = 0;
        if (error != nil) {
            DDLogError(@"[ChatTcpSocket] Disconnect from chat server with error: %@", error);
            code = error.code;
        }
        activeSocket = nil;
        DDLogInfo(@"[ChatTcpSocket] Disconnected from %@:%d", [sender connectedHost], [sender connectedPort]);
        [_delegate didDisconnectWithErrorCode:code];
        return;
    }

    NSUInteger idx = [pendingSockets indexOfObject:sender];
    if (idx != NSNotFound) {
        DDLogWarn(@"[ChatTcpSocket] Connect attempt on port %@ failed: %@", pendingPorts[idx], error);
        [pendingSockets removeObjectAtIndex:idx];
        [pendingPorts removeObjectAtIndex:idx];

        if (pendingSockets.count == 0 && activeSocket == nil) {
            // All candidates exhausted without a successful connection.
            DDLogInfo(@"[ChatTcpSocket] All connection attempts failed");
            [_delegate didDisconnectWithErrorCode:(error != nil ? error.code : 0)];
        }
        return;
    }

    // Defeated socket being cleaned up after the race — nothing to do.
}

- (void)socket:(GCDAsyncSocket *)sender didReadData:(NSData *)data withTag:(long)tag {
    if (sender != activeSocket) {
        DDLogWarn(@"[ChatTcpSocket] didReadData from non-active socket");
        return;
    }
    [_delegate didReadData:data tag:(int16_t)tag];
}

- (NSTimeInterval)socket:(GCDAsyncSocket *)sender shouldTimeoutReadWithTag:(long)tag elapsed:(NSTimeInterval)elapsed bytesDone:(NSUInteger)length {
    if (sender != activeSocket) {
        return 0;
    }
    DDLogInfo(@"[ChatTcpSocket] Read timeout, tag = %ld", tag);
    [activeSocket disconnect];
    return 0;
}

- (NSTimeInterval)socket:(GCDAsyncSocket *)sender shouldTimeoutWriteWithTag:(long)tag elapsed:(NSTimeInterval)elapsed bytesDone:(NSUInteger)length {
    if (sender != activeSocket) {
        return 0;
    }
    DDLogInfo(@"[ChatTcpSocket] Write timeout, tag = %ld", tag);
    [activeSocket disconnect];
    return 0;
}

@end
