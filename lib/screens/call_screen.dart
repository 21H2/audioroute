import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../services/audio_router.dart';
import '../services/player_controller.dart';
import 'library_screen.dart';

/// The home screen — disguised as an ongoing phone call.
class CallScreen extends StatelessWidget {
  const CallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    final track = controller.current;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.surfaceContainerHighest,
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              children: [
                const SizedBox(height: 8),
                _CallHeader(),
                const SizedBox(height: 28),
                _Avatar(initial: track?.initial ?? '♪'),
                const SizedBox(height: 20),
                Text(
                  track?.title ?? 'No active call',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  controller.output == AudioOutput.earpiece
                      ? 'AudioRoute • earpiece'
                      : 'AudioRoute • speaker',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                if (track != null) const _Scrubber(),
                const Spacer(),
                _ControlGrid(),
                const SizedBox(height: 24),
                _EndCallButton(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        StreamBuilder<Duration>(
          stream: controller.positionStream,
          builder: (context, snapshot) {
            final pos = controller.current == null
                ? Duration.zero
                : (snapshot.data ?? Duration.zero);
            return Text(
              _formatDuration(pos),
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initial});
  final String initial;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.primaryContainer,
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.25),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 56,
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber();

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlayerController>();
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<Duration?>(
      stream: controller.durationStream,
      builder: (context, durSnap) {
        final duration = durSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: controller.positionStream,
          builder: (context, posSnap) {
            final position = posSnap.data ?? Duration.zero;
            final maxMs = duration.inMilliseconds.toDouble();
            final value = maxMs == 0
                ? 0.0
                : position.inMilliseconds.clamp(0, maxMs).toDouble();
            return Column(
              children: [
                Slider(
                  min: 0,
                  max: maxMs == 0 ? 1 : maxMs,
                  value: maxMs == 0 ? 0 : value,
                  onChanged: maxMs == 0
                      ? null
                      : (v) =>
                          controller.seek(Duration(milliseconds: v.round())),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(position),
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                      Text(_formatDuration(duration),
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ControlGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlayerController>();
    final speakerOn = controller.output == AudioOutput.speaker;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _CallButton(
              icon: controller.muted ? Icons.mic_off : Icons.mic,
              label: 'mute',
              active: controller.muted,
              onTap: controller.toggleMute,
            ),
            _CallButton(
              icon: speakerOn ? Icons.volume_up : Icons.volume_up_outlined,
              label: speakerOn ? 'speaker' : 'earpiece',
              active: speakerOn,
              onTap: controller.toggleOutput,
            ),
            _CallButton(
              icon: Icons.person_add_alt,
              label: 'library',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LibraryScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _CallButton(
              icon: Icons.replay_10,
              label: '-10s',
              onTap: () => controller.skip(const Duration(seconds: -10)),
            ),
            StreamBuilder<PlayerState>(
              stream: controller.playerStateStream,
              builder: (context, snapshot) {
                final playing = snapshot.data?.playing ?? false;
                return _CallButton(
                  icon: playing ? Icons.pause : Icons.play_arrow,
                  label: playing ? 'hold' : 'resume',
                  onTap: controller.togglePlay,
                );
              },
            ),
            _CallButton(
              icon: Icons.forward_10,
              label: '+10s',
              onTap: () => controller.skip(const Duration(seconds: 10)),
            ),
          ],
        ),
      ],
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = active ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = active ? scheme.onPrimary : scheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bg,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 68,
              height: 68,
              child: Icon(icon, color: fg, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _EndCallButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlayerController>();
    final hasCall = context.watch<PlayerController>().current != null;
    return Material(
      color: hasCall ? const Color(0xFFE5484D) : Colors.grey.shade400,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasCall ? controller.endCall : null,
        child: const SizedBox(
          width: 72,
          height: 72,
          child: Icon(Icons.call_end, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = d.inHours;
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
