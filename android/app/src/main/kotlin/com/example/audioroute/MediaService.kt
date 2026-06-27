package com.example.audioroute

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import io.flutter.plugin.common.MethodChannel

/**
 * A small foreground service that mirrors the (Dart-side) player as a
 * MediaSession + media-style notification, giving lock-screen controls.
 *
 * It does NOT play audio — playback stays entirely in just_audio on the Dart
 * side. Button presses here are forwarded back to Dart via [dartChannel], so a
 * failure in this layer can never affect playback.
 */
class MediaService : Service() {

    companion object {
        const val CHANNEL_ID = "audioroute_media"
        const val NOTI_ID = 1001

        const val EXTRA_TITLE = "title"
        const val EXTRA_ARTIST = "artist"
        const val EXTRA_PLAYING = "isPlaying"
        const val EXTRA_HAS_NEXT = "hasNext"
        const val EXTRA_HAS_PREV = "hasPrevious"
        const val EXTRA_ART = "artPath"

        const val ACTION_UPDATE = "audioroute.UPDATE"
        const val ACTION_PLAY = "play"
        const val ACTION_PAUSE = "pause"
        const val ACTION_NEXT = "next"
        const val ACTION_PREV = "previous"
        const val ACTION_STOP = "stop"

        // Bridge back to Dart, assigned by MainActivity while the engine lives.
        var dartChannel: MethodChannel? = null
        private val main = Handler(Looper.getMainLooper())

        fun dispatch(action: String) {
            main.post {
                try {
                    dartChannel?.invokeMethod("action", action)
                } catch (e: Exception) {
                    Log.e("AudioRoute", "dispatch failed: ${e.message}")
                }
            }
        }
    }

    private var session: MediaSessionCompat? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        session = MediaSessionCompat(this, "AudioRoute").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() = dispatch(ACTION_PLAY)
                override fun onPause() = dispatch(ACTION_PAUSE)
                override fun onSkipToNext() = dispatch(ACTION_NEXT)
                override fun onSkipToPrevious() = dispatch(ACTION_PREV)
                override fun onStop() = dispatch(ACTION_STOP)
            })
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            when (intent?.action) {
                ACTION_PLAY -> dispatch(ACTION_PLAY)
                ACTION_PAUSE -> dispatch(ACTION_PAUSE)
                ACTION_NEXT -> dispatch(ACTION_NEXT)
                ACTION_PREV -> dispatch(ACTION_PREV)
                ACTION_STOP -> {
                    dispatch(ACTION_STOP)
                    stop()
                    return START_NOT_STICKY
                }
                else -> updateFromIntent(intent)
            }
        } catch (e: Exception) {
            Log.e("AudioRoute", "MediaService.onStartCommand: ${e.message}")
        }
        return START_NOT_STICKY
    }

    private fun updateFromIntent(intent: Intent?) {
        intent ?: return
        showNotification(
            title = intent.getStringExtra(EXTRA_TITLE) ?: "AudioRoute",
            artist = intent.getStringExtra(EXTRA_ARTIST) ?: "",
            playing = intent.getBooleanExtra(EXTRA_PLAYING, false),
            hasNext = intent.getBooleanExtra(EXTRA_HAS_NEXT, false),
            hasPrev = intent.getBooleanExtra(EXTRA_HAS_PREV, false),
            artPath = intent.getStringExtra(EXTRA_ART),
        )
    }

    private fun showNotification(
        title: String,
        artist: String,
        playing: Boolean,
        hasNext: Boolean,
        hasPrev: Boolean,
        artPath: String?,
    ) {
        val sess = session ?: return
        val art = artPath?.let {
            try {
                BitmapFactory.decodeFile(it)
            } catch (e: Exception) {
                null
            }
        }

        sess.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
                .apply {
                    if (art != null) {
                        putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, art)
                    }
                }
                .build(),
        )
        sess.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY_PAUSE or
                        PlaybackStateCompat.ACTION_PLAY or
                        PlaybackStateCompat.ACTION_PAUSE or
                        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                        PlaybackStateCompat.ACTION_STOP,
                )
                .setState(
                    if (playing) PlaybackStateCompat.STATE_PLAYING
                    else PlaybackStateCompat.STATE_PAUSED,
                    PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN,
                    1.0f,
                )
                .build(),
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(artist)
            .setOnlyAlertOnce(true)
            .setOngoing(playing)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(contentIntent())
            .setDeleteIntent(actionIntent(ACTION_STOP))
        if (art != null) builder.setLargeIcon(art)

        if (hasPrev) {
            builder.addAction(
                android.R.drawable.ic_media_previous, "Previous", actionIntent(ACTION_PREV),
            )
        }
        builder.addAction(
            if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
            if (playing) "Pause" else "Play",
            actionIntent(if (playing) ACTION_PAUSE else ACTION_PLAY),
        )
        if (hasNext) {
            builder.addAction(
                android.R.drawable.ic_media_next, "Next", actionIntent(ACTION_NEXT),
            )
        }

        builder.setStyle(
            MediaStyle()
                .setMediaSession(sess.sessionToken)
                .setShowActionsInCompactView(if (hasPrev) 1 else 0),
        )

        startForegroundCompat(builder.build())
    }

    private fun startForegroundCompat(notification: Notification) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTI_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else {
                startForeground(NOTI_ID, notification)
            }
        } catch (e: Exception) {
            Log.e("AudioRoute", "startForeground failed: ${e.message}")
        }
    }

    private fun contentIntent(): PendingIntent {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        return PendingIntent.getActivity(this, 0, launch, pendingFlags())
    }

    private fun actionIntent(action: String): PendingIntent {
        val intent = Intent(this, MediaService::class.java).setAction(action)
        return PendingIntent.getService(this, action.hashCode(), intent, pendingFlags())
    }

    private fun pendingFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

    private fun stop() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (e: Exception) {
            Log.e("AudioRoute", "stopForeground failed: ${e.message}")
        }
        stopSelf()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                mgr.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        "Playback",
                        NotificationManager.IMPORTANCE_LOW,
                    ).apply {
                        setShowBadge(false)
                        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    },
                )
            }
        }
    }

    override fun onDestroy() {
        stop()
        session?.isActive = false
        session?.release()
        session = null
        super.onDestroy()
    }
}
