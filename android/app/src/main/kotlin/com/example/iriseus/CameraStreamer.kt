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
import java.io.OutputStream
import java.net.Socket
import java.nio.ByteBuffer
import java.util.concurrent.Executors

class CameraStreamer(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private var previewView: PreviewView? = null,
) {
    companion object {
        private const val TAG = "CameraStreamer"
        // Resolução 1080p (Full HD) — com fallback natural se a câmera suportar no máximo 720p
        private const val WIDTH = 1920
        private const val HEIGHT = 1080
        private const val FRAME_RATE = 30
        // 6.0 Mbps para alta fidelidade e nitidez total via USB
        private const val BITRATE = 6_000_000
        private const val I_FRAME_INTERVAL = 1
    }

    private var cameraProvider: ProcessCameraProvider? = null
    private var lensFacing = CameraSelector.LENS_FACING_BACK
    @Volatile private var encoder: MediaCodec? = null
    private var socket: Socket? = null
    private var outputStream: OutputStream? = null
    @Volatile private var streaming = false
    private val encoderLock = Any()
    private var analysisExecutor = Executors.newSingleThreadExecutor()
    private var networkExecutor  = Executors.newSingleThreadExecutor()
    private var onStatus: ((String) -> Unit)? = null
    private var encoderWidth  = 0
    private var encoderHeight = 0
    @Volatile private var pendingWidth  = 0
    @Volatile private var pendingHeight = 0

    // Buffers reutilizáveis — zero alocações por frame
    private var writeBuffer = ByteArray(4 + 128 * 1024)
    private var yRowBuffer  = ByteArray(4096)
    private var uvRowBuffer = ByteArray(4096)

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

        val useCases = mutableListOf<androidx.camera.core.UseCase>()

        previewView?.let { pv ->
            val preview = Preview.Builder()
                .build().also {
                    it.setSurfaceProvider(pv.surfaceProvider)
                }
            useCases.add(preview)
        }

        val analysis = ImageAnalysis.Builder()
            .setTargetResolution(Size(WIDTH, HEIGHT))
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
            .build()
        analysis.setAnalyzer(analysisExecutor) { image -> onFrame(image) }
        useCases.add(analysis)

        val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()
        provider.bindToLifecycle(lifecycleOwner, selector, *useCases.toTypedArray())
    }

    fun setPreviewView(pv: PreviewView?) {
        previewView = pv
        if (cameraProvider != null) {
            bindUseCases()
        }
    }

    fun switchCamera() {
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK)
            CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK
        bindUseCases()
    }

    fun startStreaming(ip: String, port: Int, statusCallback: (String) -> Unit) {
        onStatus = statusCallback
        if (streaming) stopStreaming()

        if (networkExecutor.isShutdown)  networkExecutor  = Executors.newSingleThreadExecutor()
        if (analysisExecutor.isShutdown) analysisExecutor = Executors.newSingleThreadExecutor()

        encoderWidth  = 0
        encoderHeight = 0
        streaming = true
        postStatus("connecting")

        networkExecutor.execute {
            try {
                socket = Socket(ip, port).apply {
                    tcpNoDelay = true
                    sendBufferSize = 512 * 1024
                }
                outputStream = socket!!.getOutputStream()
                postStatus("streaming")
                drainEncoderLoop()
            } catch (e: Exception) {
                Log.e(TAG, "Erro de rede", e)
                streaming = false
                releaseEncoder()
                postStatus("error")
            }
        }
    }

    private fun setupEncoder(w: Int, h: Int) {
        encoderWidth  = w
        encoderHeight = h
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, w, h).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar)
            setInteger(MediaFormat.KEY_BIT_RATE,        BITRATE)
            setInteger(MediaFormat.KEY_FRAME_RATE,      FRAME_RATE)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, I_FRAME_INTERVAL)
            setInteger(MediaFormat.KEY_BITRATE_MODE,
                MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR)
            try {
                setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileHigh)
            } catch (_: Exception) {}
        }
        encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC).apply {
            configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            start()
        }
    }

    private fun drainEncoderLoop() {
        val bufferInfo = MediaCodec.BufferInfo()
        while (streaming) {
            if (pendingWidth != 0 && pendingHeight != 0) {
                val w = pendingWidth
                val h = pendingHeight
                pendingWidth  = 0
                pendingHeight = 0
                releaseEncoder()
                setupEncoder(w, h)
                continue
            }

            val codec = encoder
            if (codec == null) {
                Thread.sleep(2)
                continue
            }

            val outIndex = codec.dequeueOutputBuffer(bufferInfo, 0)
            if (outIndex >= 0) {
                val outBuffer = codec.getOutputBuffer(outIndex) ?: run {
                    codec.releaseOutputBuffer(outIndex, false)
                    continue
                }
                val nalu = ByteArray(bufferInfo.size)
                outBuffer.get(nalu)
                writeFramed(nalu)
                codec.releaseOutputBuffer(outIndex, false)
            } else {
                Thread.sleep(1)
            }
        }
        try { outputStream?.flush() } catch (_: Exception) {}
    }

    private fun writeFramed(nalu: ByteArray) {
        try {
            val out = outputStream ?: return
            val totalSize = 4 + nalu.size

            if (writeBuffer.size < totalSize) {
                writeBuffer = ByteArray(totalSize + 4096)
            }

            val len = nalu.size
            writeBuffer[0] = (len shr 24).toByte()
            writeBuffer[1] = (len shr 16).toByte()
            writeBuffer[2] = (len shr  8).toByte()
            writeBuffer[3] =  len.toByte()
            System.arraycopy(nalu, 0, writeBuffer, 4, nalu.size)

            out.write(writeBuffer, 0, totalSize)
            out.flush() // Entrega imediata de cada frame ao PC — sem atraso nem rajada
        } catch (e: Exception) {
            postStatus("error")
            stopStreaming()
        }
    }

    private fun onFrame(image: ImageProxy) {
        if (!streaming) { image.close(); return }
        try {
            val w = image.width
            val h = image.height
            if (w != encoderWidth || h != encoderHeight) {
                pendingWidth  = w
                pendingHeight = h
                image.close()
                return
            }
            synchronized(encoderLock) {
                if (!streaming || encoder == null) {
                    image.close()
                    return
                }
                queueToEncoder(image)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Erro processando frame", e)
        } finally {
            image.close()
        }
    }

    private fun queueToEncoder(image: ImageProxy) {
        val codec = encoder ?: return
        val inIndex = codec.dequeueInputBuffer(10_000)
        if (inIndex < 0) {
            return
        }
        val inputBuffer = codec.getInputBuffer(inIndex) ?: return
        inputBuffer.clear()

        val width  = image.width
        val height = image.height
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        val yRowStride  = yPlane.rowStride
        val uvRowStride = uPlane.rowStride
        val uvPixStride = uPlane.pixelStride

        // ── Y plane ────────────────────────────────────────────────────────
        val yBuf = yPlane.buffer
        if (yRowBuffer.size < width) yRowBuffer = ByteArray(width)
        for (row in 0 until height) {
            yBuf.position(row * yRowStride)
            yBuf.get(yRowBuffer, 0, width)
            inputBuffer.put(yRowBuffer, 0, width)
        }

        // ── UV plane (NV12: interleaved U então V) ──────────────────────────
        val uBuf = uPlane.buffer
        val vBuf = vPlane.buffer
        val uvRows = height / 2
        val uvCols = width  / 2

        val uvRowSize = uvCols * 2
        if (uvRowBuffer.size < uvRowSize) uvRowBuffer = ByteArray(uvRowSize)

        if (uvPixStride == 2) {
            for (row in 0 until uvRows) {
                val uOffset = row * uvRowStride
                val vOffset = row * vPlane.rowStride
                for (col in 0 until uvCols) {
                    val c2 = col * 2
                    uvRowBuffer[c2]     = uBuf.get(uOffset + c2)
                    uvRowBuffer[c2 + 1] = vBuf.get(vOffset + c2)
                }
                inputBuffer.put(uvRowBuffer, 0, uvRowSize)
            }
        } else {
            for (row in 0 until uvRows) {
                val uOffset = row * uvRowStride
                val vOffset = row * vPlane.rowStride
                for (col in 0 until uvCols) {
                    uvRowBuffer[col * 2]     = uBuf.get(uOffset + col)
                    uvRowBuffer[col * 2 + 1] = vBuf.get(vOffset + col)
                }
                inputBuffer.put(uvRowBuffer, 0, uvRowSize)
            }
        }

        val bytesWritten = inputBuffer.position()
        codec.queueInputBuffer(inIndex, 0, bytesWritten, System.nanoTime() / 1000, 0)
    }

    fun stopStreaming() {
        streaming = false
        releaseEncoder()
        try { outputStream?.close() } catch (_: Exception) {}
        try { socket?.close() } catch (_: Exception) {}
        outputStream = null
        socket = null
        postStatus("idle")
    }

    fun release() {
        stopStreaming()
        cameraProvider?.unbindAll()
        cameraProvider = null
        analysisExecutor.shutdown()
        networkExecutor.shutdown()
    }

    private fun releaseEncoder() {
        synchronized(encoderLock) {
            try {
                encoder?.stop()
                encoder?.release()
            } catch (_: Exception) {}
            encoder = null
        }
    }

    private fun postStatus(status: String) {
        onStatus?.invoke(status)
    }
}