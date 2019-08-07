#import "FirebaseLivestreamMlVisionPlugin.h"

@implementation FirebaseLivestreamMlVisionPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"firebase_livestream_ml_vision"
            binaryMessenger:[registrar messenger]];
  FirebaseLivestreamMlVisionPlugin* instance = [[FirebaseLivestreamMlVisionPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"getPlatformVersion" isEqualToString:call.method]) {
    result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

@end
