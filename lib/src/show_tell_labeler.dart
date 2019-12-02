part of firebase_livestream_ml_vision;

class ShowTellLabeler {
  ShowTellLabeler._({
    @required int handle,
  }) : _handle = handle;

  final int _handle;

  bool _hasBeenOpened = false;
  bool _isClosed = false;

  /// Finds entities in the input image.
  Future<void> startDetection() async {
    assert(!_isClosed);

    _hasBeenOpened = true;
    // https://github.com/flutter/flutter/issues/26431
    // ignore: strong_mode_implicit_dynamic_method
    await FirebaseVision.channel.invokeMethod<dynamic>(
      'ShowTellLabeler#startDetection',
      <String, dynamic>{
        'handle': _handle,
      },
    );
  }

  /// Release resources used by this labeler.
  Future<void> close() {
    if (!_hasBeenOpened) _isClosed = true;
    if (_isClosed) return Future<void>.value(null);

    _isClosed = true;
    return FirebaseVision.channel.invokeMethod<void>(
      'ShowTellLabeler#close',
      <String, dynamic>{'handle': _handle},
    );
  }
}
