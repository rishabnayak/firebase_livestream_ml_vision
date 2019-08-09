part of firebase_livestream_ml_vision;

/// Used for finding [VisionEdgeImageLabel]s in a supplied image.
///
///
/// A image labeler is created via
/// `addVisionEdgeImageLabeler(String dataset, [VisionEdgeImageLabelerOptions options])` in [FirebaseVision]:
///


class VisionEdgeImageLabeler {
  VisionEdgeImageLabeler._({
    @required dynamic options,
    @required String dataset,
    @required String modelLocation,
    @required int handle,
  })  : _options = options,
        _dataset = dataset,
        _handle = handle,
        _modelLocation = modelLocation,
        assert(options != null),
        assert(dataset != null);

  // Should be of type VisionEdgeImageLabelerOptions.
  final dynamic _options;

  final String _dataset;

  final String _modelLocation;

  final int _handle;

  bool _hasBeenOpened = false;
  bool _isClosed = false;

  /// Finds entities in the input image.
 Future<void> startDetection() async {
    assert(!_isClosed);

    _hasBeenOpened = true;
    // https://github.com/flutter/flutter/issues/26431
    // ignore: strong_mode_implicit_dynamic_method
    if (_modelLocation == ModelLocation.Local) {
    await FirebaseVision.channel.invokeMethod<dynamic>(
        'VisionEdgeImageLabeler#startLocalDetection',
        <String, dynamic>{
          'handle': _handle,
          'options': <String, dynamic>{
            'dataset': _dataset,
            'confidenceThreshold': _options.confidenceThreshold,
          },
        },
    );
    } else {
   await FirebaseVision.channel.invokeListMethod<dynamic>(
        'VisionEdgeImageLabeler#startRemoteDetection',
        <String, dynamic>{
          'handle': _handle,
          'options': <String, dynamic>{
            'dataset': _dataset,
            'confidenceThreshold': _options.confidenceThreshold,
          },
        },
);
    }
  }

  /// Release resources used by this labeler.
  Future<void> close() {
    if (!_hasBeenOpened) _isClosed = true;
    if (_isClosed) return Future<void>.value(null);

    _isClosed = true;
    return FirebaseVision.channel.invokeMethod<void>(
      'VisionEdgeImageLabeler#close',
      <String, dynamic>{'handle': _handle},
    );
  }
}

class ModelLocation {
  static const String Local = 'local';
  static const String Remote = 'remote';
}

/// Options for on device image labeler.
///
/// Confidence threshold could be provided for the label detection. For example,
/// if the confidence threshold is set to 0.7, only labels with
/// confidence >= 0.7 would be returned. The default threshold is 0.5.
class VisionEdgeImageLabelerOptions {
  /// Constructor for [VisionEdgeImageLabelerOptions].
  ///
  /// Confidence threshold could be provided for the label detection.
  /// For example, if the confidence threshold is set to 0.7, only labels with
  /// confidence >= 0.7 would be returned. The default threshold is 0.5.
  const VisionEdgeImageLabelerOptions({this.confidenceThreshold = 0.5})
      : assert(confidenceThreshold >= 0.0),
        assert(confidenceThreshold <= 1.0);

  /// The minimum confidence threshold of labels to be detected.
  ///
  /// Required to be in range [0.0, 1.0].
  final double confidenceThreshold;
}

/// Represents an entity label detected by [ImageLabeler] and [CloudImageLabeler].
class VisionEdgeImageLabel {
  VisionEdgeImageLabel._(dynamic data)
      : confidence = data['confidence'],
        text = data['text'];

  /// The overall confidence of the result. Range [0.0, 1.0].
  final double confidence;

  /// A detected label from the given image.
  ///
  /// The label returned here is in English only. The end developer should use
  /// [entityId] to retrieve unique id.
  final String text;
}
