package io.flutter.plugins.firebaselivestreammlvision;

import androidx.annotation.NonNull;
import com.google.android.gms.tasks.OnFailureListener;
import com.google.android.gms.tasks.OnSuccessListener;
import com.google.firebase.ml.common.FirebaseMLException;
import com.google.firebase.ml.common.modeldownload.FirebaseLocalModel;
import com.google.firebase.ml.common.modeldownload.FirebaseModelManager;
import com.google.firebase.ml.vision.FirebaseVision;
import com.google.firebase.ml.vision.common.FirebaseVisionImage;
import com.google.firebase.ml.vision.label.FirebaseVisionImageLabel;
import com.google.firebase.ml.vision.label.FirebaseVisionImageLabeler;
import com.google.firebase.ml.vision.label.FirebaseVisionOnDeviceAutoMLImageLabelerOptions;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

class LocalVisionEdgeDetector implements Detector {
  private FirebaseVisionImageLabeler labeler;

  LocalVisionEdgeDetector(FirebaseVision vision, Map<String, Object> options) {
    String finalPath = "flutter_assets/assets/" + options.get("dataset") + "/manifest.json";
    FirebaseLocalModel localModel =
        FirebaseModelManager.getInstance().getLocalModel((String) options.get("dataset"));
    if (localModel == null) {
      localModel =
          new FirebaseLocalModel.Builder((String) options.get("dataset"))
              .setAssetFilePath(finalPath)
              .build();
      FirebaseModelManager.getInstance().registerLocalModel(localModel);
      try {
        labeler = vision.getOnDeviceAutoMLImageLabeler(parseOptions(options));
      } catch (FirebaseMLException e) {
        throw new IllegalArgumentException(e.getLocalizedMessage());
      }
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

  private FirebaseVisionOnDeviceAutoMLImageLabelerOptions parseOptions(
      Map<String, Object> optionsData) {
    float conf = (float) (double) optionsData.get("confidenceThreshold");
    return new FirebaseVisionOnDeviceAutoMLImageLabelerOptions.Builder()
        .setLocalModelName((String) optionsData.get("dataset"))
        .setConfidenceThreshold(conf)
        .build();
  }

  @Override
  public void close() throws IOException {
    labeler.close();
  }
}
