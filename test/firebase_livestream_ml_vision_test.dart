import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_livestream_ml_vision/firebase_livestream_ml_vision.dart';

void main() {
  const MethodChannel channel = MethodChannel('firebase_livestream_ml_vision');

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    expect(await FirebaseLivestreamMlVision.platformVersion, '42');
  });
}
