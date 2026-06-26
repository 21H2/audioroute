import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Metadata resolved for one track.
class TrackMeta {
  const TrackMeta({this.artist, this.artwork, this.artUri});
  final String? artist;
  final Uint8List? artwork;
  final Uri? artUri;
}

/// Reads artist + embedded album art straight from an audio file's tags
/// (ID3 / MP4 / FLAC / Vorbis) using the pure-Dart `audio_metadata_reader`.
///
/// No native plugin and no media-library permission — it works on any file the
/// user imports. Missing tags simply yield empty metadata and the UI falls
/// back to a lettered avatar, so this is always best-effort.
class MetadataService {
  Directory? _cacheDir;

  Future<TrackMeta> lookup(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return const TrackMeta();

      final metadata = readMetadata(file, getImage: true);

      final rawArtist = metadata.artist?.trim();
      final artist = (rawArtist == null || rawArtist.isEmpty) ? null : rawArtist;

      Uint8List? art;
      if (metadata.pictures.isNotEmpty) {
        art = metadata.pictures.first.bytes;
      }

      final artUri = art == null ? null : await _cacheArt(path, art);
      return TrackMeta(artist: artist, artwork: art, artUri: artUri);
    } catch (e) {
      debugPrint('MetadataService.lookup failed: $e');
      return const TrackMeta();
    }
  }

  /// Persist artwork bytes so the media notification can reference them by URI.
  Future<Uri?> _cacheArt(String path, Uint8List bytes) async {
    try {
      _cacheDir ??= await getTemporaryDirectory();
      final key = p.basename(path).hashCode;
      final file = File(p.join(_cacheDir!.path, 'art_$key.jpg'));
      if (!file.existsSync()) await file.writeAsBytes(bytes);
      return Uri.file(file.path);
    } catch (e) {
      debugPrint('MetadataService._cacheArt failed: $e');
      return null;
    }
  }
}
