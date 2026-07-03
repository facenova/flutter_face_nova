package com.example.flutter_face_nova

import android.content.res.AssetManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.StandardMethodCodec

class LivenessFlutterPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var assetManager: AssetManager? = null

    companion object {
        init { System.loadLibrary("liveness_sec") }
    }

    external fun verifyLicense(token: String): Boolean
    external fun decryptModel(assetManager: AssetManager, modelId: Int): ByteArray?

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val taskQueue = binding.binaryMessenger.makeBackgroundTaskQueue()
        channel = MethodChannel(
            binding.binaryMessenger,
            "liveness_flutter/secure",
            StandardMethodCodec.INSTANCE,
            taskQueue
        )
        channel.setMethodCallHandler(this)
        assetManager = binding.applicationContext.assets
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "verifyLicense" -> {
                val token = call.argument<String>("token") ?: ""
                try {
                    result.success(verifyLicense(token))
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            "decryptModel" -> {
                val modelId = call.argument<Int>("modelId") ?: 0
                val am = assetManager
                if (am == null) { result.success(null); return }
                try {
                    result.success(decryptModel(am, modelId))
                } catch (e: Exception) {
                    result.success(null)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
