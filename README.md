# AudioRoute

Listen to your own music through the phone's **front earpiece** instead of the
loudspeaker — so it looks like you're on a call, but you're actually playing a
track. Built with **Flutter**, **Material You** dynamic theming, and a custom
native audio-routing channel.

## Why Flutter (vs. React Native)

- **Audio routing** is the core feature and needs native code either way.
  Flutter's `just_audio` exposes Android `AudioAttributes` directly
  (`setAndroidAudioAttributes`), and `audio_session` wraps focus/mode cleanly —
  far less native glue than RN's fragmented audio packages.
- **Material You** is first-class via `dynamic_color` (real wallpaper-derived
  palette on Android 12+); RN relies on lagging third-party bridges.
- One language for both UI and the platform channel.

## How the "music on the earpiece" trick works

Two halves, both required:

1. **Native (`MainActivity.kt`)** puts the device into
   `MODE_IN_COMMUNICATION` and selects the **built-in earpiece** as the active
   communication device (`setCommunicationDevice` on API 31+, the
   `isSpeakerphoneOn` flag on older devices).
2. **Player (`PlayerController._applyAttributes`)** tags playback with
   `AndroidAudioUsage.voiceCommunication` so the OS routes it like call audio.

Toggle to **Speaker** and it flips back to `media` usage + `MODE_NORMAL` —
ordinary system audio out the loudspeaker.

## Features

- iOS-style **call screen**: album-art backdrop (blurred), crisp artwork
  centerpiece, live call timer, frosted-glass mute / speaker / library /
  rewind / play-hold / forward controls, and a red **End Call** button.
- **Import** individual audio files *or a whole folder* (`file_picker` +
  all-files access) into a "contacts" library.
- **Playlist transport**: previous / play-pause / next with auto-advance, and
  Spotify-style **lock-screen + notification controls** (`just_audio_background`).
- **Album art + artist** read from each file's embedded tags
  (`audio_metadata_reader`, pure Dart) and shown both in-app and on the media
  notification.
- **Background playback** with lock-screen / notification controls
  (`just_audio_background`).
- **Proximity screen-off**: while playing through the earpiece, holding the
  phone to your ear blanks the screen — just like a real call.
- One-tap **earpiece ↔ speaker** routing.
- Material You dynamic color (falls back to a seeded purple scheme).

## Project layout

```
lib/
  main.dart                     # app + DynamicColorBuilder + Provider
  theme.dart                    # Material 3 theme from a ColorScheme
  models/track.dart
  services/audio_router.dart    # method channel + audio_session
  services/player_controller.dart  # state, just_audio, import
  screens/call_screen.dart      # the disguised-call home screen
  screens/library_screen.dart   # imported tracks
android/app/src/main/kotlin/com/example/audioroute/MainActivity.kt
```

## Build & run

Requires the Flutter SDK (3.24+) and an Android toolchain.

```bash
cd audioroute
flutter pub get
flutter run            # on a connected device or emulator
```

### One-time note about the Gradle wrapper

This scaffold ships the Gradle config but **not** the binary
`gradle-wrapper.jar` (it can't be authored as text). If `flutter run` complains
that the wrapper is missing, regenerate the Android tooling without touching the
app code:

```bash
# Generates the Gradle wrapper + any missing platform files.
# It will NOT overwrite lib/, pubspec.yaml, or your customized
# MainActivity.kt / AndroidManifest.xml.
flutter create --platforms=android .
```

Then re-run `flutter pub get && flutter run`.

> Tip: test on a **physical phone**. Emulators usually don't model a real
> earpiece, so the routing difference is hard to hear.

## Get it on your phone (no toolchain needed)

Every push auto-bumps the version and publishes a **GitHub Release** with an
installable APK:

1. Go to the repo's **Releases** page.
2. On your Android phone, open the latest release and download
   `audioroute-<version>.apk`.
3. Tap the downloaded file and confirm — allow "install unknown apps" for your
   browser if prompted.

The release APK is a universal (all-ABI) build, so it installs on any phone.
It's debug-signed: great for sideloading, not yet ready for Play Store upload.

## Notes & next steps

- `minSdk` is **26** (lets the launcher icon stay pure-XML; routing needs 31+
  for the modern API, with a legacy fallback below that).
- Playback **defaults to the loudspeaker** so it's audible immediately; tap the
  earpiece button for the "on a call" effect. The earpiece is intentionally
  quiet (it uses the in-call volume stream) — turn the volume up while playing
  and hold the phone to your ear. Earpiece routing is device-dependent.
- **Folder import** needs "All files access" on Android 11+; the app will
  prompt for it the first time a folder scan is blocked. (This permission is
  fine for sideloading but would need justification for a Play Store listing.)
- Ideas to extend: a swipe-up "now playing" queue, playlist persistence across
  launches, and a real signing keystore for Play Store uploads.
