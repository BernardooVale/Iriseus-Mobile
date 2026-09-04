package com.example.iriseus

import android.content.Context
import androidx.camera.view.PreviewView
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.platform.PlatformView

class CameraStreamView(context: Context, lifecycleOwner: LifecycleOwner) : PlatformView {
    private val previewView = PreviewView(context)
    val streamer = CameraStreamer(context, lifecycleOwner, previewView)
    init { streamer.startPreview() }
    override fun getView() = previewView
    override fun dispose() = streamer.release()
}