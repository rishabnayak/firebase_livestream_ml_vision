// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:firebase_livestream_ml_vision/firebase_livestream_ml_vision.dart';
import 'package:flutter/material.dart';
import 'detector_painters.dart';

void main() => runApp(MaterialApp(home: _MyHomePage()));

class _MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<_MyHomePage> {
  FirebaseVision _vision;
  dynamic _scanResults;
  Detector _currentDetector = Detector.barcode;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  void _initializeCamera() async {
    List<FirebaseCameraDescription> cameras = await camerasAvailable();
    _vision = FirebaseVision(cameras[0], ResolutionSetting.high);
    _vision.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

    Widget _buildResults() {
    const Text noResultsText = Text('No results!');

    CustomPainter painter;

    final Size imageSize = Size(
      _vision.value.previewSize.height,
      _vision.value.previewSize.width,
    );

    switch (_currentDetector) {
      case Detector.barcode:
        _vision.addBarcodeDetector().then((onValue){
          onValue.listen((onData){
            setState(() {
              _scanResults = onData;
            });
          });
        });
        if (_scanResults is! List<Barcode>) return noResultsText;
        painter = BarcodeDetectorPainter(imageSize, _scanResults);
        break;
      case Detector.face:
        _vision.addFaceDetector().then((onValue){
          onValue.listen((onData){
            setState(() {
              _scanResults = onData;
            });
          });
        });
        if (_scanResults is! List<Face>) return noResultsText;
        painter = FaceDetectorPainter(imageSize, _scanResults);
        break;
      case Detector.label:
        _vision.addImageLabeler().then((onValue){
          onValue.listen((onData){
            setState(() {
              _scanResults = onData;
            });
          });
        });
        if (_scanResults is! List<ImageLabel>) return noResultsText;
        painter = LabelDetectorPainter(imageSize, _scanResults);
        break;
      case Detector.cloudLabel:
        _vision.addCloudImageLabeler().then((onValue){
          onValue.listen((onData){
            setState(() {
              _scanResults = onData;
            });
          });
        });
        if (_scanResults is! List<ImageLabel>) return noResultsText;
        painter = LabelDetectorPainter(imageSize, _scanResults);
        break;
      case Detector.visionEdgeLabel:
        _vision.addVisionEdgeImageLabeler('potholes', ModelLocation.Local).then((onValue){
          onValue.listen((onData){
            setState(() {
              _scanResults = onData;
            });
          });
        });
        if (_scanResults is! List<VisionEdgeImageLabel>) return noResultsText;
        painter = VisionEdgeLabelDetectorPainter(imageSize, _scanResults);
        break;
      default:
        assert(_currentDetector == Detector.text ||
            _currentDetector == Detector.cloudText);
        _vision.addTextRecognizer().then((onValue){
          onValue.listen((onData){
            setState(() {
              _scanResults = onData;
            });
          });
        });
        if (_scanResults is! VisionText) return noResultsText;
        painter = TextDetectorPainter(imageSize, _scanResults);
    }

    return CustomPaint(
      painter: painter,
    );
  }

  Widget _buildImage() {
    return Container(
      constraints: const BoxConstraints.expand(),
      child: _vision == null
          ? const Center(
              child: Text(
                'Initializing Camera...',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 30.0,
                ),
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: <Widget>[
                FirebaseCameraPreview(_vision),
                _buildResults(),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ML Vision Example'),
        actions: <Widget>[
          PopupMenuButton(
            onSelected: (result) {
              _currentDetector = result;
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry>[
              const PopupMenuItem(
                child: Text('Detect Barcode'),
                value: Detector.barcode,
              ),
              const PopupMenuItem(
                child: Text('Detect Face'),
                value: Detector.face,
              ),
              const PopupMenuItem(
                child: Text('Detect Label'),
                value: Detector.label,
              ),
              const PopupMenuItem(
                child: Text('Detect Cloud Label'),
                value: Detector.cloudLabel,
              ),
              const PopupMenuItem(
                child: Text('Detect Text'),
                value: Detector.text,
              ),
              const PopupMenuItem(
                child: Text('Detect Cloud Text'),
                value: Detector.cloudText,
              ),
              const PopupMenuItem(
                child: Text('Detect AutoML Vision Label'),
                value: Detector.visionEdgeLabel,
              ),
            ],
          ),
        ],
      ),
      body: _buildImage(),
    );
  }

  @override
  void dispose() {
    _vision.dispose().then((_) {
      _vision.barcodeDetector.close();
      _vision.faceDetector.close();
      _vision.localImageLabeler.close();
      _vision.cloudImageLabeler.close();
      _vision.textRecognizer.close();
      _vision.visionEdgeImageLabeler.close();
    });

    _currentDetector = null;
    super.dispose();
  }

}