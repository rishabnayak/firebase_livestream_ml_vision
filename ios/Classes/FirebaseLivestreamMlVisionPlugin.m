#import "FirebaseLivestreamMlVisionPlugin.h"
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <CoreMotion/CoreMotion.h>
#import <libkern/OSAtomic.h>
#import "UserAgent.h"

static FlutterError *getFlutterError(NSError *error) {
    return [FlutterError errorWithCode:[NSString stringWithFormat:@"Error %d", (int)error.code]
                               message:error.domain
                               details:error.localizedDescription];
}

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

@implementation FirebaseCam {
    dispatch_queue_t _dispatchQueue;
}

// Format used for video and image streaming.
FourCharCode const format = kCVPixelFormatType_32BGRA;

- (instancetype)initWithCameraName:(NSString *)cameraName
                  resolutionPreset:(NSString *)resolutionPreset
                     dispatchQueue:(dispatch_queue_t)dispatchQueue
                             error:(NSError **)error {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _dispatchQueue = dispatchQueue;
    _captureSession = [[AVCaptureSession alloc] init];
    _captureDevice = [AVCaptureDevice deviceWithUniqueID:cameraName];
    NSError *localError = nil;
    _captureVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:_captureDevice
                                                               error:&localError];
    if (localError) {
        *error = localError;
        return nil;
    }
    _captureVideoOutput = [AVCaptureVideoDataOutput new];
    _captureVideoOutput.videoSettings =
    @{(NSString *)kCVPixelBufferPixelFormatTypeKey : @(format)};
    [_captureVideoOutput setAlwaysDiscardsLateVideoFrames:YES];
    [_captureVideoOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    AVCaptureConnection *connection =
    [AVCaptureConnection connectionWithInputPorts:_captureVideoInput.ports
                                           output:_captureVideoOutput];
    if ([_captureDevice position] == AVCaptureDevicePositionFront) {
        connection.videoMirrored = YES;
    }
    connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    [_captureSession addInputWithNoConnections:_captureVideoInput];
    [_captureSession addOutputWithNoConnections:_captureVideoOutput];
    [_captureSession addConnection:connection];
    [self setCaptureSessionPreset:resolutionPreset];
    return self;
}

- (void)imageOrientation {
    [self imageOrientationFromDevicePosition:AVCaptureDevicePositionBack];
}

- (UIImageOrientation)imageOrientationFromDevicePosition:(AVCaptureDevicePosition)devicePosition {
    UIDeviceOrientation deviceOrientation = UIDevice.currentDevice.orientation;
    if (deviceOrientation == UIDeviceOrientationFaceDown ||
        deviceOrientation == UIDeviceOrientationFaceUp ||
        deviceOrientation == UIDeviceOrientationUnknown) {
        deviceOrientation = [self currentUIOrientation];
    }
    switch (deviceOrientation) {
        case UIDeviceOrientationPortrait:
            return devicePosition == AVCaptureDevicePositionFront ? UIImageOrientationLeftMirrored
            : UIImageOrientationRight;
        case UIDeviceOrientationLandscapeLeft:
            return devicePosition == AVCaptureDevicePositionFront ? UIImageOrientationDownMirrored
            : UIImageOrientationUp;
        case UIDeviceOrientationPortraitUpsideDown:
            return devicePosition == AVCaptureDevicePositionFront ? UIImageOrientationRightMirrored
            : UIImageOrientationLeft;
        case UIDeviceOrientationLandscapeRight:
            return devicePosition == AVCaptureDevicePositionFront ? UIImageOrientationUpMirrored
            : UIImageOrientationDown;
        case UIDeviceOrientationFaceDown:
        case UIDeviceOrientationFaceUp:
        case UIDeviceOrientationUnknown:
            return UIImageOrientationUp;
    }
}

- (FIRVisionDetectorImageOrientation)visionImageOrientationFromImageOrientation:
(UIImageOrientation)imageOrientation {
    switch (imageOrientation) {
        case UIImageOrientationUp:
            return FIRVisionDetectorImageOrientationTopLeft;
        case UIImageOrientationDown:
            return FIRVisionDetectorImageOrientationBottomRight;
        case UIImageOrientationLeft:
            return FIRVisionDetectorImageOrientationLeftBottom;
        case UIImageOrientationRight:
            return FIRVisionDetectorImageOrientationRightTop;
        case UIImageOrientationUpMirrored:
            return FIRVisionDetectorImageOrientationTopRight;
        case UIImageOrientationDownMirrored:
            return FIRVisionDetectorImageOrientationBottomLeft;
        case UIImageOrientationLeftMirrored:
            return FIRVisionDetectorImageOrientationLeftTop;
        case UIImageOrientationRightMirrored:
            return FIRVisionDetectorImageOrientationRightBottom;
    }
}

- (UIDeviceOrientation)currentUIOrientation {
    UIDeviceOrientation (^deviceOrientation)(void) = ^UIDeviceOrientation(void) {
        switch (UIApplication.sharedApplication.statusBarOrientation) {
            case UIInterfaceOrientationLandscapeLeft:
                return UIDeviceOrientationLandscapeRight;
            case UIInterfaceOrientationLandscapeRight:
                return UIDeviceOrientationLandscapeLeft;
            case UIInterfaceOrientationPortraitUpsideDown:
                return UIDeviceOrientationPortraitUpsideDown;
            case UIInterfaceOrientationPortrait:
            case UIInterfaceOrientationUnknown:
                return UIDeviceOrientationPortrait;
        }
    };
    
    if (NSThread.isMainThread) {
        return deviceOrientation();
    } else {
        __block UIDeviceOrientation currentOrientation = UIDeviceOrientationPortrait;
        dispatch_sync(dispatch_get_main_queue(), ^{
            currentOrientation = deviceOrientation();
        });
        return currentOrientation;
    }
}

- (void)start {
    [_captureSession startRunning];
}

- (void)stop {
    [_captureSession stopRunning];
}

- (void)setCaptureSessionPreset:(NSString *)resolutionPreset {
    int presetIndex;
    if ([resolutionPreset isEqualToString:@"high"]) {
        presetIndex = 2;
    } else if ([resolutionPreset isEqualToString:@"medium"]) {
        presetIndex = 3;
    } else {
        NSAssert([resolutionPreset isEqualToString:@"low"], @"Unknown resolution preset %@",
                 resolutionPreset);
        presetIndex = 4;
    }
    switch (presetIndex) {
        case 0:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset3840x2160]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset3840x2160;
                _previewSize = CGSizeMake(3840, 2160);
                break;
            }
        case 1:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset1920x1080]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset1920x1080;
                _previewSize = CGSizeMake(1920, 1080);
                break;
            }
        case 2:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset1280x720;
                _previewSize = CGSizeMake(1280, 720);
                break;
            }
        case 3:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset640x480]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset640x480;
                _previewSize = CGSizeMake(640, 480);
                break;
            }
        case 4:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset352x288]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset352x288;
                _previewSize = CGSizeMake(352, 288);
                break;
            }
        default: {
            NSException *exception = [NSException
                                      exceptionWithName:@"NoAvailableCaptureSessionException"
                                      reason:@"No capture session available for current capture session."
                                      userInfo:nil];
            @throw exception;
        }
    }
}

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    if (output == _captureVideoOutput) {
        CVImageBufferRef newBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        CFRetain(newBuffer);
        CVPixelBufferRef old = _latestPixelBuffer;
        while (!OSAtomicCompareAndSwapPtrBarrier(old, newBuffer, (void **)&_latestPixelBuffer)) {
            old = _latestPixelBuffer;
        }
        if (old != nil) {
            CFRelease(old);
        }
        if (_onFrameAvailable) {
            _onFrameAvailable();
        }
    }
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        _eventSink(@{
            @"event" : @"error",
            @"errorDescription" : @"sample buffer is not ready. Skipping sample"
        });
        return;
    }
    if (!_isRecognizingStream) {
        if (_eventSink) {
            _isRecognizingStream = YES;
            FIRVisionImage *visionImage = [[FIRVisionImage alloc] initWithBuffer:sampleBuffer];
            FIRVisionImageMetadata *metadata = [[FIRVisionImageMetadata alloc] init];
            UIImageOrientation orientation = [self
                                              imageOrientationFromDevicePosition:[_captureDevice position] == AVCaptureDevicePositionFront ? AVCaptureDevicePositionFront
                                              : AVCaptureDevicePositionBack];
            FIRVisionDetectorImageOrientation visionOrientation =
            [self visionImageOrientationFromImageOrientation:orientation];
            metadata.orientation = visionOrientation;
            visionImage.metadata = metadata;
            [_activeDetector handleDetection:visionImage result:_eventSink];
            _isRecognizingStream = NO;
        }
    }
}

- (void)close {
    [_captureSession stopRunning];
    for (AVCaptureInput *input in [_captureSession inputs]) {
        [_captureSession removeInput:input];
    }
    for (AVCaptureOutput *output in [_captureSession outputs]) {
        [_captureSession removeOutput:output];
    }
}

- (void)dealloc {
    if (_latestPixelBuffer) {
        CFRelease(_latestPixelBuffer);
    }
}

- (CVPixelBufferRef)copyPixelBuffer {
    CVPixelBufferRef pixelBuffer = _latestPixelBuffer;
    while (!OSAtomicCompareAndSwapPtrBarrier(pixelBuffer, nil, (void **)&_latestPixelBuffer)) {
        pixelBuffer = _latestPixelBuffer;
    }
    
    return pixelBuffer;
}

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
    _eventSink = nil;
    return nil;
}

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(nonnull FlutterEventSink)events {
    _eventSink = events;
    return nil;
}
@end

@interface FLTFirebaseLivestreamMlVisionPlugin ()
@property(readonly, nonatomic) NSObject<FlutterTextureRegistry> *registry;
@property(readonly, nonatomic) NSObject<FlutterBinaryMessenger> *messenger;
@property(readonly, nonatomic) FirebaseCam *camera;
@end

@implementation FLTFirebaseLivestreamMlVisionPlugin {
    dispatch_queue_t _dispatchQueue;
}

static NSMutableDictionary<NSNumber *, id<Detector>> *detectors;

+ (void)handleError:(NSError *)error result:(FlutterResult)result {
    result(getFlutterError(error));
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    detectors = [NSMutableDictionary new];
    FlutterMethodChannel *channel =
    [FlutterMethodChannel methodChannelWithName:@"plugins.flutter.io/firebase_livestream_ml_vision"
                                binaryMessenger:[registrar messenger]];
    FLTFirebaseLivestreamMlVisionPlugin *instance = [[FLTFirebaseLivestreamMlVisionPlugin alloc] initWithRegistry:[registrar textures]
                                                                                    messenger:[registrar messenger]];
    [registrar addMethodCallDelegate:instance channel:channel];
    
    SEL sel = NSSelectorFromString(@"registerLibrary:withVersion:");
    if ([FIRApp respondsToSelector:sel]) {
        [FIRApp performSelector:sel withObject:LIBRARY_NAME withObject:LIBRARY_VERSION];
    }
}

- (instancetype)initWithRegistry:(NSObject<FlutterTextureRegistry> *)registry
                       messenger:(NSObject<FlutterBinaryMessenger> *)messenger{
    self = [super init];
    if (self) {
        if (![FIRApp appNamed:@"__FIRAPP_DEFAULT"]) {
            NSLog(@"Configuring the default Firebase app...");
            [FIRApp configure];
            NSLog(@"Configured the default Firebase app %@.", [FIRApp defaultApp].name);
            _registry = registry;
            _messenger = messenger;
        }
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if (_dispatchQueue == nil) {
        _dispatchQueue = dispatch_queue_create("io.flutter.camera.dispatchqueue", NULL);
    }
    
    // Invoke the plugin on another dispatch queue to avoid blocking the UI.
    dispatch_async(_dispatchQueue, ^{
        [self handleMethodCallAsync:call result:result];
    });
}

- (void)handleMethodCallAsync:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSString *modelName = call.arguments[@"model"];
    NSDictionary *options = call.arguments[@"options"];
    NSNumber *handle = call.arguments[@"handle"];
    if ([@"ModelManager#setupLocalModel" isEqualToString:call.method]) {
        [SetupLocalModel modelName:modelName result:result];
    } else if ([@"ModelManager#setupRemoteModel" isEqualToString:call.method]) {
        [SetupRemoteModel modelName:modelName result:result];
    } else if ([@"camerasAvailable" isEqualToString:call.method]){
        AVCaptureDeviceDiscoverySession *discoverySession = [AVCaptureDeviceDiscoverySession
                                                             discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeBuiltInWideAngleCamera ]
                                                             mediaType:AVMediaTypeVideo
                                                             position:AVCaptureDevicePositionUnspecified];
        NSArray<AVCaptureDevice *> *devices = discoverySession.devices;
        NSMutableArray<NSDictionary<NSString *, NSObject *> *> *reply =
        [[NSMutableArray alloc] initWithCapacity:devices.count];
        for (AVCaptureDevice *device in devices) {
            NSString *lensFacing;
            switch ([device position]) {
                case AVCaptureDevicePositionBack:
                    lensFacing = @"back";
                    break;
                case AVCaptureDevicePositionFront:
                    lensFacing = @"front";
                    break;
                case AVCaptureDevicePositionUnspecified:
                    lensFacing = @"external";
                    break;
            }
            [reply addObject:@{
                @"name" : [device uniqueID],
                @"lensFacing" : lensFacing,
                @"sensorOrientation" : @90,
            }];
        }
        result(reply);
    } else if ([@"initialize" isEqualToString:call.method]) {
        NSString *cameraName = call.arguments[@"cameraName"];
        NSString *resolutionPreset = call.arguments[@"resolutionPreset"];
        NSError *error;
        FirebaseCam *cam = [[FirebaseCam alloc] initWithCameraName:cameraName
                                                  resolutionPreset:resolutionPreset
                                                     dispatchQueue:_dispatchQueue
                                                             error:&error];
        if (error) {
            result(getFlutterError(error));
        } else {
            if (_camera) {
                [_camera close];
            }
            int64_t textureId = [_registry registerTexture:cam];
            _camera = cam;
            cam.onFrameAvailable = ^{
                [self->_registry textureFrameAvailable:textureId];
            };
            FlutterEventChannel *eventChannel = [FlutterEventChannel
                                                 eventChannelWithName:[NSString
                                                                       stringWithFormat:@"plugins.flutter.io/firebase_livestream_ml_vision%lld",
                                                                       textureId]
                                                 binaryMessenger:_messenger];
            [eventChannel setStreamHandler:cam];
            cam.eventChannel = eventChannel;
            result(@{
                @"textureId" : @(textureId),
                @"previewWidth" : @(cam.previewSize.width),
                @"previewHeight" : @(cam.previewSize.height),
            });
            [cam start];
        }
    } else if ([@"BarcodeDetector#startDetection" isEqualToString:call.method] ||
               [@"FaceDetector#startDetection" isEqualToString:call.method] ||
               [@"ImageLabeler#startDetection" isEqualToString:call.method] ||
               [@"TextRecognizer#startDetection" isEqualToString:call.method] ||
               [@"VisionEdgeImageLabeler#startLocalDetection" isEqualToString:call.method] ||
               [@"VisionEdgeImageLabeler#startRemoteDetection" isEqualToString:call.method]){
        id<Detector> detector = detectors[handle];
        if (!detector) {
            if ([call.method hasPrefix:@"BarcodeDetector"]) {
                detector = [[BarcodeDetector alloc] initWithVision:[FIRVision vision] options:options];
            } else if ([call.method hasPrefix:@"FaceDetector"]) {
                detector = [[FaceDetector alloc] initWithVision:[FIRVision vision] options:options];
            } else if ([call.method hasPrefix:@"ImageLabeler"]) {
                detector = [[ImageLabeler alloc] initWithVision:[FIRVision vision] options:options];
            } else if ([call.method hasPrefix:@"TextRecognizer"]) {
                detector = [[TextRecognizer alloc] initWithVision:[FIRVision vision] options:options];
            } else if ([call.method isEqualToString:@"VisionEdgeImageLabeler#startLocalDetection"]) {
                detector = [[LocalVisionEdgeDetector alloc] initWithVision:[FIRVision vision]
                                                                options:options];
            } else if ([call.method isEqualToString:@"VisionEdgeImageLabeler#startRemoteDetection"]) {
                detector = [[RemoteVisionEdgeDetector alloc] initWithVision:[FIRVision vision]
                                                                options:options];
            }
            [FLTFirebaseLivestreamMlVisionPlugin addDetector:handle detector:detector];
        }
        _camera.activeDetector = detectors[handle];
        result(nil);
    } else if ([@"BarcodeDetector#close" isEqualToString:call.method] ||
               [@"FaceDetector#close" isEqualToString:call.method] ||
               [@"ImageLabeler#close" isEqualToString:call.method] ||
               [@"TextRecognizer#close" isEqualToString:call.method] ||
               [@"VisionEdgeImageLabeler#close" isEqualToString:call.method]) {
        NSNumber *handle = call.arguments[@"handle"];
        [detectors removeObjectForKey:handle];
        _camera.activeDetector = nil;
        result(nil);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

+ (void)addDetector:(NSNumber *)handle detector:(id<Detector>)detector {
    if (detectors[handle]) {
        NSString *reason =
        [[NSString alloc] initWithFormat:@"Object for handle already exists: %d", handle.intValue];
        @throw [[NSException alloc] initWithName:NSInvalidArgumentException reason:reason userInfo:nil];
    }
    
    detectors[handle] = detector;
}

@end
