package io.flutter.plugins.firebaselivestreammlvision;

import com.google.firebase.ml.vision.common.FirebaseVisionImage;

import java.io.IOException;
import java.net.MalformedURLException;
import java.net.URL;
import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.plugin.common.EventChannel;

class ShowTellDetector implements Detector {

    @Override
    public void handleDetection(FirebaseVisionImage image, EventChannel.EventSink eventSink, AtomicBoolean throttle) {
        try {
            URL url = new URL("http://35.223.217.25/");
        } catch (MalformedURLException e) {
            e.printStackTrace();
        }

        

        image.getBitmap();

    }

    @Override
    public void close() throws IOException {

    }
}
