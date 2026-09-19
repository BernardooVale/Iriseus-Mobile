package com.example.iriseus

import android.content.Context
import android.view.ViewGroup
import androidx.camera.view.PreviewView
import io.flutter.plugin.platform.PlatformView

class CameraStreamView(context: Context) : PlatformView {
    private val previewView = PreviewView(context).apply {
        // COMPATIBLE usa TextureView internamente — evita bugs de posicionamento e corte
        // do SurfaceView dentro de PlatformViews no Flutter com Vulkan/Impeller
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        scaleType = PreviewView.ScaleType.FILL_CENTER
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
    }

    init {
        CameraForegroundService.attachPreview(previewView)
    }

    override fun getView() = previewView

    override fun dispose() {
        CameraForegroundService.attachPreview(null)
    }
}