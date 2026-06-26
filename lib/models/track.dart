import 'dart:typed_data';

/// A single imported audio file the user can "call".
///
/// Core fields ([title], [path]) are set on import; the metadata fields
/// ([artist], [artwork], [artUri]) are filled in asynchronously afterwards
/// by [MetadataService] when a match is found in the device media library.
class Track {
  Track({required this.title, required this.path, this.artist});

  /// Display name (derived from the file name on import).
  final String title;

  /// Absolute path to the local audio file.
  final String path;

  /// Artist/subtitle, if known.
  String? artist;

  /// Raw album-art bytes for in-app display (`Image.memory`).
  Uint8List? artwork;

  /// File URI of cached art, handed to the media notification.
  Uri? artUri;

  bool get hasArtwork => artwork != null;

  /// First letter used for the avatar fallback.
  String get initial =>
      title.trim().isEmpty ? '?' : title.trim().substring(0, 1).toUpperCase();
}
