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
/// On Android this combines two things:
///   1. A native [MethodChannel] (see `MainActivity.kt`) that flips the
///      [AudioManager] into communication mode and selects the built-in
///      earpiece vs. speaker as the active communication device.
///   2. The [AudioSession] focus configuration so the OS treats us politely.
///
/// The matching ExoPlayer audio *attributes* (media vs. voiceCommunication
/// usage) are set on the player itself in `PlayerController._applyAttributes`.
class AudioRouter {
  static const MethodChannel _channel = MethodChannel('audioroute/routing');

  AudioSession? _session;

  Future<void> init() async {
    _session = await AudioSession.instance;
    // Request focus appropriate for media; the OS handles ducking/interrupts.
    await _session!.configure(const AudioSessionConfiguration.music());
  }

  /// Apply the requested physical output route.
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
      // PlatformException on failure, or MissingPluginException before the
      // engine attaches the channel — non-fatal either way.
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
}
