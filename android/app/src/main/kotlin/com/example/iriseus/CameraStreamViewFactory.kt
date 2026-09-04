package com.example.iriseus

import android.content.Context
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import androidx.lifecycle.LifecycleOwner

class CameraStreamViewFactory(
    private val lifecycleOwner: LifecycleOwner,
    private val onCreated: (CameraStreamer) -> Unit,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val view = CameraStreamView(context, lifecycleOwner)
        onCreated(view.streamer)
        return view
    }
}