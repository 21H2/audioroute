/// A single imported audio file the user can "call".
class Track {
  const Track({required this.title, required this.path, this.artist});

  /// Display name (derived from the file name on import).
  final String title;

  /// Absolute path to the local audio file.
  final String path;

  /// Optional artist/subtitle. Shown as the "call type" line.
  final String? artist;

  /// First letter used for the avatar fallback.
  String get initial =>
      title.trim().isEmpty ? '?' : title.trim().substring(0, 1).toUpperCase();
}
