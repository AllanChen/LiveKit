//
//  MSStreamRTPUDPSocket.m
//  Pods
//
//  Created by hyq on 16/9/29.
//
//

#import "LFStreamRTPUDPSocket.h"
#import "rtpWrapper.h"

static const NSInteger RetryTimesBreaken = 20;  ///<  重连1分钟  3秒一次 一共20次
static const NSInteger RetryTimesMargin = 3;

@interface LFStreamRTPUDPSocket()<LFStreamingBufferDelegate>
{
}
@property (nonatomic, weak) id<LFStreamSocketDelegate> delegate;
@property (nonatomic, strong) LFLiveStreamInfo *stream;
@property (nonatomic, strong) LFStreamingBuffer *buffer;
@property (nonatomic, strong) LFStreamingBuffer *audioBuffer;
@property (nonatomic, strong) LFLiveDebug *debugInfo;
@property (nonatomic, strong) dispatch_queue_t rtpSendQueue;
@property (nonatomic, strong) dispatch_queue_t rtpAudioSendQueue;
//错误信息
@property (nonatomic, assign) NSInteger retryTimes4netWorkBreaken;
@property (nonatomic, assign) NSInteger reconnectInterval;
@property (nonatomic, assign) NSInteger reconnectCount;

@property (atomic, assign) BOOL isSending;
@property (atomic, assign) BOOL isSendingAudio;
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, assign) BOOL isConnecting;
@property (nonatomic, assign) BOOL isReconnecting;

@property (nonatomic, assign) BOOL sendVideoHead;
@property (nonatomic, assign) BOOL sendAudioHead;
@end

@implementation LFStreamRTPUDPSocket


#pragma mark -- LFStreamSocket
- (nullable instancetype)initWithStream:(nullable LFLiveStreamInfo *)stream{
    return [self initWithStream:stream reconnectInterval:0 reconnectCount:0];
}

- (nullable instancetype)initWithStream:(nullable LFLiveStreamInfo *)stream reconnectInterval:(NSInteger)reconnectInterval reconnectCount:(NSInteger)reconnectCount{
    if (!stream) @throw [NSException exceptionWithName:@"LFStreamRTPSocket init error" reason:@"stream is nil" userInfo:nil];
    if (self = [super init]) {
        _stream = stream;
        if (reconnectInterval > 0) _reconnectInterval = reconnectInterval;
        else _reconnectInterval = RetryTimesMargin;
        
        if (reconnectCount > 0) _reconnectCount = reconnectCount;
        else _reconnectCount = RetryTimesBreaken;
        
        [self addObserver:self forKeyPath:@"isSending" options:NSKeyValueObservingOptionNew context:nil];//这里改成observer主要考虑一直到发送出错情况下，可以继续发送
        [self addObserver:self forKeyPath:@"isSendingAudio" options:NSKeyValueObservingOptionNew context:nil];//这里改成observer主要考虑一直到发送出错情况下，可以继续发送
    }
    return self;
}

- (void)dealloc{
    [self removeObserver:self forKeyPath:@"isSending"];
    [self removeObserver:self forKeyPath:@"isSendingAudio"];
}

- (void)start {
    dispatch_async(self.rtpSendQueue, ^{
        [self _start];
    });
}

- (void)_start {
    if (!_stream) return;
    if (_isConnecting) return;
    self.debugInfo.streamId = self.stream.streamId;
    self.debugInfo.isRtmp = NO;
    
    rtpSetup([_stream.host UTF8String], _stream.port, _stream.port + 2);
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
        [self.delegate socketStatus:self status:LFLiveStart];
    }
}

- (void)stop {
    dispatch_async(self.rtpSendQueue, ^{
        [self _stop];
    });
}

- (void)_stop {
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
        [self.delegate socketStatus:self status:LFLiveStop];
    }

    rtpRelease();
    [self clean];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)sendFrame:(LFFrame *)frame {
    if (!frame) return;
    
    if ([frame isKindOfClass:[LFVideoFrame class]]) {
        [self.buffer appendObject:frame];
        
        if(!self.isSending){
            [self sendFrame];
        }
    }else {
        [self.audioBuffer appendObject:frame];
        
        if (!self.isSendingAudio) {
            [self sendAudioFrame];
        }
    }
}


- (void)sendFrame {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.rtpSendQueue, ^{
        if (weakSelf.isSending || weakSelf.buffer.list.count == 0) { return; }
        
        //发送状态YES
        weakSelf.isSending = YES;
        
        LFVideoFrame *frame = [weakSelf.buffer popFirstObject];
        uint32_t timestamp = (uint32_t)(frame.timestamp * 90);
        if (frame.isKeyFrame) {
            rtpSendH264Nalu((uint32_t)frame.sps.length, (uint8_t *)frame.sps.bytes, timestamp);
            rtpSendH264Nalu((uint32_t)frame.pps.length, (uint8_t *)frame.pps.bytes, timestamp);
        }
        rtpSendH264Nalu((uint32_t)frame.data.length, (uint8_t *)frame.data.bytes, timestamp);

        //发送状态NO（这里只为了不循环调用sendFrame方法 调用栈是保证先出栈再进栈）
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            weakSelf.isSending = NO;
        });
    });
}

- (void)sendAudioFrame {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.rtpAudioSendQueue, ^{
        if (weakSelf.isSendingAudio || weakSelf.audioBuffer.list.count == 0) { return; }
        
        //发送状态YES
        weakSelf.isSendingAudio = YES;
        
        LFFrame *frame = [weakSelf.audioBuffer popFirstObject];
        uint32_t timestamp = (uint32_t)(frame.timestamp * 90);
        
        float factor = 90 / (_stream.audioConfiguration.audioSampleRate/1000.0);
        timestamp = (float)timestamp / factor;
        rtpSendAAC((uint32_t)frame.data.length, (uint8_t *)frame.data.bytes, timestamp);
        
        //发送状态NO（这里只为了不循环调用sendFrame方法 调用栈是保证先出栈再进栈）
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            weakSelf.isSendingAudio = NO;
        });
    });
 
}

- (void)setDelegate:(id<LFStreamSocketDelegate>)delegate {
    _delegate = delegate;
}

- (LFStreamingBuffer *)buffer {
    if (!_buffer) {
        _buffer = [[LFStreamingBuffer alloc] init];
        _buffer.delegate = self;
        
    }
    return _buffer;
}

- (LFStreamingBuffer *)audioBuffer {
    if (!_audioBuffer) {
        _audioBuffer = [[LFStreamingBuffer alloc]init];
        _audioBuffer.delegate = self;
    }
    return _audioBuffer;
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
    }else if ([keyPath isEqualToString:@"isSendingAudio"]) {
        if (!self.isSendingAudio) {
            [self sendAudioFrame];
        }
    }
}


#pragma mark -- CustomMethod
- (void)clean {
    _isConnecting = NO;
    _isReconnecting = NO;
    _isSending = NO;
    _isSendingAudio = NO;
    _isConnected = NO;
    _sendAudioHead = NO;
    _sendVideoHead = NO;
    self.debugInfo = nil;
    [self.buffer removeAllObject];
    [self.audioBuffer removeAllObject];
    self.retryTimes4netWorkBreaken = 0;
}

- (dispatch_queue_t)rtpSendQueue{
    if(!_rtpSendQueue){
        _rtpSendQueue = dispatch_queue_create("com.yy.mshow.rtpSendQueue", NULL);
    }
    return _rtpSendQueue;
}

- (dispatch_queue_t)rtpAudioSendQueue {
    if (!_rtpAudioSendQueue) {
        _rtpAudioSendQueue = dispatch_queue_create("com.yy.mshow.rtpAudioSendQueue", NULL);
    }
    
    return _rtpAudioSendQueue;
}

@end
