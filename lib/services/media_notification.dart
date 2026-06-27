import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart side of the native lock-screen media controls.
///
/// Sends the current track + playback state to the native [MediaService] and
/// receives button presses back via [onAction]. Entirely decoupled from
/// playback — every call is best-effort and guarded.
class MediaNotification {
  static const MethodChannel _channel = MethodChannel('audioroute/media');

  /// Called with 'play' | 'pause' | 'next' | 'previous' | 'stop'.
  void Function(String action)? onAction;

  MediaNotification() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'action' && call.arguments is String) {
        onAction?.call(call.arguments as String);
      }
    });
  }

  Future<void> show({
    required String title,
    required String artist,
    required bool isPlaying,
    required bool hasNext,
    required bool hasPrevious,
    String? artPath,
  }) async {
    try {
      await _channel.invokeMethod('show', {
        'title': title,
        'artist': artist,
        'isPlaying': isPlaying,
        'hasNext': hasNext,
        'hasPrevious': hasPrevious,
        'artPath': artPath,
      });
    } catch (e) {
      debugPrint('MediaNotification.show failed: $e');
    }
  }

  Future<void> hide() async {
    try {
      await _channel.invokeMethod('hide');
    } catch (e) {
      debugPrint('MediaNotification.hide failed: $e');
    }
  }
}
