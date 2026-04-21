// SplashPage: shown for 800ms-2000ms while we attempt to auto-reconnect to
// the saved rig. Routes to HomePage either way — if reconnect failed,
// HomePage shows the disconnected state and the user taps Settings.
//
// Layout:
//   - Center: LG icon + "Liquid Galaxy" + "GSoC 2026 — Task 2" subtitle.
//   - Spinner under the headline only while auto-reconnect runs.
//   - Bottom: row of partner logo placeholders at 60% opacity.
//   - Min 800ms display so the brand registers; max 2000ms outer cap on
//     reconnect so the splash never hangs on a bad rig.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import 'home_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  bool _reconnectFinished = false;
  bool _minTimeElapsed = false;

  @override
  void initState() {
    super.initState();
    _startSequence();
  }

  Future<void> _startSequence() async {
    // 1. Kick off the minimum-display-time timer so users always SEE the splash
    //    even on instant reconnects.
    Timer(const Duration(milliseconds: 800), () {
      _minTimeElapsed = true;
      _maybeNavigate();
    });

    // 2. Try to auto-reconnect, with a hard 2-second outer cap so the splash
    //    never hangs forever if something hangs.
    final provider = context.read<ConnectionProvider>();
    try {
      await provider.tryAutoReconnect().timeout(
            const Duration(seconds: 2),
            onTimeout: () => false,
          );
    } catch (_) {
      // tryAutoReconnect already swallows; .timeout might still throw.
      // Either way, we proceed to home — failure surfaces in the badge.
    }
    _reconnectFinished = true;
    _maybeNavigate();
  }

  void _maybeNavigate() {
    if (!mounted) return;
    if (_reconnectFinished && _minTimeElapsed) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Stack(
            children: [
              // Brand block truly centered on the screen.
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.public, size: 96, color: scheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Liquid Galaxy',
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'GSoC 2026 — Task 2',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: _reconnectFinished
                          ? const SizedBox.shrink()
                          : CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary,
                            ),
                    ),
                  ],
                ),
              ),
              // Partner logos pinned to bottom, horizontally centered.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Opacity(
                  opacity: 0.6,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 24,
                    children: const [
                      _PartnerLogoPlaceholder(label: 'GSoC'),
                      _PartnerLogoPlaceholder(label: 'LG-Lab'),
                      _PartnerLogoPlaceholder(label: 'Lleida Labs'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartnerLogoPlaceholder extends StatelessWidget {
  final String label;
  const _PartnerLogoPlaceholder({required this.label});
  // TODO: replace with Image.asset('assets/images/<partner>_logo.png') once
  // partner logos are checked in. For now a labeled badge keeps the layout.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
