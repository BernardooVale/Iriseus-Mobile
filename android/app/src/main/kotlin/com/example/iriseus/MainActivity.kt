package com.example.iriseus

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val REQUEST_CODE_SCREEN_CAPTURE = 1001
    }

    private var eventSink: EventChannel.EventSink? = null
    private var pendingScreenShareResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.example.iriseus/camera_preview",
            CameraStreamViewFactory()
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.iriseus/camera")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startStream" -> {
                        val ip: String = call.argument("ip") ?: "127.0.0.1"
                        val port: Int  = call.argument("port") ?: 45679
                        CameraForegroundService.statusCallback = { status, mode ->
                            runOnUiThread {
                                eventSink?.success(mapOf("status" to status, "mode" to mode))
                            }
                        }
                        CameraForegroundService.startStream(this, ip, port)
                        result.success(null)
                    }
                    "stopStream" -> {
                        CameraForegroundService.stopStream(this)
                        result.success(null)
                    }
                    "switchCamera" -> {
                        CameraForegroundService.switchCamera(this)
                        result.success(null)
                    }
                    "startScreenShare" -> {
                        val mediaProjectionManager =
                            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                        pendingScreenShareResult = result
                        startActivityForResult(
                            mediaProjectionManager.createScreenCaptureIntent(),
                            REQUEST_CODE_SCREEN_CAPTURE
                        )
                    }
                    "stopScreenShare" -> {
                        CameraForegroundService.stopScreenShare(this)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.iriseus/camera_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) { eventSink = sink }
                override fun onCancel(args: Any?) { eventSink = null }
            })
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_SCREEN_CAPTURE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                CameraForegroundService.startScreenShare(this, resultCode, data)
                pendingScreenShareResult?.success(true)
                pendingScreenShareResult = null

                // M4.5: Minimiza o aplicativo automaticamente para evitar gravar a interface do Iriseus
                moveTaskToBack(true)
            } else {
                pendingScreenShareResult?.success(false)
                pendingScreenShareResult = null
            }
        }
    }
}