import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where playback should physically come out of the device.
enum AudioOutput {
  /// The small front earpiece — the "on a call" experience.
  earpiece,

  /// The loud bottom speaker — normal system/media audio.
  speaker,
}

/// Owns the platform-level audio routing.
///
/// Earpiece routing needs three things to agree:
///   1. The [AudioSession] is configured with voice-communication attributes
///      (so the OS treats us like a call).
///   2. The native [MethodChannel] puts [AudioManager] into communication mode
///      and selects the built-in earpiece as the active device.
///   3. The just_audio player advertises voiceCommunication usage
///      (set in `PlayerController._applyAttributes`).
class AudioRouter {
  static const MethodChannel _channel = MethodChannel('audioroute/routing');

  AudioSession? _session;

  Future<void> init() async {
    _session = await AudioSession.instance;
  }

  /// Apply (or re-assert) the requested physical output route.
  Future<void> applyOutput(AudioOutput output) async {
    try {
      await _configureSession(output);
      await _session?.setActive(true);
      switch (output) {
        case AudioOutput.earpiece:
          await _channel.invokeMethod<bool>('routeToEarpiece');
        case AudioOutput.speaker:
          await _channel.invokeMethod<bool>('routeToSpeaker');
      }
    } catch (e) {
      debugPrint('AudioRouter.applyOutput failed: $e');
    }
  }

  Future<void> _configureSession(AudioOutput output) async {
    final session = _session ??= await AudioSession.instance;
    if (output == AudioOutput.earpiece) {
      await session.configure(
        const AudioSessionConfiguration(
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        ),
      );
    } else {
      await session.configure(const AudioSessionConfiguration.music());
    }
  }

  /// Restore the device to its normal (non-call) audio mode.
  Future<void> reset() async {
    try {
      await _channel.invokeMethod<bool>('reset');
      await _session?.setActive(false);
    } catch (e) {
      debugPrint('AudioRouter.reset failed: $e');
    }
  }

  /// Hold a proximity wake lock so the screen blanks when the phone is at the
  /// ear — exactly how a real phone call behaves.
  Future<void> startProximity() async {
    try {
      await _channel.invokeMethod<bool>('startProximity');
    } catch (e) {
      debugPrint('AudioRouter.startProximity failed: $e');
    }
  }

  Future<void> stopProximity() async {
    try {
      await _channel.invokeMethod<bool>('stopProximity');
    } catch (e) {
      debugPrint('AudioRouter.stopProximity failed: $e');
    }
  }
}
