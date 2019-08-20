package io.flutter.plugins.firebaselivestreammlvision;

import static android.view.OrientationEventListener.ORIENTATION_UNKNOWN;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.ImageFormat;
import android.graphics.Point;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CameraMetadata;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.media.Image;
import android.media.ImageReader;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;
import android.util.Size;
import android.util.SparseIntArray;
import android.view.Display;
import android.view.OrientationEventListener;
import android.view.Surface;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.PluginRegistry;
import io.flutter.view.FlutterView;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import android.util.SparseArray;
import android.view.WindowManager;
import com.google.firebase.ml.vision.FirebaseVision;
import com.google.firebase.ml.vision.common.FirebaseVisionImage;
import com.google.firebase.ml.vision.common.FirebaseVisionImageMetadata;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import java.io.IOException;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

/** FirebaseMlVisionPlugin */
public class FirebaseLivestreamMlVisionPlugin implements MethodCallHandler {

  private static final int CAMERA_REQUEST_ID = 327123094;
  private static CameraManager cameraManager;
  private final FlutterView view;
  private Camera camera;

  private Runnable cameraPermissionContinuation;
  private final OrientationEventListener orientationEventListener;
  private int currentOrientation = ORIENTATION_UNKNOWN;

  private final SparseArray<Detector> detectors = new SparseArray<>();

  private Registrar registrar;

  private FirebaseLivestreamMlVisionPlugin(Registrar registrar, FlutterView view) {
    this.registrar = registrar;
    this.view = view;

    orientationEventListener =
            new OrientationEventListener(registrar.activity().getApplicationContext()) {
              @Override
              public void onOrientationChanged(int i) {
                if (i == ORIENTATION_UNKNOWN) {
                  return;
                }
                // Convert the raw deg angle to the nearest multiple of 90.
                currentOrientation = (int) Math.round(i / 90.0) * 90;
              }
            };

    registrar.addRequestPermissionsResultListener(new CameraRequestPermissionsListener());
  }

  /** Plugin registration. */
  public static void registerWith(Registrar registrar) {
    if (registrar.activity() == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
      // When a background flutter view tries to register the plugin, the registrar has no activity.
      // We stop the registration process as this plugin is foreground only. Also, if the sdk is
      // less than 21 (min sdk for Camera2) we don't register the plugin.
      return;
    }

    final MethodChannel channel =
        new MethodChannel(registrar.messenger(), "plugins.flutter.io/firebase_livestream_ml_vision");

    cameraManager = (CameraManager) registrar.activity().getSystemService(Context.CAMERA_SERVICE);

    channel.setMethodCallHandler(new FirebaseLivestreamMlVisionPlugin(registrar, registrar.view()));
  }

  @Override
  public void onMethodCall(MethodCall call, Result result) {
    String modelName = call.argument("model");
    Map<String, Object> options = call.argument("options");
    Integer handle = call.argument("handle");
    switch (call.method) {
      case "ModelManager#setupLocalModel":
        SetupLocalModel.instance.setup(modelName, result);
        break;
      case "ModelManager#setupRemoteModel":
        SetupRemoteModel.instance.setup(modelName, result);
        break;
      case "camerasAvailable":
        try {
          String[] cameraNames = cameraManager.getCameraIdList();
          List<Map<String, Object>> cameras = new ArrayList<>();
          for (String cameraName : cameraNames) {
            HashMap<String, Object> details = new HashMap<>();
            CameraCharacteristics characteristics =
                    cameraManager.getCameraCharacteristics(cameraName);
            details.put("name", cameraName);
            @SuppressWarnings("ConstantConditions")
            int sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION);
            details.put("sensorOrientation", sensorOrientation);

            int lensFacing = characteristics.get(CameraCharacteristics.LENS_FACING);
            switch (lensFacing) {
              case CameraMetadata.LENS_FACING_FRONT:
                details.put("lensFacing", "front");
                break;
              case CameraMetadata.LENS_FACING_BACK:
                details.put("lensFacing", "back");
                break;
              case CameraMetadata.LENS_FACING_EXTERNAL:
                details.put("lensFacing", "external");
                break;
            }
            cameras.add(details);
          }
          result.success(cameras);
        } catch (Exception e) {
          handleException(e, result);
        }
        break;
      case "initialize":
        String cameraName = call.argument("cameraName");
        String resolutionPreset = call.argument("resolutionPreset");
        if (camera != null) {
          camera.close();
        }
        camera = new Camera(registrar, cameraName, resolutionPreset, result);
        orientationEventListener.enable();
        break;
      case "BarcodeDetector#startDetection":
      case "FaceDetector#startDetection":
      case "ImageLabeler#startDetection":
      case "TextRecognizer#startDetection":
      case "VisionEdgeImageLabeler#startLocalDetection":
      case "VisionEdgeImageLabeler#startRemoteDetection":
        Detector detector = getDetector(call);
        if (detector == null) {
          switch (call.method) {
            case "BarcodeDetector#startDetection":
              detector = new BarcodeDetector(FirebaseVision.getInstance(), options);
              break;
            case "FaceDetector#startDetection":
              detector = new FaceDetector(FirebaseVision.getInstance(), options);
              break;
            case "ImageLabeler#startDetection":
              detector = new ImageLabeler(FirebaseVision.getInstance(), options);
              break;
            case "TextRecognizer#startDetection":
              detector = new TextRecognizer(FirebaseVision.getInstance(), options);
              break;
            case "VisionEdgeImageLabeler#startLocalDetection":
              detector = new LocalVisionEdgeDetector(FirebaseVision.getInstance(), options);
              break;
            case "VisionEdgeImageLabeler#startRemoteDetection":
              detector = new RemoteVisionEdgeDetector(FirebaseVision.getInstance(), options);
              break;
          }
          addDetector(handle, detector);
        }
        camera.currentDetector = getDetector(call);
        result.success(null);
        break;
      case "BarcodeDetector#close":
      case "FaceDetector#close":
      case "ImageLabeler#close":
      case "TextRecognizer#close":
      case "VisionEdgeImageLabeler#close":
        closeDetector(call, result);
        break;
      case "dispose":
        if (camera != null) {
          camera.dispose();
        }
        orientationEventListener.disable();
        result.success(null);
        break;
      default:
        result.notImplemented();
    }
  }

  @SuppressWarnings("ConstantConditions")
  private void handleException(Exception exception, Result result) {
    if (exception instanceof CameraAccessException) {
      result.error("CameraAccess", exception.getMessage(), null);
    }

    throw (RuntimeException) exception;
  }

  private static class CompareSizesByArea implements Comparator<Size> {
    @Override
    public int compare(Size lhs, Size rhs) {
      // We cast here to ensure the multiplications won't overflow.
      return Long.signum(
              (long) lhs.getWidth() * lhs.getHeight() - (long) rhs.getWidth() * rhs.getHeight());
    }
  }

  private class CameraRequestPermissionsListener
          implements PluginRegistry.RequestPermissionsResultListener {
    @Override
    public boolean onRequestPermissionsResult(int id, String[] permissions, int[] grantResults) {
      if (id == CAMERA_REQUEST_ID) {
        cameraPermissionContinuation.run();
        return true;
      }
      return false;
    }
  }

  private void closeDetector(final MethodCall call, final Result result) {
    final Detector detector = getDetector(call);

    if (detector == null) {
      final Integer handle = call.argument("handle");
      final String message = String.format("Object for handle does not exists: %s", handle);
      throw new IllegalArgumentException(message);
    }

    try {
      detector.close();
      result.success(null);
    } catch (IOException e) {
      final String code = String.format("%sIOError", detector.getClass().getSimpleName());
      result.error(code, e.getLocalizedMessage(), null);
    } finally {
      final Integer handle = call.argument("handle");
      detectors.remove(handle);
    }
  }

  private void addDetector(final int handle, final Detector detector) {
    if (detectors.get(handle) != null) {
      final String message = String.format("Object for handle already exists: %s", handle);
      throw new IllegalArgumentException(message);
    }

    detectors.put(handle, detector);
  }

  private Detector getDetector(final MethodCall call) {
    final Integer handle = call.argument("handle");
    return detectors.get(handle);
  }

  private class Camera {
    private final SparseIntArray ORIENTATIONS = new SparseIntArray(4);
    {
      ORIENTATIONS.append(Surface.ROTATION_0, 90);
      ORIENTATIONS.append(Surface.ROTATION_90, 0);
      ORIENTATIONS.append(Surface.ROTATION_180, 270);
      ORIENTATIONS.append(Surface.ROTATION_270, 180);
    }
    private final FlutterView.SurfaceTextureEntry textureEntry;
    private CameraDevice cameraDevice;
    private CameraCaptureSession cameraCaptureSession;
    private EventChannel.EventSink eventSink;
    private ImageReader imageReader;
    private int sensorOrientation;
    private boolean isFrontFacing;
    private String cameraName;
    private Size captureSize;
    private Size previewSize;
    private CaptureRequest.Builder captureRequestBuilder;
    private HandlerThread mBackgroundThread;
    private Handler mBackgroundHandler;
    private WindowManager windowManager;
    private Detector currentDetector;
    private Activity activity;

    Camera(
            PluginRegistry.Registrar registrar,
            final String cameraName,
            final String resolutionPreset,
            @NonNull final Result result) {

      this.activity = registrar.activity();
      this.cameraName = cameraName;
      textureEntry = view.createSurfaceTexture();

      registerEventChannel();

      try {
        int minHeight;
        switch (resolutionPreset) {
          case "high":
            minHeight = 720;
            break;
          case "medium":
            minHeight = 480;
            break;
          case "low":
            minHeight = 240;
            break;
          default:
            throw new IllegalArgumentException("Unknown preset: " + resolutionPreset);
        }

        CameraCharacteristics characteristics = cameraManager.getCameraCharacteristics(cameraName);
        StreamConfigurationMap streamConfigurationMap =
                characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
        //noinspection ConstantConditions
        sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION);
        //noinspection ConstantConditions
        isFrontFacing =
                characteristics.get(CameraCharacteristics.LENS_FACING)
                        == CameraMetadata.LENS_FACING_FRONT;
        computeBestCaptureSize(streamConfigurationMap);
        computeBestPreviewAndRecordingSize(streamConfigurationMap, minHeight, captureSize);

        if (cameraPermissionContinuation != null) {
          result.error("cameraPermission", "Camera permission request ongoing", null);
        }
        cameraPermissionContinuation =
                new Runnable() {
                  @Override
                  public void run() {
                    cameraPermissionContinuation = null;
                    if (!hasCameraPermission()) {
                      result.error(
                              "cameraPermission", "MediaRecorderCamera permission not granted", null);
                      return;
                    }
                    open(result);
                  }
                };
        if (hasCameraPermission()) {
          cameraPermissionContinuation.run();
        } else {
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            final Activity activity = registrar.activity();
            if (activity == null) {
              throw new IllegalStateException("No activity available!");
            }

            activity.requestPermissions(new String[] {Manifest.permission.CAMERA}, CAMERA_REQUEST_ID);
          }
        }
      } catch (CameraAccessException e) {
        result.error("CameraAccess", e.getMessage(), null);
      } catch (IllegalArgumentException e) {
        result.error("IllegalArgumentException", e.getMessage(), null);
      }
    }

    private void registerEventChannel() {
      new EventChannel(
              registrar.messenger(), "plugins.flutter.io/firebase_livestream_ml_vision" + textureEntry.id())
              .setStreamHandler(
                      new EventChannel.StreamHandler() {
                        @Override
                        public void onListen(Object arguments, EventChannel.EventSink eventSink) {
                          Camera.this.eventSink = eventSink;
                        }

                        @Override
                        public void onCancel(Object arguments) {
                          Camera.this.eventSink = null;
                        }
                      });
    }

    private boolean hasCameraPermission() {
      final Activity activity = registrar.activity();
      if (activity == null) {
        throw new IllegalStateException("No activity available!");
      }

      return Build.VERSION.SDK_INT < Build.VERSION_CODES.M
              || activity.checkSelfPermission(Manifest.permission.CAMERA)
              == PackageManager.PERMISSION_GRANTED;
    }

    private void computeBestPreviewAndRecordingSize(
            StreamConfigurationMap streamConfigurationMap, int minHeight, Size captureSize) {
      Size[] sizes = streamConfigurationMap.getOutputSizes(SurfaceTexture.class);

      // Preview size and video size should not be greater than screen resolution or 1080.
      Point screenResolution = new Point();

      final Activity activity = registrar.activity();
      if (activity == null) {
        throw new IllegalStateException("No activity available!");
      }

      Display display = activity.getWindowManager().getDefaultDisplay();
      display.getRealSize(screenResolution);

      final boolean swapWH = getMediaOrientation() % 180 == 90;
      int screenWidth = swapWH ? screenResolution.y : screenResolution.x;
      int screenHeight = swapWH ? screenResolution.x : screenResolution.y;

      List<Size> goodEnough = new ArrayList<>();
      for (Size s : sizes) {
        if (minHeight <= s.getHeight()
                && s.getWidth() <= screenWidth
                && s.getHeight() <= screenHeight
                && s.getHeight() <= 1080) {
          goodEnough.add(s);
        }
      }

      Collections.sort(goodEnough, new CompareSizesByArea());

      if (goodEnough.isEmpty()) {
        previewSize = sizes[0];
      } else {
        float captureSizeRatio = (float) captureSize.getWidth() / captureSize.getHeight();

        previewSize = goodEnough.get(0);
        for (Size s : goodEnough) {
          if ((float) s.getWidth() / s.getHeight() == captureSizeRatio) {
            previewSize = s;
            break;
          }
        }

        Collections.reverse(goodEnough);
      }
    }

    private void computeBestCaptureSize(StreamConfigurationMap streamConfigurationMap) {
      // For still image captures, we use the largest available size.
      captureSize =
              Collections.max(
                      Arrays.asList(streamConfigurationMap.getOutputSizes(ImageFormat.JPEG)),
                      new CompareSizesByArea());
    }

    /** Starts a background thread and its {@link Handler}. */
    private void startBackgroundThread() {
      mBackgroundThread = new HandlerThread("CameraBackground");
      mBackgroundThread.start();
      mBackgroundHandler = new Handler(mBackgroundThread.getLooper());
    }

    /** Stops the background thread and its {@link Handler}. */
    private void stopBackgroundThread() {
      if (mBackgroundThread != null) {
        mBackgroundThread.quitSafely();
        try {
          mBackgroundThread.join();
          mBackgroundThread = null;
          mBackgroundHandler = null;
        } catch (InterruptedException e) {
          e.printStackTrace();
        }
      }
    }

    private int getRotation() {
      if (windowManager == null) {
        windowManager = (WindowManager) activity.getSystemService(Context.WINDOW_SERVICE);
      }
      int degrees = 0;
      int rotation = windowManager.getDefaultDisplay().getRotation();
      switch (rotation) {
        case Surface.ROTATION_0:
          degrees = 0;
          break;
        case Surface.ROTATION_90:
          degrees = 90;
          break;
        case Surface.ROTATION_180:
          degrees = 180;
          break;
        case Surface.ROTATION_270:
          degrees = 270;
          break;
        default:
          Log.e("ML", "Bad rotation value: $rotation");
      }

      try {
        int angle;
        CameraCharacteristics cameraCharacteristics =
                cameraManager.getCameraCharacteristics(cameraName);
        Integer orientation = cameraCharacteristics.get(CameraCharacteristics.SENSOR_ORIENTATION);
        // back-facing
        angle = (orientation - degrees + 360) % 360;
        int translatedAngle = angle / 90;
        return translatedAngle; // this corresponds to the rotation constants
      } catch (CameraAccessException e) {
        return 0;
      }
    }

    private final AtomicBoolean shouldThrottle = new AtomicBoolean(false);

    private void processImage(Image image) {
      if (eventSink == null || currentDetector == null) return;
      if (shouldThrottle.get()) {
        return;
      }
      shouldThrottle.set(true);
      FirebaseVisionImageMetadata metadata =
              new FirebaseVisionImageMetadata.Builder()
                      .setFormat(FirebaseVisionImageMetadata.IMAGE_FORMAT_NV21)
                      .setWidth(image.getWidth())
                      .setHeight(image.getHeight())
                      .setRotation(getRotation())
                      .build();
      FirebaseVisionImage firebaseVisionImage =
              FirebaseVisionImage.fromMediaImage(image, metadata.getRotation());

      currentDetector.handleDetection(
              firebaseVisionImage, eventSink, shouldThrottle);
    }

    private final ImageReader.OnImageAvailableListener imageAvailable =
     new ImageReader.OnImageAvailableListener() {
              @Override
              public void onImageAvailable(ImageReader reader) {
                Image image = reader.acquireLatestImage();
                if (image != null) {
                    processImage(image);
                    image.close();
                }
              }
     };

    private void open(@Nullable final Result result) {
      if (!hasCameraPermission()) {
        if (result != null) result.error("cameraPermission", "Camera permission not granted", null);
      } else {
        try {
          startBackgroundThread();
          imageReader =
                  ImageReader.newInstance(
                          previewSize.getWidth(), previewSize.getHeight(), ImageFormat.YUV_420_888, 2);
          imageReader.setOnImageAvailableListener(imageAvailable, mBackgroundHandler);
          cameraManager.openCamera(
                  cameraName,
                  new CameraDevice.StateCallback() {
                    @Override
                    public void onOpened(@NonNull CameraDevice cameraDevice) {
                      Camera.this.cameraDevice = cameraDevice;
                      try {
                        startPreview();
                      } catch (CameraAccessException e) {
                        if (result != null) result.error("CameraAccess", e.getMessage(), null);
                        cameraDevice.close();
                        Camera.this.cameraDevice = null;
                        return;
                      }

                      if (result != null) {
                        Map<String, Object> reply = new HashMap<>();
                        reply.put("textureId", textureEntry.id());
                        reply.put("previewWidth", previewSize.getWidth());
                        reply.put("previewHeight", previewSize.getHeight());
                        result.success(reply);
                      }
                    }

                    @Override
                    public void onClosed(@NonNull CameraDevice camera) {
                      if (eventSink != null) {
                        Map<String, String> event = new HashMap<>();
                        event.put("eventType", "cameraClosing");
                        eventSink.success(event);
                      }
                      super.onClosed(camera);
                    }

                    @Override
                    public void onDisconnected(@NonNull CameraDevice cameraDevice) {
                      cameraDevice.close();
                      Camera.this.cameraDevice = null;
                      sendErrorEvent("The camera was disconnected.");
                    }

                    @Override
                    public void onError(@NonNull CameraDevice cameraDevice, int errorCode) {
                      cameraDevice.close();
                      Camera.this.cameraDevice = null;
                      String errorDescription;
                      switch (errorCode) {
                        case ERROR_CAMERA_IN_USE:
                          errorDescription = "The camera device is in use already.";
                          break;
                        case ERROR_MAX_CAMERAS_IN_USE:
                          errorDescription = "Max cameras in use";
                          break;
                        case ERROR_CAMERA_DISABLED:
                          errorDescription =
                                  "The camera device could not be opened due to a device policy.";
                          break;
                        case ERROR_CAMERA_DEVICE:
                          errorDescription = "The camera device has encountered a fatal error";
                          break;
                        case ERROR_CAMERA_SERVICE:
                          errorDescription = "The camera service has encountered a fatal error.";
                          break;
                        default:
                          errorDescription = "Unknown camera error";
                      }
                      sendErrorEvent(errorDescription);
                    }
                  },
                  null);
        } catch (CameraAccessException e) {
          if (result != null) result.error("cameraAccess", e.getMessage(), null);
        }
      }
    }

    private void startPreview() throws CameraAccessException {
      closeCaptureSession();

      SurfaceTexture surfaceTexture = textureEntry.surfaceTexture();
      surfaceTexture.setDefaultBufferSize(previewSize.getWidth(), previewSize.getHeight());
      captureRequestBuilder = cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);

      List<Surface> surfaces = new ArrayList<>();

      Surface previewSurface = new Surface(surfaceTexture);
      surfaces.add(previewSurface);
      captureRequestBuilder.addTarget(previewSurface);

      surfaces.add(imageReader.getSurface());
      captureRequestBuilder.addTarget(imageReader.getSurface());

      cameraDevice.createCaptureSession(
              surfaces,
              new CameraCaptureSession.StateCallback() {

                @Override
                public void onConfigured(@NonNull CameraCaptureSession session) {
                  if (cameraDevice == null) {
                    sendErrorEvent("The camera was closed during configuration.");
                    return;
                  }
                  try {
                    cameraCaptureSession = session;
                    captureRequestBuilder.set(
                            CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO);
                    cameraCaptureSession.setRepeatingRequest(captureRequestBuilder.build(), null, null);
                  } catch (CameraAccessException | IllegalStateException | IllegalArgumentException e) {
                    sendErrorEvent(e.getMessage());
                  }
                }

                @Override
                public void onConfigureFailed(@NonNull CameraCaptureSession cameraCaptureSession) {
                  sendErrorEvent("Failed to configure the camera for preview.");
                }
              },
              null);
    }

    private void sendErrorEvent(String errorDescription) {
      if (eventSink != null) {
        Map<String, String> event = new HashMap<>();
        event.put("eventType", "error");
        event.put("errorDescription", errorDescription);
        eventSink.success(event);
      }
    }

    private void closeCaptureSession() {
      if (cameraCaptureSession != null) {
        cameraCaptureSession.close();
        cameraCaptureSession = null;
      }
    }

    private void close() {
      closeCaptureSession();

      if (cameraDevice != null) {
        cameraDevice.close();
        cameraDevice = null;
      }
      if (imageReader != null) {
        imageReader.close();
        imageReader = null;
      }
      stopBackgroundThread();
    }

    private void dispose() {
      close();
      textureEntry.release();
    }

    private int getMediaOrientation() {
      final int sensorOrientationOffset =
              (currentOrientation == ORIENTATION_UNKNOWN)
                      ? 0
                      : (isFrontFacing) ? -currentOrientation : currentOrientation;
      return (sensorOrientationOffset + sensorOrientation + 360) % 360;
    }
  }

}
