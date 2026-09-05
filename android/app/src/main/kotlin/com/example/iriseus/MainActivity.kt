package com.example.iriseus

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.net.wifi.WifiManager

class MainActivity : FlutterActivity() {
    private var eventSink: EventChannel.EventSink? = null
    private var cameraStreamer: CameraStreamer? = null

    private var pendingStreamArgs: Pair<String, Int>? = null

    private var pendingStatusCallback: ((String) -> Unit)? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.example.iriseus/camera_preview",
            CameraStreamViewFactory(this) { streamer ->
                cameraStreamer = streamer
                // dispara stream pendente se houver
                val args = pendingStreamArgs
                val cb = pendingStatusCallback
                if (args != null && cb != null) {
                    streamer.startStreaming(args.first, args.second, cb)
                    pendingStreamArgs = null
                    pendingStatusCallback = null
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.iriseus/camera")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startStream" -> {
                        val ip: String = call.argument("ip")!!
                        val port: Int = call.argument("port")!!
                        val cb: (String) -> Unit = { s -> eventSink?.success(mapOf("status" to s)) }
                        cameraStreamer?.let { streamer ->
                            streamer.startStreaming(ip, port, cb)
                        } ?: run {
                            pendingStreamArgs = Pair(ip, port)
                            pendingStatusCallback = cb
                        }
                        result.success(null)
                    }
                    "stopStream" -> { cameraStreamer?.stopStreaming(); result.success(null) }
                    "switchCamera" -> { cameraStreamer?.switchCamera(); result.success(null) }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.iriseus/wifi")
            .setMethodCallHandler { call, result ->
                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                when (call.method) {
                    "acquireMulticastLock" -> {
                        multicastLock = wifi.createMulticastLock("iriseus_mdns").apply {
                            setReferenceCounted(true)
                            acquire()
                        }
                        result.success(null)
                    }
                    "releaseMulticastLock" -> {
                        multicastLock?.release()
                        multicastLock = null
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