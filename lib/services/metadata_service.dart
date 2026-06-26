import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Metadata resolved for one track.
class TrackMeta {
  const TrackMeta({this.artist, this.artwork, this.artUri});
  final String? artist;
  final Uint8List? artwork;
  final Uri? artUri;
}

/// Resolves artist + album art for imported files by matching their path
/// against the device media library (MediaStore) via `on_audio_query`.
///
/// Files that aren't indexed by MediaStore simply return empty metadata —
/// the UI falls back to a lettered avatar, so this is always best-effort.
class MetadataService {
  final OnAudioQuery _query = OnAudioQuery();

  List<SongModel>? _songs;
  bool? _granted;
  Directory? _cacheDir;

  Future<bool> _ensurePermission() async {
    if (_granted != null) return _granted!;
    var ok = await _query.permissionsStatus();
    if (!ok) ok = await _query.permissionsRequest();
    return _granted = ok;
  }

  Future<void> _loadSongs() async {
    _songs ??= await _query.querySongs();
  }

  Future<TrackMeta> lookup(String path) async {
    try {
      if (!await _ensurePermission()) return const TrackMeta();
      await _loadSongs();

      SongModel? song;
      for (final s in _songs ?? const <SongModel>[]) {
        if (s.data == path) {
          song = s;
          break;
        }
      }
      if (song == null) return const TrackMeta();

      final art = await _query.queryArtwork(
        song.id,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 600,
      );

      final artist = (song.artist == null || song.artist == '<unknown>')
          ? null
          : song.artist;
      final artUri = art == null ? null : await _cacheArt(song.id, art);

      return TrackMeta(artist: artist, artwork: art, artUri: artUri);
    } catch (e) {
      debugPrint('MetadataService.lookup failed: $e');
      return const TrackMeta();
    }
  }

  /// Persist artwork bytes so the media notification can reference them by URI.
  Future<Uri?> _cacheArt(int id, Uint8List bytes) async {
    try {
      _cacheDir ??= await getTemporaryDirectory();
      final file = File(p.join(_cacheDir!.path, 'art_$id.jpg'));
      if (!file.existsSync()) await file.writeAsBytes(bytes);
      return Uri.file(file.path);
    } catch (e) {
      debugPrint('MetadataService._cacheArt failed: $e');
      return null;
    }
  }
}
