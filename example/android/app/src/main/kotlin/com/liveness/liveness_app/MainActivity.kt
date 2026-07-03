package com.liveness.liveness_app

import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "liveness_flutter/camera"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getBackCameraFocusInfo") {
                    getBackCameraFocusInfo(result)
                } else {
                    result.notImplemented()
                }
            }
    }

    // Returns the minimum focus distance (diopters) of the back camera.
    // 0.0  → fixed-focus lens (already can't focus close — nothing to do)
    // >0.0 → autofocus; caller should lock AF after init so close screens blur.
    private fun getBackCameraFocusInfo(result: MethodChannel.Result) {
        try {
            val manager = getSystemService(CAMERA_SERVICE) as CameraManager
            val backId = manager.cameraIdList.firstOrNull { id ->
                manager.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            } ?: return result.error("NO_BACK_CAMERA", "No back camera found", null)

            val chars = manager.getCameraCharacteristics(backId)
            val minFocusDiopters = chars.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE) ?: 0f

            // minFocusDiopters > 0 means the lens has autofocus.
            // e.g. 10.0 diopters = can focus as close as 10 cm.
            // We want to lock it at ~1.0 diopter (1 metre) so screens
            // held closer than ~40 cm go blurry.
            result.success(mapOf(
                "cameraId" to backId,
                "minFocusDiopters" to minFocusDiopters,
                "hasAutofocus" to (minFocusDiopters > 0f),
            ))
        } catch (e: Exception) {
            result.error("CAMERA_ERROR", e.message, null)
        }
    }
}
