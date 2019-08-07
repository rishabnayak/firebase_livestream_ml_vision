#import "FirebaseLivestreamMlVisionPlugin.h"
#import "FirebaseCam.h"

static FlutterError *getFlutterError(NSError *error) {
    return [FlutterError errorWithCode:[NSString stringWithFormat:@"Error %d", (int)error.code]
                               message:error.domain
                               details:error.localizedDescription];
}

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
