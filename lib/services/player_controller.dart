import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../models/track.dart';
import 'audio_router.dart';
import 'media_notification.dart';
import 'metadata_service.dart';

const _audioExtensions = {
  '.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg', '.opus', '.wma', '.aiff',
  '.aif', '.alac',
};

/// Central app state: the library of imported tracks, the active "call",
/// playback transport, and the chosen audio output route.
///
/// Playback is deliberately simple — one file at a time via [setFilePath],
/// which is the approach that worked in the original build. Next/previous are
/// handled manually against [tracks].
class PlayerController extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  final AudioRouter _router = AudioRouter();
  final MetadataService _meta = MetadataService();
  final MediaNotification _media = MediaNotification();

  final List<Track> tracks = <Track>[];

  Track? _current;
  Track? get current => _current;

  AudioOutput _output = AudioOutput.speaker;
  AudioOutput get output => _output;

  bool _muted = false;
  bool get muted => _muted;

  bool _busy = false;
  bool get busy => _busy;

  bool get playing => _player.playing;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Future<void> init() async {
    await _router.init();

    // Lock-screen controls (best-effort; never affects playback).
    _media.onAction = _onMediaAction;
    try {
      await Permission.notification.request();
    } catch (_) {}

    // Set voice-communication attributes ONCE, before any source loads, so the
    // OS treats playback like a call and setCommunicationDevice() can move it
    // to the earpiece. Changing this later would recreate the player.
    try {
      await _player.setAndroidAudioAttributes(
        const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
      );
    } catch (e) {
      debugPrint('setAndroidAudioAttributes failed: $e');
    }

    await setOutput(AudioOutput.speaker);

    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _onCompleted();
      }
      _updateProximity();
      _syncNotification();
      notifyListeners();
    });
  }

  void _onMediaAction(String action) {
    switch (action) {
      case 'play':
      case 'pause':
        togglePlay();
      case 'next':
        next();
      case 'previous':
        previous();
      case 'stop':
        endCall();
    }
  }

  void _syncNotification() {
    final track = _current;
    if (track == null) {
      _media.hide();
      return;
    }
    _media.show(
      title: track.title,
      artist: track.artist ?? 'AudioRoute',
      isPlaying: _player.playing,
      hasNext: tracks.length > 1,
      hasPrevious: tracks.length > 1,
      artPath: track.artUri?.toFilePath(),
    );
  }

  // ---- Importing -----------------------------------------------------------

  /// Returns the number of new tracks added.
  Future<int> importTracks() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null) return 0;
    final paths =
        result.files.map((f) => f.path).whereType<String>().toList();
    return _addPaths(paths);
  }

  /// Returns the number of new tracks added, or `null` if the folder couldn't
  /// be read (e.g. storage permission denied).
  Future<int?> importFolder() async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) return 0; // cancelled

    final dir = Directory(dirPath);
    var paths = await _scanFolder(dir);
    if (paths == null) {
      if (Platform.isAndroid) {
        await Permission.manageExternalStorage.request();
      }
      paths = await _scanFolder(dir);
    }
    if (paths == null) {
      debugPrint('importFolder: could not read $dirPath');
      return null;
    }
    return _addPaths(paths);
  }

  Future<List<String>?> _scanFolder(Directory dir) async {
    try {
      final paths = <String>[];
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File && _isAudio(entity.path)) {
          paths.add(entity.path);
        }
      }
      paths.sort();
      return paths;
    } catch (e) {
      debugPrint('_scanFolder failed: $e');
      return null;
    }
  }

  bool _isAudio(String path) =>
      _audioExtensions.contains(p.extension(path).toLowerCase());

  Future<int> _addPaths(List<String> paths) async {
    _busy = true;
    notifyListeners();
    var added = 0;
    for (final path in paths) {
      if (tracks.any((t) => t.path == path)) continue;
      final track = Track(title: _titleFromPath(path), path: path);
      final meta = await _meta.lookup(path);
      track.artist = meta.artist ?? track.artist;
      track.artwork = meta.artwork;
      track.artUri = meta.artUri;
      tracks.add(track);
      added++;
      notifyListeners();
    }
    _busy = false;
    notifyListeners();
    return added;
  }

  String _titleFromPath(String path) {
    final name = p.basenameWithoutExtension(path);
    return name.replaceAll('_', ' ').replaceAll('-', ' ').trim();
  }

  // ---- Transport -----------------------------------------------------------

  int _indexOfCurrent() => _current == null
      ? -1
      : tracks.indexWhere((t) => t.path == _current!.path);

  Future<void> play(Track track) async {
    _current = track;
    notifyListeners();
    try {
      await _player.setFilePath(track.path);
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

  Future<void> next() async {
    if (tracks.isEmpty) return;
    final i = _indexOfCurrent();
    final nextIndex = i < 0 ? 0 : (i + 1) % tracks.length;
    await play(tracks[nextIndex]);
  }

  Future<void> previous() async {
    // Restart the track if we're past the first few seconds, else go back one.
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    if (tracks.isEmpty) return;
    final i = _indexOfCurrent();
    final prevIndex = i <= 0 ? tracks.length - 1 : i - 1;
    await play(tracks[prevIndex]);
  }

  Future<void> _onCompleted() async {
    final i = _indexOfCurrent();
    if (i >= 0 && i < tracks.length - 1) {
      await next();
    } else {
      await _player.pause();
      await _player.seek(Duration.zero);
    }
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> toggleMute() async {
    _muted = !_muted;
    await _player.setVolume(_muted ? 0 : 1);
    notifyListeners();
  }

  // ---- Routing -------------------------------------------------------------

  /// Switch the physical output. Audio attributes stay constant — only the
  /// communication device changes — so playback is never interrupted.
  Future<void> setOutput(AudioOutput output) async {
    _output = output;
    await _router.applyOutput(output);
    _updateProximity();
    notifyListeners();
  }

  Future<void> toggleOutput() => setOutput(
        _output == AudioOutput.earpiece
            ? AudioOutput.speaker
            : AudioOutput.earpiece,
      );

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
    _media.hide();
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
