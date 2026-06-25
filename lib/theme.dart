import 'package:flutter/material.dart';

/// Fallback seed color used when the device can't supply a Material You
/// (dynamic) palette — e.g. Android < 12 or desktop/web.
const Color kSeedColor = Color(0xFF6750A4);

ThemeData buildTheme(ColorScheme scheme) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    sliderTheme: SliderThemeData(
      trackHeight: 3,
      overlayShape: SliderComponentShape.noOverlay,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
  );
}
