
//  LFStreamRTPTCPSocket.m
//  Pods
//
//  Created by hyq on 16/10/20.
//
//
#import "LFStreamRTPTCPSocket.h"
#import "rtpOverTcp.h"
#import "DDLoggerWrapper.h"

static const NSInteger RetryTimesBreaken = 20;  ///<  重连1分钟  3秒一次 一共20次
static const NSInteger RetryTimesMargin = 3;

NS_ENUM(NSInteger, RTPTCPState) {
    RTPTCPLogout,           //登出
    RTPTCPException,        //异常断开
    RTPTCPLogin,            //登录
    RTPTCPUnpublish,        //停止发布流
    RTPTCPPublish,          //开始发布流
};

@interface LFStreamRTPTCPSocket()<LFStreamingBufferDelegate>
{
}
@property (nonatomic, weak) id<LFStreamSocketDelegate> delegate;
@property (nonatomic, strong) LFLiveStreamInfo *stream;
@property (nonatomic, strong) LFStreamingBuffer *buffer;
@property (nonatomic, strong) LFLiveDebug *debugInfo;
@property (nonatomic, strong) dispatch_queue_t rtptcpSendQueue;
@property (nonatomic, strong) dispatch_queue_t rtptcpReceiveQueue;
//错误信息
@property (nonatomic, assign) NSInteger retryTimes4netWorkBreaken;
@property (nonatomic, assign) NSInteger reconnectInterval;
@property (nonatomic, assign) NSInteger reconnectCount;

@property (atomic, assign) BOOL isSending;
@property (atomic, assign) BOOL isStarted;
@property (nonatomic, assign) BOOL isStarting;
@property (nonatomic, assign) BOOL isNeedReConnect;
@property (nonatomic, assign) BOOL isReConnecting;
@property (nonatomic, assign) BOOL isReceiving;
@property (nonatomic, assign) enum RTPTCPState state;

@end

@implementation LFStreamRTPTCPSocket

#pragma mark -- LFStreamSocket
- (nullable instancetype)initWithStream:(nullable LFLiveStreamInfo *)stream{
    return [self initWithStream:stream reconnectInterval:0 reconnectCount:0];
}

- (nullable instancetype)initWithStream:(nullable LFLiveStreamInfo *)stream reconnectInterval:(NSInteger)reconnectInterval reconnectCount:(NSInteger)reconnectCount{
    if (!stream) @throw [NSException exceptionWithName:@"LFStreamRTPTCPSocket init error" reason:@"stream is nil" userInfo:nil];
    if (self = [super init]) {
        _stream = stream;
        if (reconnectInterval > 0) _reconnectInterval = reconnectInterval;
        else _reconnectInterval = RetryTimesMargin;
        
        if (reconnectCount > 0) _reconnectCount = reconnectCount;
        else _reconnectCount = RetryTimesBreaken;
        
        [self addObserver:self forKeyPath:@"isSending" options:NSKeyValueObservingOptionNew context:nil];//这里改成observer主要考虑一直到发送出错情况下，可以继续发送
        [self addObserver:self forKeyPath:@"isNeedReConnect" options:NSKeyValueObservingOptionNew context:nil];
    }
    return self;
}

- (void)dealloc{
    [self removeObserver:self forKeyPath:@"isSending"];
    [self removeObserver:self forKeyPath:@"isNeedReConnect"];
}

- (void)start {
    dispatch_async(self.rtptcpSendQueue, ^{
        [self _start];
    });
}

- (void)_start {
    if (!_stream) return;
    if (_isStarting || _isStarted) return;
    _isStarting = YES;
    _state = RTPTCPLogout;
    
    self.debugInfo.streamId = self.stream.streamId;
    self.debugInfo.isRtmp = NO;
    
    rtptcpSetup();
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
        [self.delegate socketStatus:self status:LFLivePending];
    }
    
    if(rtptcpConnect([_stream.host UTF8String], _stream.port, _uid) == 0) {
        _state = RTPTCPLogin;
        _isStarted = YES;
        
        if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
            [self.delegate socketStatus:self status:LFLiveStart];
        }
        
        [self dispatchReceive];
    }else {
        self.isNeedReConnect = YES;
        
        if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
            [self.delegate socketStatus:self status:LFLiveError];
        }
    }

}

- (void)stop {
    dispatch_async(self.rtptcpSendQueue, ^{
        [self _stop];
    });
}

- (void)_stop {
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
        [self.delegate socketStatus:self status:LFLiveStop];
    }
    
    NSLog(@"[RTPTCP] [_stop][uid=%lu]", _uid);
    rtptcpDisconnect();
    rtptcpRelease();
    [self clean];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)sendFrame:(LFFrame *)frame {
    if (!frame) return;
    [self.buffer appendObject:frame];
    
    if(!self.isSending){
        [self sendFrame];
    }
}



- (void)setDelegate:(id<LFStreamSocketDelegate>)delegate {
    _delegate = delegate;
}

- (LFStreamingBuffer *)buffer {
    if (!_buffer) {
        _buffer = [[LFStreamingBuffer alloc] init];
        _buffer.delegate = self;
        _buffer.maxCount = 25;//设置一个小的缓冲队列降低延时
        
    }
    return _buffer;
}

#pragma mark -- LFStreamingBufferDelegate
- (void)streamingBuffer:(nullable LFStreamingBuffer *)buffer bufferState:(LFLiveBuffferState)state{
    if(self.delegate && [self.delegate respondsToSelector:@selector(socketBufferStatus:status:)]){
        [self.delegate socketBufferStatus:self status:state];
    }
}

#pragma mark -- Observer
-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context{
    if([keyPath isEqualToString:@"isSending"]){
        if(!self.isSending){
            [self sendFrame];
        }
    }else if ([keyPath isEqualToString:@"isNeedReConnect"]) {
        if (self.isStarted) {
            [self dispatchReconnect];
        }
    }
}


#pragma mark -- CustomMethod
- (void)clean {
    _isSending = NO;
    _isReConnecting = NO;
    _isStarting = NO;
    _isStarted = NO;
    _isReceiving = NO;
    _state = RTPTCPLogout;
    _debugInfo = nil;
    self.isNeedReConnect = NO;
    [_buffer removeAllObject];
    _retryTimes4netWorkBreaken = 0;
}

- (dispatch_queue_t)rtptcpSendQueue{
    if(!_rtptcpSendQueue){
        _rtptcpSendQueue = dispatch_queue_create("com.yy.mshow.rtptcpSendQueue", NULL);
    }
    return _rtptcpSendQueue;
}

- (dispatch_queue_t)rtptcpReceiveQueue {
    if (!_rtptcpReceiveQueue) {
        _rtptcpReceiveQueue = dispatch_queue_create("com.yy.mshow.rtptcpConnectQueue", NULL);
    }
    return _rtptcpReceiveQueue;
}


#pragma mark -- RTPOVERTCP

- (void)sendFrame {
    __weak typeof(self) weakSelf = self;
    dispatch_async(_rtptcpSendQueue, ^{
        if (weakSelf.isSending || weakSelf.buffer.list.count == 0) { return; }
        
        //发送状态YES
        weakSelf.isSending = YES;
        
        [weakSelf rtptcpSendFrame];
        
        //发送状态NO（这里只为了不循环调用sendFrame方法 调用栈是保证先出栈再进栈）
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            weakSelf.isSending = NO;
        });
    });
}

- (NSInteger)sendVideoData:(uint32_t)length data:(uint8_t *)data timestamp:(uint32_t)timestamp {
    if(rtptcpSendH264Nalu(length, data, timestamp) < 0) {
        _state = RTPTCPException;
        return -1;
    }
    return 0;
}

- (NSInteger)sendAudioData:(uint32_t)length data:(uint8_t *)data timestamp:(uint32_t)timestamp {
    if(rtptcpSendAAC(length, data, timestamp) < 0) {
        _state = RTPTCPException;
        return -1;
    }
    return 0;
}

- (void)rtptcpSendFrame {
    LFFrame *frame = [self.buffer popFirstObject];
    if (!frame) { return; }
    
    if (!_isStarted || _state != RTPTCPPublish) return;
    
    uint32_t timestamp = (uint32_t)(frame.timestamp * 90);
    if ([frame isKindOfClass:[LFVideoFrame class]]) {
//        NSLog(@"[RTPTCP][sendVideo] ts1=%u, ts2=%u", frame.timestamp, timestamp);
        LFVideoFrame *videoFrame = (LFVideoFrame *)frame;
        if (videoFrame.isKeyFrame) {

            if ([self sendVideoData:(uint32_t)videoFrame.sps.length data:(uint8_t *)videoFrame.sps.bytes timestamp:timestamp] < 0)  return;
            
            if ([self sendVideoData:(uint32_t)videoFrame.pps.length data:(uint8_t *)videoFrame.pps.bytes timestamp:timestamp] < 0) return;
        }
        
        if ([self sendVideoData:(uint32_t)frame.data.length data:(uint8_t *)frame.data.bytes timestamp:timestamp] < 0) return;
    }else {
        float factor = 90 / (_stream.audioConfiguration.audioSampleRate/1000.0);
        timestamp = (float)timestamp / factor;
        [self sendAudioData:(uint32_t)frame.data.length data:(uint8_t *)frame.data.bytes timestamp:timestamp];
    }
}

- (void)dispatchReconnect {
    __weak typeof (self) wSelf = self;
    dispatch_async(self.rtptcpReceiveQueue, ^{
        
        NSLog(@"[RTPTCP] [dispatchReconnect] Reconnecting=%d, need=%d", wSelf.isReConnecting, wSelf.isNeedReConnect);
        if (wSelf.isReConnecting || !wSelf.isNeedReConnect) return;
       
        wSelf.isReConnecting = YES;
        [wSelf reconnect];
        wSelf.isReConnecting = NO;
    });
}

- (void)reconnect {
    NSLog(@"[RTPTCP] [reconnect] begin uid=%lu", _uid);
    while (self.isStarted) {
        rtptcpDisconnect();
        
        if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
            [self.delegate socketStatus:self status:LFLivePending];
        }
        
        if (rtptcpConnect([_stream.host UTF8String], _stream.port, (uint32_t)_uid) == 0) {
            self.isNeedReConnect = NO;
            
            if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
                [self.delegate socketStatus:self status:LFLiveStart];
            }
            _state = RTPTCPLogin;
            [self dispatchReceive];
            NSLog(@"[RTPTCP] [reconnect] success uid=%lu", _uid);
            break;
        }
        usleep(5 * 1000 * 1000);
    }
    NSLog(@"[RTPTCP] [reconnect] end uid=%lu", _uid);
}


- (void)dispatchReceive {
    __weak typeof (self) wSelf = self;
    dispatch_async(self.rtptcpReceiveQueue, ^{
        
        if (wSelf.isReceiving) return;
        
        wSelf.isReceiving = YES;
        [wSelf receive];
        wSelf.isReceiving = NO;
    });
}

- (void)receive {
    while (self.isStarted) {
        NSInteger message = rtptcpRecvMessage();
        if (message < 0) {
            NSLog(@"[RTPTCP] [receive] error uid=%lu", _uid);
            __weak typeof (self) wSelf = self;
            //为了保证stop的瞬间，不会进行重连
            dispatch_async(self.rtptcpSendQueue, ^{
                
                if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
                    [self.delegate socketStatus:self status:LFLiveError];
                }
                wSelf.isNeedReConnect = YES;
            });
            
            if (_state != RTPTCPLogout) {
                _state = RTPTCPException;
            }
            break;
        }
        
        switch (message) {
            case MSG_PUBLISH:
                NSLog(@"[RTPTCP] [receive] message publish uid=%lu", _uid);
                _state = RTPTCPPublish;
                break;
            case MSG_UNPUBLISH:
                _state = RTPTCPUnpublish;
                NSLog(@"[RTPTCP] [receive] message unpublish uid=%lu", _uid);
                break;
            case MSG_LOGOUT:
                _state = RTPTCPLogout;
                NSLog(@"[RTPTCP] [receive] message logout uid=%lu", _uid);
                break;
            default:
                break;
        }
    }
}

- (BOOL)isNeedReConnect {
    return _isNeedReConnect && _state != RTPTCPLogout;
}

@end
