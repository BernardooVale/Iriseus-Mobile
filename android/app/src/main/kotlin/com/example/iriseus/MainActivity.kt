package com.example.iriseus

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var eventSink: EventChannel.EventSink? = null
    private var cameraStreamer: CameraStreamer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.example.iriseus/camera_preview",
            CameraStreamViewFactory(this) { streamer -> cameraStreamer = streamer }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.iriseus/camera")
            .setMethodCallHandler { call, result ->
                val streamer = cameraStreamer
                if (streamer == null) { result.error("NO_CAMERA", "Preview não iniciado", null); return@setMethodCallHandler }
                when (call.method) {
                    "startStream" -> {
                        streamer.startStreaming(call.argument("ip")!!, call.argument("port")!!) { s ->
                            eventSink?.success(mapOf("status" to s))
                        }
                        result.success(null)
                    }
                    "stopStream" -> { streamer.stopStreaming(); result.success(null) }
                    "switchCamera" -> { streamer.switchCamera(); result.success(null) }
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