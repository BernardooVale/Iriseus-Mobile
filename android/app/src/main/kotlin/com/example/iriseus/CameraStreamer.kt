package com.example.iriseus

import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.util.Log
import android.util.Size
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.io.DataOutputStream
import java.net.Socket
import java.util.concurrent.Executors
import kotlin.collections.get
import kotlin.text.get

class CameraStreamer(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val previewView: PreviewView,
) {
    companion object {
        private const val TAG = "CameraStreamer"
        private const val WIDTH = 1280
        private const val HEIGHT = 720
        private const val FRAME_RATE = 30
        private const val BITRATE = 2_000_000
        private const val I_FRAME_INTERVAL = 1
    }

    private var cameraProvider: ProcessCameraProvider? = null
    private var lensFacing = CameraSelector.LENS_FACING_BACK
    private var encoder: MediaCodec? = null
    private var socket: Socket? = null
    private var outStream: DataOutputStream? = null
    @Volatile private var streaming = false
    private var analysisExecutor = Executors.newSingleThreadExecutor()
    private var networkExecutor = Executors.newSingleThreadExecutor()
    private var onStatus: ((String) -> Unit)? = null

    private var encoderWidth = WIDTH

    private var encoderHeight = HEIGHT

    fun startPreview() {
        val providerFuture = ProcessCameraProvider.getInstance(context)
        providerFuture.addListener({
            cameraProvider = providerFuture.get()
            bindUseCases()
        }, ContextCompat.getMainExecutor(context))
    }

    private fun bindUseCases() {
        val provider = cameraProvider ?: return
        provider.unbindAll()
        val preview = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
        val analysis = ImageAnalysis.Builder()
            .setTargetResolution(Size(WIDTH, HEIGHT))
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()
        analysis.setAnalyzer(analysisExecutor) { image -> onFrame(image) }
        val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()
        provider.bindToLifecycle(lifecycleOwner, selector, preview, analysis)
    }

    fun switchCamera() {
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK)
            CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK
        bindUseCases()
    }

    fun startStreaming(ip: String, port: Int, statusCallback: (String) -> Unit) {
        onStatus = statusCallback
        if (streaming) stopStreaming()

        if (networkExecutor.isShutdown) networkExecutor = Executors.newSingleThreadExecutor()
        if (analysisExecutor.isShutdown) analysisExecutor = Executors.newSingleThreadExecutor()

        // setupEncoder antes de setar streaming=true
        setupEncoder()
        streaming = true
        postStatus("connecting")
        networkExecutor.execute {
            try {
                socket = Socket(ip, port).apply { tcpNoDelay = true }
                outStream = DataOutputStream(socket!!.getOutputStream())
                // setupEncoder() — removido daqui
                postStatus("streaming")
                Log.d(TAG, "Socket conectado, iniciando drainEncoderLoop")
                drainEncoderLoop()
                Log.d(TAG, "drainEncoderLoop encerrou")
            } catch (e: Exception) {
                Log.e(TAG, "Falha ao conectar socket de stream", e)
                streaming = false
                encoder?.stop(); encoder?.release(); encoder = null
                postStatus("error")
            }
        }
    }

    private fun setupEncoder(w: Int = WIDTH, h: Int = HEIGHT) {
        encoderWidth = w
        encoderHeight = h
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, w, h).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE, BITRATE)
            setInteger(MediaFormat.KEY_FRAME_RATE, FRAME_RATE)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, I_FRAME_INTERVAL)
            setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
        }
        encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC).apply {
            configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            start()
        }
    }

    private fun drainEncoderLoop() {
        val bufferInfo = MediaCodec.BufferInfo()
        while (streaming) {
            val codec = encoder ?: break
            val outIndex = codec.dequeueOutputBuffer(bufferInfo, 10_000)
            if (outIndex >= 0) {
                val outBuffer = codec.getOutputBuffer(outIndex) ?: continue
                val nalu = ByteArray(bufferInfo.size)
                outBuffer.get(nalu)
                writeFramed(nalu)
                codec.releaseOutputBuffer(outIndex, false)
            }
        }
    }

    private fun writeFramed(nalu: ByteArray) {
        try {
            val out = outStream ?: return
            out.writeInt(nalu.size)
            out.write(nalu)
            out.flush()
        } catch (e: Exception) {
            Log.e(TAG, "Erro ao escrever NALU", e)
            postStatus("error")           // era onStatus?.invoke("error")
            stopStreaming()
        }
    }

    private fun onFrame(image: ImageProxy) {
        if (!streaming || encoder == null) {
            Log.d(TAG, "onFrame descartado: streaming=$streaming encoder=${encoder != null}")
            image.close(); return }
        try {
            queueToEncoder(yuv420ToNv21(image))
        } catch (e: Exception) {
            Log.e(TAG, "Erro processando frame", e)
        } finally {
            image.close()
        }
    }

    private fun queueToEncoder(nv21: ByteArray) {
        val codec = encoder ?: return
        val inIndex = codec.dequeueInputBuffer(10_000)
        if (inIndex >= 0) {
            val inputBuffer = codec.getInputBuffer(inIndex) ?: return
            inputBuffer.clear()
            // inputBuffer.put(nv21)
            val bytesToWrite = minOf(nv21.size, inputBuffer.remaining())
            inputBuffer.put(nv21, 0, bytesToWrite)
            codec.queueInputBuffer(inIndex, 0, bytesToWrite, System.nanoTime() / 1000, 0)
        }
    }

    // Conversão simplificada — assume sem row padding. Ver nota abaixo.
    private fun yuv420ToNv21(image: ImageProxy): ByteArray {
        val width = image.width
        val height = image.height

        Log.d(TAG, "yuv420ToNv21: ${width}x${height}")

        val ySize = width * height
        val uvSize = width * height / 2
        val nv21 = ByteArray(ySize + uvSize)

        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        // copia Y linha a linha respeitando row stride
        val yRowStride = yPlane.rowStride
        val yBuf = yPlane.buffer
        for (row in 0 until height) {
            yBuf.position(row * yRowStride)
            yBuf.get(nv21, row * width, width)
        }

        // intercala V e U para NV21 (V primeiro)
        val uvRowStride = uPlane.rowStride
        val uvPixelStride = uPlane.pixelStride
        val uBuf = uPlane.buffer
        val vBuf = vPlane.buffer
        var uvIndex = ySize
        for (row in 0 until height / 2) {
            for (col in 0 until width / 2) {
                val bufIndex = row * uvRowStride + col * uvPixelStride
                nv21[uvIndex++] = vBuf.get(bufIndex)
                nv21[uvIndex++] = uBuf.get(bufIndex)
            }
        }
        return nv21
    }

    fun stopStreaming() {
        streaming = false
        try { encoder?.stop(); encoder?.release() } catch (_: Exception) {}
        encoder = null
        try { outStream?.close(); socket?.close() } catch (_: Exception) {}
        outStream = null; socket = null
    }

    fun release() {
        stopStreaming()
        cameraProvider?.unbindAll()
        analysisExecutor.shutdown()
        networkExecutor.shutdown()
    }

    private fun postStatus(status: String) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            onStatus?.invoke(status)
        }
    }
}