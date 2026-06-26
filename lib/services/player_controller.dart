import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path/path.dart' as p;

import '../models/track.dart';
import 'audio_router.dart';
import 'metadata_service.dart';

/// Central app state: the library of imported tracks, the active "call",
/// playback transport, and the chosen audio output route.
class PlayerController extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  final AudioRouter _router = AudioRouter();
  final MetadataService _meta = MetadataService();

  final List<Track> tracks = <Track>[];

  Track? _current;
  Track? get current => _current;

  AudioOutput _output = AudioOutput.earpiece;
  AudioOutput get output => _output;

  bool _muted = false;
  bool get muted => _muted;

  bool get playing => _player.playing;

  /// Streams the UI binds to directly (avoids rebuilding on every tick).
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Future<void> init() async {
    await _router.init();
    // Default route is the earpiece — the whole point of the app.
    await setOutput(AudioOutput.earpiece);

    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        // Treat end-of-track like the call winding down: rewind and pause.
        _player.seek(Duration.zero);
        _player.pause();
      }
      _updateProximity();
      notifyListeners();
    });
  }

  /// Let the user pick one or more local audio files to add to the library.
  Future<void> importTracks() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null) return;

    final added = <Track>[];
    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue;
      if (tracks.any((t) => t.path == path)) continue;
      final track = Track(title: _titleFromPath(path), path: path);
      tracks.add(track);
      added.add(track);
    }
    notifyListeners();

    // Enrich with artist + album art in the background.
    for (final track in added) {
      final meta = await _meta.lookup(track.path);
      track.artist = meta.artist ?? track.artist;
      track.artwork = meta.artwork;
      track.artUri = meta.artUri;
      notifyListeners();
    }
  }

  String _titleFromPath(String path) {
    final name = p.basenameWithoutExtension(path);
    return name.replaceAll('_', ' ').replaceAll('-', ' ').trim();
  }

  /// Start a "call" with [track] — load it and begin playback.
  Future<void> play(Track track) async {
    _current = track;
    notifyListeners();
    try {
      await _applyAttributes();
      final uri = Uri.file(track.path);
      try {
        await _player.setAudioSource(
          AudioSource.uri(
            uri,
            tag: MediaItem(
              id: track.path,
              title: track.title,
              artist: track.artist ?? 'AudioRoute',
              artUri: track.artUri,
            ),
          ),
        );
      } catch (e) {
        // Background service unavailable — play without notification metadata
        // rather than failing outright.
        debugPrint('Tagged source failed ($e); falling back to plain source.');
        await _player.setAudioSource(AudioSource.uri(uri));
      }
      await _player.play();
    } catch (e) {
      debugPrint('PlayerController.play failed: $e');
    }
    _updateProximity();
    notifyListeners();
  }

  Future<void> togglePlay() async {
    if (_player.playing) {
      await _player.pause();
    } else if (_current == null && tracks.isNotEmpty) {
      await play(tracks.first);
      return;
    } else {
      await _player.play();
    }
    _updateProximity();
    notifyListeners();
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> skip(Duration delta) async {
    final target = _player.position + delta;
    final max = _player.duration ?? Duration.zero;
    await _player.seek(target < Duration.zero
        ? Duration.zero
        : (target > max ? max : target));
  }

  Future<void> toggleMute() async {
    _muted = !_muted;
    await _player.setVolume(_muted ? 0 : 1);
    notifyListeners();
  }

  /// Switch the physical output and re-apply matching player attributes.
  Future<void> setOutput(AudioOutput output) async {
    _output = output;
    await _router.applyOutput(output);
    await _applyAttributes();
    _updateProximity();
    notifyListeners();
  }

  Future<void> toggleOutput() => setOutput(
        _output == AudioOutput.earpiece
            ? AudioOutput.speaker
            : AudioOutput.earpiece,
      );

  /// Tell ExoPlayer which audio "usage" to advertise. `voiceCommunication`
  /// is what makes the OS route playback through the earpiece; `media` is
  /// normal system audio out of the loudspeaker.
  Future<void> _applyAttributes() async {
    try {
      await _player.setAndroidAudioAttributes(
        AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: _output == AudioOutput.earpiece
              ? AndroidAudioUsage.voiceCommunication
              : AndroidAudioUsage.media,
        ),
      );
    } catch (e) {
      debugPrint('PlayerController._applyAttributes failed: $e');
    }
  }

  /// Blank the screen via the proximity sensor only while we're actually
  /// "on a call" — i.e. playing through the earpiece.
  void _updateProximity() {
    if (_player.playing && _output == AudioOutput.earpiece) {
      _router.startProximity();
    } else {
      _router.stopProximity();
    }
  }

  /// "End call" — stop playback and restore normal device audio mode.
  Future<void> endCall() async {
    await _player.stop();
    await _router.stopProximity();
    await _router.reset();
    _current = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
