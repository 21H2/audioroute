import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/player_controller.dart';

/// The "contacts" list — imported audio files you can call.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlayerController>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        bottom: controller.busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'Import folder',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: controller.importFolder,
          ),
          IconButton(
            tooltip: 'Import files',
            icon: const Icon(Icons.library_add_outlined),
            onPressed: controller.importTracks,
          ),
        ],
      ),
      body: controller.tracks.isEmpty
          ? _EmptyState(
              onImportFiles: controller.importTracks,
              onImportFolder: controller.importFolder,
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: controller.tracks.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 88),
              itemBuilder: (context, index) {
                final track = controller.tracks[index];
                final isCurrent = controller.current?.path == track.path;
                return ListTile(
                  leading: _Thumb(track: track),
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    isCurrent
                        ? 'On call now'
                        : (track.artist ?? 'Tap to call'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Icon(
                    isCurrent ? Icons.graphic_eq : Icons.call_outlined,
                    color: isCurrent ? scheme.primary : null,
                  ),
                  onTap: () async {
                    await controller.play(track);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                );
              },
            ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (track.artwork != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          track.artwork!,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
        ),
      );
    }
    return CircleAvatar(
      radius: 26,
      backgroundColor: scheme.primaryContainer,
      child: Text(
        track.initial,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onImportFiles, required this.onImportFolder});

  final VoidCallback onImportFiles;
  final VoidCallback onImportFolder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note_outlined, size: 72, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              'No audio yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Add songs or a whole folder, then place a "call" to listen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onImportFiles,
              icon: const Icon(Icons.library_add_outlined),
              label: const Text('Import files'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onImportFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Import folder'),
            ),
          ],
        ),
      ),
    );
  }
}
