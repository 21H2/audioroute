package com.example.audioroute

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Flutter's [AudioRouter] to Android's [AudioManager] and [PowerManager].
 *
 * The trick: to push *media* out of the small front earpiece (instead of the
 * loudspeaker) we put the device into communication mode and pick the built-in
 * earpiece as the active communication device — exactly what a phone call does.
 *
 * We also hold a PROXIMITY_SCREEN_OFF wake lock while "on a call" so the display
 * blanks when the phone is against the ear, just like the real dialer.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "audioroute/routing"
    private var proximityLock: PowerManager.WakeLock? = null

    private val audioManager: AudioManager
        get() = getSystemService(Context.AUDIO_SERVICE) as AudioManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "routeToEarpiece" -> {
                        result.success(routeToEarpiece())
                    }
                    "routeToSpeaker" -> {
                        result.success(routeToSpeaker())
                    }
                    "reset" -> {
                        reset()
                        result.success(true)
                    }
                    "startProximity" -> {
                        startProximity()
                        result.success(true)
                    }
                    "stopProximity" -> {
                        stopProximity()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun routeToEarpiece(): Boolean {
        val am = audioManager
        // Communication mode + earpiece device is the 2026-canonical recipe.
        am.mode = AudioManager.MODE_IN_COMMUNICATION
        val ok = selectDevice(am, AudioDeviceInfo.TYPE_BUILTIN_EARPIECE, speakerFallback = false)
        boostVoiceVolume(am, 1.0)
        return ok
    }

    private fun routeToSpeaker(): Boolean {
        val am = audioManager
        // Stay in communication mode and just move to the speaker device, so
        // switching never requires recreating the player.
        am.mode = AudioManager.MODE_IN_COMMUNICATION
        val ok = selectDevice(am, AudioDeviceInfo.TYPE_BUILTIN_SPEAKER, speakerFallback = true)
        boostVoiceVolume(am, 0.7)
        return ok
    }

    private fun selectDevice(am: AudioManager, type: Int, speakerFallback: Boolean): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val device = am.availableCommunicationDevices.firstOrNull { it.type == type }
            val ok = device != null && am.setCommunicationDevice(device)
            Log.i("AudioRoute", "setCommunicationDevice(type=$type)=$ok")
            if (!ok) {
                @Suppress("DEPRECATION")
                am.isSpeakerphoneOn = speakerFallback
            }
            return ok
        } else {
            @Suppress("DEPRECATION")
            am.isSpeakerphoneOn = speakerFallback
            return true
        }
    }

    // Bump the in-call volume stream so playback is actually audible (it
    // defaults to near-zero, which is the usual "earpiece is silent" cause).
    private fun boostVoiceVolume(am: AudioManager, fraction: Double) {
        try {
            val max = am.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
            val target = (max * fraction).toInt().coerceIn(1, max)
            am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, target, 0)
        } catch (e: Exception) {
            Log.w("AudioRoute", "setStreamVolume failed: ${e.message}")
        }
    }

    private fun reset() {
        val am = audioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            am.clearCommunicationDevice()
        } else {
            @Suppress("DEPRECATION")
            am.isSpeakerphoneOn = false
        }
        am.mode = AudioManager.MODE_NORMAL
    }

    private fun startProximity() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) {
            return
        }
        if (proximityLock == null) {
            proximityLock = pm.newWakeLock(
                PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
                "audioroute:proximity",
            )
        }
        if (proximityLock?.isHeld == false) {
            proximityLock?.acquire()
        }
    }

    private fun stopProximity() {
        if (proximityLock?.isHeld == true) {
            // Wait for the phone to leave the ear before turning the screen back on.
            proximityLock?.release(PowerManager.RELEASE_FLAG_WAIT_FOR_NO_PROXIMITY)
        }
    }

    override fun onDestroy() {
        stopProximity()
        super.onDestroy()
    }
}
