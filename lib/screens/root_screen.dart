import 'package:flutter/material.dart';

import '../services/onboarding_store.dart';
import 'call_screen.dart';
import 'onboarding_screen.dart';

/// Shows the call screen, and presents onboarding once on first launch.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final OnboardingStore _store = OnboardingStore();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOnboard());
  }

  Future<void> _maybeOnboard() async {
    if (await _store.isDone()) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const OnboardingScreen(),
      ),
    );
    await _store.markDone();
  }

  @override
  Widget build(BuildContext context) => const CallScreen();
}
