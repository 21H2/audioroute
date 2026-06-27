import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/audio_router.dart';
import '../services/player_controller.dart';
import 'library_screen.dart';

/// The home screen — disguised as an ongoing phone call, styled after iOS.
class CallScreen extends StatelessWidget {
  const CallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlayerController>();
    final track = controller.current;
    final palette = _CallPalette.of(context, hasArt: track?.hasArtwork ?? false);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _Backdrop(track: track, palette: palette),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  _CallerName(track: track, palette: palette),
                  const SizedBox(height: 8),
                  _StatusLine(track: track, palette: palette),
                  const Spacer(),
                  _Artwork(track: track, palette: palette),
                  const Spacer(),
                  if (track != null) _Scrubber(palette: palette),
                  const SizedBox(height: 20),
                  _ControlGrid(palette: palette),
                  const SizedBox(height: 28),
                  _EndCallButton(active: track != null),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Foreground colors adapt: white over album art, theme colors otherwise.
class _CallPalette {
  const _CallPalette({
    required this.fg,
    required this.muted,
    required this.glass,
    required this.glassActive,
    required this.glassActiveIcon,
  });

  final Color fg;
  final Color muted;
  final Color glass;
  final Color glassActive;
  final Color glassActiveIcon;

  factory _CallPalette.of(BuildContext context, {required bool hasArt}) {
    final scheme = Theme.of(context).colorScheme;
    if (hasArt) {
      return _CallPalette(
        fg: Colors.white,
        muted: Colors.white70,
        glass: Colors.white.withValues(alpha: 0.20),
        glassActive: Colors.white,
        glassActiveIcon: Colors.black,
      );
    }
    return _CallPalette(
      fg: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      glass: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
      glassActive: scheme.primary,
      glassActiveIcon: scheme.onPrimary,
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.track, required this.palette});
  final Track? track;
  final _CallPalette palette;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (track?.artwork != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 38, sigmaY: 38),
            child: Image.memory(track!.artwork!, fit: BoxFit.cover),
          ),
          // Darkening scrim for legibility.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.black.withValues(alpha: 0.65),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [scheme.surfaceContainerHighest, scheme.surface],
        ),
      ),
    );
  }
}

class _CallerName extends StatelessWidget {
  const _CallerName({required this.track, required this.palette});
  final Track? track;
  final _CallPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      track?.title ?? 'No active call',
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: palette.fg,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.track, required this.palette});
  final Track? track;
  final _CallPalette palette;

  @override
  Widget build(BuildContext context) {
    // Copy to a local so Dart can promote it to non-null after the check
    // (public fields aren't promotable).
    final track = this.track;
    final controller = context.watch<PlayerController>();
    final route = controller.output == AudioOutput.earpiece
        ? 'earpiece'
        : 'speaker';

    if (track == null) {
      return Text('AudioRoute', style: TextStyle(color: palette.muted));
    }

    return StreamBuilder<Duration>(
      stream: controller.positionStream,
      builder: (context, snapshot) {
        final pos = snapshot.data ?? Duration.zero;
        final subtitle = track.artist == null
            ? route
            : '${track.artist} • $route';
        return Column(
          children: [
            Text(
              _formatDuration(pos),
              style: TextStyle(
                color: palette.fg,
                fontSize: 17,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.muted, fontSize: 13),
            ),
          ],
        );
      },
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.track, required this.palette});
  final Track? track;
  final _CallPalette palette;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const size = 232.0;
    final shadow = [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.35),
        blurRadius: 50,
        spreadRadius: 2,
        offset: const Offset(0, 12),
      ),
    ];

    if (track?.artwork != null) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: shadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: Image.memory(
            track!.artwork!,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.primaryContainer,
        boxShadow: shadow,
      ),
      alignment: Alignment.center,
      child: Text(
        track?.initial ?? '♪',
        style: TextStyle(
          fontSize: 84,
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber({required this.palette});
  final _CallPalette palette;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlayerController>();

    return StreamBuilder<Duration?>(
      stream: controller.durationStream,
      builder: (context, durSnap) {
        final duration = durSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: controller.positionStream,
          builder: (context, posSnap) {
            final position = posSnap.data ?? Duration.zero;
            final maxMs = duration.inMilliseconds.toDouble();
            final value =
                maxMs == 0 ? 0.0 : position.inMilliseconds.clamp(0, maxMs).toDouble();
            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: palette.fg,
                    inactiveTrackColor: palette.fg.withValues(alpha: 0.25),
                    thumbColor: palette.fg,
                  ),
                  child: Slider(
                    min: 0,
                    max: maxMs == 0 ? 1 : maxMs,
                    value: maxMs == 0 ? 0 : value,
                    onChanged: maxMs == 0
                        ? null
                        : (v) =>
                            controller.seek(Duration(milliseconds: v.round())),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(position),
                          style: TextStyle(fontSize: 12, color: palette.muted)),
                      Text(_formatDuration(duration),
                          style: TextStyle(fontSize: 12, color: palette.muted)),
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
  const _ControlGrid({required this.palette});
  final _CallPalette palette;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlayerController>();
    final speakerOn = controller.output == AudioOutput.speaker;

    return Column(
      children: [
        _row([
          _GlassButton(
            palette: palette,
            icon: controller.muted ? Icons.mic_off : Icons.mic,
            label: controller.muted ? 'unmute' : 'mute',
            active: controller.muted,
            onTap: controller.toggleMute,
          ),
          _GlassButton(
            palette: palette,
            icon: speakerOn ? Icons.volume_up : Icons.hearing,
            label: speakerOn ? 'speaker' : 'earpiece',
            active: speakerOn,
            onTap: controller.toggleOutput,
          ),
          _GlassButton(
            palette: palette,
            icon: Icons.library_music,
            label: 'library',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LibraryScreen()),
            ),
          ),
        ]),
        const SizedBox(height: 26),
        _row([
          _GlassButton(
            palette: palette,
            icon: Icons.skip_previous,
            label: 'previous',
            onTap: controller.previous,
          ),
          StreamBuilder<PlayerState>(
            stream: controller.playerStateStream,
            builder: (context, snapshot) {
              final playing = snapshot.data?.playing ?? false;
              return _GlassButton(
                palette: palette,
                icon: playing ? Icons.pause : Icons.play_arrow,
                label: playing ? 'hold' : 'resume',
                onTap: controller.togglePlay,
              );
            },
          ),
          _GlassButton(
            palette: palette,
            icon: Icons.skip_next,
            label: 'next',
            onTap: controller.next,
          ),
        ]),
      ],
    );
  }

  /// Three equal columns, each centering its button — matches the dialer grid.
  Widget _row(List<Widget> items) => Row(
        children: [
          for (final item in items) Expanded(child: Center(child: item)),
        ],
      );
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final _CallPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final fill = active ? palette.glassActive : palette.glass;
    final iconColor = active ? palette.glassActiveIcon : palette.fg;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipOval(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Material(
              color: fill,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onTap,
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Icon(icon, color: iconColor, size: 26),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(color: palette.muted, fontSize: 12.5),
        ),
      ],
    );
  }
}

class _EndCallButton extends StatelessWidget {
  const _EndCallButton({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlayerController>();
    return Material(
      color: active ? const Color(0xFFE5484D) : const Color(0x66888888),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: active ? controller.endCall : null,
        child: const SizedBox(
          width: 64,
          height: 64,
          child: Icon(Icons.call_end, color: Colors.white, size: 28),
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
