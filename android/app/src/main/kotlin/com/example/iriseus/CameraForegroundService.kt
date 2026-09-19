package com.example.iriseus

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.PowerManager
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService

/**
 * ForegroundService que gerencia câmera + encoder + TCP stream.
 * Permanece ativo com tela desligada graças ao WakeLock PARTIAL e
 * à notificação persistente exigida pelo Android para câmera em background.
 */
class CameraForegroundService : LifecycleService() {

    companion object {
        private const val TAG = "CameraForegroundService"
        private const val CHANNEL_ID = "iriseus_stream"
        private const val NOTIFICATION_ID = 1

        const val ACTION_START_STREAM  = "com.example.iriseus.START_STREAM"
        const val ACTION_STOP_STREAM   = "com.example.iriseus.STOP_STREAM"
        const val ACTION_SWITCH_CAMERA = "com.example.iriseus.SWITCH_CAMERA"
        const val ACTION_STOP_SERVICE  = "com.example.iriseus.STOP_SERVICE"

        const val EXTRA_IP   = "ip"
        const val EXTRA_PORT = "port"

        @Volatile var activeStreamer: CameraStreamer? = null
        @Volatile var currentPreviewView: PreviewView? = null
        var statusCallback: ((String) -> Unit)? = null

        fun attachPreview(pv: PreviewView?) {
            currentPreviewView = pv
            activeStreamer?.setPreviewView(pv)
        }

        /** Inicia o serviço e começa a transmissão. */
        fun startStream(context: Context, ip: String, port: Int) {
            val intent = Intent(context, CameraForegroundService::class.java).apply {
                action = ACTION_START_STREAM
                putExtra(EXTRA_IP, ip)
                putExtra(EXTRA_PORT, port)
            }
            ContextCompat.startForegroundService(context, intent)
        }

        /** Para a transmissão e encerra o serviço. */
        fun stopStream(context: Context) {
            context.startService(Intent(context, CameraForegroundService::class.java).apply {
                action = ACTION_STOP_STREAM
            })
        }

        fun switchCamera(context: Context) {
            context.startService(Intent(context, CameraForegroundService::class.java).apply {
                action = ACTION_SWITCH_CAMERA
            })
        }
    }

    // ─── Estado interno ────────────────────────────────────────────────────
    private var streamer: CameraStreamer? = null
    private var wakeLock: PowerManager.WakeLock? = null

    // ─── Lifecycle ─────────────────────────────────────────────────────────
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)

        when (intent?.action) {
            ACTION_START_STREAM -> {
                val ip   = intent.getStringExtra(EXTRA_IP)   ?: "127.0.0.1"
                val port = intent.getIntExtra(EXTRA_PORT, 45679)
                startForegroundWithNotification()
                initStreamerAndStart(ip, port)
            }
            ACTION_STOP_STREAM -> {
                stopStreamInternal()
                stopSelf()
            }
            ACTION_SWITCH_CAMERA -> streamer?.switchCamera()
            ACTION_STOP_SERVICE  -> { stopStreamInternal(); stopSelf() }
        }

        return START_STICKY
    }

    override fun onDestroy() {
        stopStreamInternal()
        releaseWakeLock()
        super.onDestroy()
    }

    // ─── Streaming ─────────────────────────────────────────────────────────
    private fun initStreamerAndStart(ip: String, port: Int) {
        val s = CameraStreamer(this, this, currentPreviewView)
        streamer = s
        activeStreamer = s
        s.startPreview()
        s.startStreaming(ip, port) { status ->
            statusCallback?.invoke(status)
            updateNotificationStatus(status)
        }
    }

    private fun stopStreamInternal() {
        activeStreamer = null
        streamer?.stopStreaming()
        streamer?.release()
        streamer = null
    }

    // ─── Notificação persistente ────────────────────────────────────────────
    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Iriseus — Transmissão",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Notificação de transmissão ativa da câmera"
            setShowBadge(false)
        }
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(statusText: String = "Transmitindo..."): Notification {
        val stopIntent = PendingIntent.getService(
            this, 0,
            Intent(this, CameraForegroundService::class.java).apply { action = ACTION_STOP_SERVICE },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val openIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Iriseus")
            .setContentText(statusText)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .addAction(
                Notification.Action.Builder(
                    android.graphics.drawable.Icon.createWithResource(this, android.R.drawable.ic_media_pause),
                    "Parar",
                    stopIntent
                ).build()
            )
            .build()
    }

    private fun startForegroundWithNotification() {
        val notification = buildNotification("Iniciando câmera...")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotificationStatus(status: String) {
        val text = when (status) {
            "streaming"  -> "Câmera transmitindo para o PC"
            "connecting" -> "Conectando ao PC..."
            "error"      -> "Erro na transmissão — reconectando"
            else         -> "Iriseus ativo"
        }
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification(text))
    }

    // ─── WakeLock ───────────────────────────────────────────────────────────
    private fun acquireWakeLock() {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "iriseus::StreamWakeLock"
        ).apply { acquire(60 * 60 * 1000L /* 1h máximo */) }
    }

    private fun releaseWakeLock() {
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
    }
}
