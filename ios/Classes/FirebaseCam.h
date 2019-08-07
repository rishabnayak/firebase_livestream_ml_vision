#import <AVFoundation/AVFoundation.h>
#import "FirebaseLivestreamMlVisionPlugin.h"
#import <Flutter/Flutter.h>
#import <libkern/OSAtomic.h>
#import "UserAgent.h"

@interface FirebaseCam : NSObject <FlutterTexture,
AVCaptureVideoDataOutputSampleBufferDelegate,
AVCaptureAudioDataOutputSampleBufferDelegate,
FlutterStreamHandler>
@property(assign, atomic) BOOL isRecognizingStream;
@property(readonly, nonatomic) int64_t textureId;
@property(nonatomic, copy) void (^onFrameAvailable)();
@property(nonatomic) id<Detector> activeDetector;
@property(nonatomic) FlutterEventChannel *eventChannel;
@property(nonatomic) FlutterEventSink eventSink;
@property(readonly, nonatomic) AVCaptureSession *captureSession;
@property(readonly, nonatomic) AVCaptureDevice *captureDevice;
@property(readonly, nonatomic) AVCaptureVideoDataOutput *captureVideoOutput;
@property(readonly, nonatomic) AVCaptureInput *captureVideoInput;
@property(readonly) CVPixelBufferRef volatile latestPixelBuffer;
@property(readonly, nonatomic) CGSize previewSize;

- (instancetype)initWithCameraName:(NSString *)cameraName
                  resolutionPreset:(NSString *)resolutionPreset
                     dispatchQueue:(dispatch_queue_t)dispatchQueue
                             error:(NSError **)error;

- (void)start;
- (void)stop;
- (void)close;
@end
