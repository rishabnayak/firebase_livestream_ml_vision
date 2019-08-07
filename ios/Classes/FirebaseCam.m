#import "FirebaseCam.h"
#import <AVFoundation/AVFoundation.h>
#import <libkern/OSAtomic.h>

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
    CVImageBufferRef newBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (newBuffer) {
        if (!_isRecognizingStream) {
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
