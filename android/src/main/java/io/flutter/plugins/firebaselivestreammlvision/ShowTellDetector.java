package io.flutter.plugins.firebaselivestreammlvision;

import android.graphics.Bitmap;
import android.util.Base64;

import com.google.firebase.ml.vision.common.FirebaseVisionImage;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedOutputStream;
import java.io.BufferedWriter;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.plugin.common.EventChannel;

class ShowTellDetector implements Detector {

    @Override
    public void handleDetection(final FirebaseVisionImage image, final EventChannel.EventSink result, final AtomicBoolean throttle) {
        ByteArrayOutputStream outStream = new ByteArrayOutputStream();
        JSONObject json = new JSONObject();
        image.getBitmap().compress(Bitmap.CompressFormat.JPEG, 100, outStream);
        byte[] imageBytes = outStream.toByteArray();
        String imageString = Base64.encodeToString(imageBytes, Base64.DEFAULT);
        Log.i("BASE64", imageString);
        OutputStream out;
        try {
            URL url = new URL("http://35.223.217.25/");
            HttpURLConnection con = (HttpURLConnection) url.openConnection();
            con.setRequestMethod("POST");
            con.setRequestProperty("Content-Type", "application/json; utf-8");
            con.setRequestProperty("Accept", "application/json");
            con.setDoOutput(true);
            //con.connect();
            json.put("image", imageString);
            String jsonString = json.toString();
            Log.i("JSON", jsonString);
            out = new BufferedOutputStream(con.getOutputStream());
            BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(out, "UTF-8"));
            writer.write(jsonString);
            writer.flush();
            writer.close();
            out.close();
            con.connect();
            throttle.set(false);
            result.success(out);
            
            //DataOutputStream os = new DataOutputStream(con.getOutputStream());
            //os.writeBytes(json.toString());
            //os.flush();
            //os.close();
            Log.i("STATUS", String.valueOf(con.getResponseCode()));
            Log.i("MSG" , con.getResponseMessage());
                //con.disconnect();

        } catch (IOException | JSONException e) {
            e.printStackTrace();
        }
    }

    @Override
    public void close() throws IOException {

    }
}
