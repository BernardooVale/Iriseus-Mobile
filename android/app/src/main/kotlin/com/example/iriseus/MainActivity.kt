package com.example.iriseus

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var eventSink: EventChannel.EventSink? = null

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
                        CameraForegroundService.statusCallback = { status ->
                            runOnUiThread { eventSink?.success(mapOf("status" to status)) }
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
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.iriseus/camera_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) { eventSink = sink }
                override fun onCancel(args: Any?) { eventSink = null }
            })
    }
}