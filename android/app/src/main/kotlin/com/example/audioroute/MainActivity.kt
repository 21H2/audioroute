package com.example.audioroute

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Flutter's [AudioRouter] to Android's [AudioManager].
 *
 * The trick: to push *media* out of the small front earpiece (instead of the
 * loudspeaker) we put the device into communication mode and pick the built-in
 * earpiece as the active communication device — exactly what a phone call does.
 *
 * The matching player-side audio attributes (voiceCommunication usage) are set
 * from Dart via just_audio's setAndroidAudioAttributes; both halves are needed.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "audioroute/routing"

    private val audioManager: AudioManager
        get() = getSystemService(Context.AUDIO_SERVICE) as AudioManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "routeToEarpiece" -> {
                        routeTo(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE)
                        result.success(true)
                    }
                    "routeToSpeaker" -> {
                        routeTo(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)
                        result.success(true)
                    }
                    "reset" -> {
                        reset()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun routeTo(deviceType: Int) {
        val am = audioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // API 31+: explicit communication-device selection.
            am.mode = AudioManager.MODE_IN_COMMUNICATION
            val target = am.availableCommunicationDevices
                .firstOrNull { it.type == deviceType }
            if (target != null) {
                am.setCommunicationDevice(target)
            }
        } else {
            // Legacy: speakerphone flag toggles earpiece vs. loudspeaker.
            am.mode = AudioManager.MODE_IN_COMMUNICATION
            @Suppress("DEPRECATION")
            am.isSpeakerphoneOn = (deviceType == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)
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
}
