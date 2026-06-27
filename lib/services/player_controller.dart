import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../models/track.dart';
import 'audio_router.dart';
import 'metadata_service.dart';

/// Set by `main()` after attempting background-audio init. When false we add
/// plain (untagged) sources so playback still works without the notification.
bool backgroundAudioReady = false;

const _audioExtensions = {
  '.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg', '.opus', '.wma', '.aiff',
  '.aif', '.alac',
};

/// Central app state: the playlist of imported tracks, the active "call",
/// playback transport, and the chosen audio output route.
class PlayerController extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  final AudioRouter _router = AudioRouter();
  final MetadataService _meta = MetadataService();

  bool _sourceSet = false;

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

    // CRITICAL: set voice-communication attributes ONCE, before any audio
    // source is loaded. This makes the OS treat playback like a call so
    // setCommunicationDevice() can move it to the earpiece. Changing these
    // later would recreate the player and drop the source mid-playback.
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

    _player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < tracks.length) {
        _current = tracks[index];
        _updateProximity();
        notifyListeners();
      }
    });

    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero, index: 0);
      }
      _updateProximity();
      notifyListeners();
    });
  }

  // ---- Importing -----------------------------------------------------------

  Future<void> importTracks() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null) return;
    final paths =
        result.files.map((f) => f.path).whereType<String>().toList();
    await _addPaths(paths);
  }

  Future<void> importFolder() async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) return;

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
      return;
    }
    await _addPaths(paths);
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

  Future<void> _addPaths(List<String> paths) async {
    _busy = true;
    notifyListeners();
    var changed = false;
    for (final path in paths) {
      if (tracks.any((t) => t.path == path)) continue;
      final track = Track(title: _titleFromPath(path), path: path);

      final meta = await _meta.lookup(path);
      track.artist = meta.artist ?? track.artist;
      track.artwork = meta.artwork;
      track.artUri = meta.artUri;

      tracks.add(track);
      changed = true;
    }
    if (changed) await _rebuildSource();
    _busy = false;
    notifyListeners();
  }

  /// Build the whole playlist in one shot. Incrementally `.add()`-ing to a
  /// ConcatenatingAudioSource is buggy on just_audio 0.9.x, so we always
  /// rebuild and re-set the full source.
  Future<void> _rebuildSource() async {
    final sources = tracks.map(_sourceFor).toList();
    if (sources.isEmpty) return;
    final wasPlaying = _player.playing;
    final keepIndex =
        (_player.currentIndex ?? 0).clamp(0, sources.length - 1);
    final keepPos = _player.position;
    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(children: sources),
        initialIndex: keepIndex,
        initialPosition: keepPos,
      );
      _sourceSet = true;
      if (wasPlaying) await _player.play();
    } catch (e) {
      debugPrint('PlayerController._rebuildSource failed: $e');
    }
  }

  AudioSource _sourceFor(Track track) {
    final uri = Uri.file(track.path);
    if (!backgroundAudioReady) return AudioSource.uri(uri);
    return AudioSource.uri(
      uri,
      tag: MediaItem(
        id: track.path,
        title: track.title,
        artist: track.artist ?? 'AudioRoute',
        artUri: track.artUri,
      ),
    );
  }

  String _titleFromPath(String path) {
    final name = p.basenameWithoutExtension(path);
    return name.replaceAll('_', ' ').replaceAll('-', ' ').trim();
  }

  // ---- Transport -----------------------------------------------------------

  Future<void> play(Track track) async {
    final index = tracks.indexOf(track);
    if (index < 0) return;
    _current = track;
    notifyListeners();
    try {
      if (!_sourceSet) await _rebuildSource();
      await _player.seek(Duration.zero, index: index);
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
    if (_player.hasNext) {
      await _player.seekToNext();
    } else if (tracks.isNotEmpty) {
      await _player.seek(Duration.zero, index: 0);
    }
  }

  Future<void> previous() async {
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
    } else if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
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
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
