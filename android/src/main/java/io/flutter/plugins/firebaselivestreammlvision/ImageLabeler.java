package io.flutter.plugins.firebaselivestreammlvision;

import androidx.annotation.NonNull;
import com.google.android.gms.tasks.OnFailureListener;
import com.google.android.gms.tasks.OnSuccessListener;
import com.google.firebase.ml.vision.FirebaseVision;
import com.google.firebase.ml.vision.common.FirebaseVisionImage;
import com.google.firebase.ml.vision.label.FirebaseVisionCloudImageLabelerOptions;
import com.google.firebase.ml.vision.label.FirebaseVisionImageLabel;
import com.google.firebase.ml.vision.label.FirebaseVisionImageLabeler;
import com.google.firebase.ml.vision.label.FirebaseVisionOnDeviceImageLabelerOptions;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

class ImageLabeler implements Detector {
  private final FirebaseVisionImageLabeler labeler;

  ImageLabeler(FirebaseVision vision, Map<String, Object> options) {
    final String modelType = (String) options.get("modelType");
    if (modelType.equals("onDevice")) {
      labeler = vision.getOnDeviceImageLabeler(parseOptions(options));
    } else if (modelType.equals("cloud")) {
      labeler = vision.getCloudImageLabeler(parseCloudOptions(options));
    } else {
      final String message = String.format("No model for type: %s", modelType);
      throw new IllegalArgumentException(message);
    }
  }

  @Override
  public void handleDetection(final FirebaseVisionImage image, final EventChannel.EventSink result, final AtomicBoolean throttle) {
    labeler
        .processImage(image)
        .addOnSuccessListener(
            new OnSuccessListener<List<FirebaseVisionImageLabel>>() {
              @Override
              public void onSuccess(List<FirebaseVisionImageLabel> firebaseVisionLabels) {
                List<Map<String, Object>> labels = new ArrayList<>(firebaseVisionLabels.size());
                for (FirebaseVisionImageLabel label : firebaseVisionLabels) {
                  Map<String, Object> labelData = new HashMap<>();
                  labelData.put("confidence", (double) label.getConfidence());
                  labelData.put("entityId", label.getEntityId());
                  labelData.put("text", label.getText());

                  labels.add(labelData);
                }

                Map<String, Object> res = new HashMap<>();
                res.put("eventType", "detection");
                res.put("data", labels);
                throttle.set(false);
                result.success(res);
              }
            })
        .addOnFailureListener(
            new OnFailureListener() {
              @Override
              public void onFailure(@NonNull Exception e) {
                throttle.set(false);
                result.error("imageLabelerError", e.getLocalizedMessage(), null);
              }
            });
  }

  private FirebaseVisionOnDeviceImageLabelerOptions parseOptions(Map<String, Object> optionsData) {
    float conf = (float) (double) optionsData.get("confidenceThreshold");
    return new FirebaseVisionOnDeviceImageLabelerOptions.Builder()
        .setConfidenceThreshold(conf)
        .build();
  }

  private FirebaseVisionCloudImageLabelerOptions parseCloudOptions(
      Map<String, Object> optionsData) {
    float conf = (float) (double) optionsData.get("confidenceThreshold");
    return new FirebaseVisionCloudImageLabelerOptions.Builder()
        .setConfidenceThreshold(conf)
        .build();
  }

  @Override
  public void close() throws IOException {
    labeler.close();
  }
}
