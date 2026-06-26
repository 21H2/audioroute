import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';

import 'screens/call_screen.dart';
import 'services/player_controller.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Enables the background foreground-service + media notification controls.
  // Guarded so a failure/hang here can never trap us on the splash screen —
  // foreground playback still works even if background init doesn't.
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.audioroute.playback',
      androidNotificationChannelName: 'AudioRoute playback',
      androidNotificationOngoing: true,
    ).timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('JustAudioBackground.init failed/timed out: $e');
  }
  runApp(const AudioRouteApp());
}

class AudioRouteApp extends StatefulWidget {
  const AudioRouteApp({super.key});

  @override
  State<AudioRouteApp> createState() => _AudioRouteAppState();
}

class _AudioRouteAppState extends State<AudioRouteApp> {
  final PlayerController _controller = PlayerController();

  @override
  void initState() {
    super.initState();
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PlayerController>.value(
      value: _controller,
      child: DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
          // Material You: use the wallpaper-derived palette on Android 12+,
          // otherwise fall back to a seeded scheme.
          final lightScheme = lightDynamic ??
              ColorScheme.fromSeed(seedColor: kSeedColor);
          final darkScheme = darkDynamic ??
              ColorScheme.fromSeed(
                seedColor: kSeedColor,
                brightness: Brightness.dark,
              );

          return MaterialApp(
            title: 'AudioRoute',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(lightScheme),
            darkTheme: buildTheme(darkScheme),
            themeMode: ThemeMode.system,
            home: const CallScreen(),
          );
        },
      ),
    );
  }
}
