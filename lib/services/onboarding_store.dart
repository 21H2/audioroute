import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persists whether the first-run onboarding has been seen, using a marker
/// file in the app support directory (no extra plugin needed).
class OnboardingStore {
  static const _fileName = 'onboarding_v1.done';

  Future<bool> isDone() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File(p.join(dir.path, _fileName)).existsSync();
    } catch (e) {
      debugPrint('OnboardingStore.isDone failed: $e');
      return false;
    }
  }

  Future<void> markDone() async {
    try {
      final dir = await getApplicationSupportDirectory();
      await File(p.join(dir.path, _fileName)).create(recursive: true);
    } catch (e) {
      debugPrint('OnboardingStore.markDone failed: $e');
    }
  }
}
