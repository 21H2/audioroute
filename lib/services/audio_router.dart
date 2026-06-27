import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where playback should physically come out of the device.
enum AudioOutput {
  /// The small front earpiece — the "on a call" experience.
  earpiece,

  /// The loud bottom speaker (speakerphone-style).
  speaker,
}

/// Owns the platform-level audio routing.
///
/// The player's audio attributes are set to voiceCommunication ONCE (in
/// [PlayerController.init]) and never changed. Switching earpiece/speaker is
/// done purely by selecting the communication device natively, so playback is
/// never interrupted.
class AudioRouter {
  static const MethodChannel _channel = MethodChannel('audioroute/routing');

  AudioSession? _session;

  Future<void> init() async {
    _session = await AudioSession.instance;
    await _session!.configure(
      const AudioSessionConfiguration(
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ),
    );
  }

  /// Apply (or re-assert) the requested physical output route.
  Future<void> applyOutput(AudioOutput output) async {
    try {
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

  /// Restore the device to its normal (non-call) audio mode.
  Future<void> reset() async {
    try {
      await _channel.invokeMethod<bool>('reset');
      await _session?.setActive(false);
    } catch (e) {
      debugPrint('AudioRouter.reset failed: $e');
    }
  }

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
