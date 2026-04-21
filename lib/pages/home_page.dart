// The demo screen. Three stacked filled action buttons (Send LG Logo, Send
// Pyramid + Fly, Fly Home), a Cleanup divider, then two outlined buttons
// (Clean Logos, Reset) side by side. A status badge lives in the AppBar and
// Settings/Log entry points sit in the bottomNavigationBar.
//
// Reads all connection state from ConnectionProvider via Selector/Consumer
// so the button row rebuilds only when isConnected changes, not on every
// new log entry. Each button has its own _busyAction string instead of a
// global bool so only the in-flight button shows its spinner.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../theme/app_theme.dart';
import '../utils/connection_log.dart';
import '../utils/kml/kml_makers.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const double _homeLat = 40.4168;
  static const double _homeLng = -3.7038;
  static const String _logoUrl =
      'https://raw.githubusercontent.com/lucisays/imagen/main/LGMasterWebAppLogo.png';

  bool _busy = false;
  String? _busyAction;

  Future<void> _runAction(
    String name,
    Future<void> Function(ConnectionProvider) action,
  ) async {
    final provider = context.read<ConnectionProvider>();
    if (!provider.isConnected) {
      _showError('Not connected — open Settings to connect');
      return;
    }
    setState(() {
      _busy = true;
      _busyAction = name;
    });
    try {
      await action(provider);
      if (mounted) _showSuccess('$name done');
    } catch (e) {
      if (mounted) _showError('$name failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyAction = null;
        });
      }
    }
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _onSendLogo() => _runAction(
        'Send LG Logo',
        (p) => p.sendLogo(buildLogoKml(imageUrl: _logoUrl)),
      );

  Future<void> _onSendPyramidAndFly() => _runAction(
        'Send Pyramid + Fly',
        (p) => p.sendPyramidAndFly(
          buildPyramidKml(centerLat: _homeLat, centerLng: _homeLng),
          buildLookAtXml(lat: _homeLat, lng: _homeLng),
        ),
      );

  Future<void> _onFlyHome() => _runAction(
        'Fly Home',
        (p) => p.flyTo(buildLookAtXml(lat: _homeLat, lng: _homeLng)),
      );

  Future<void> _onCleanLogos() =>
      _runAction('Clean Logos', (p) => p.cleanLogos());

  Future<void> _onCleanKml() => _runAction('Reset', (p) async {
        await p.cleanKml();
        // World-level view — GE's viewRefreshMode=onStop only refreshes on a
        // meaningful camera move, so we fly somewhere clearly different from
        // any demo flytoview. Also visually matches "initial state".
        await p.flyTo(
          buildLookAtXml(
            lat: 0,
            lng: 0,
            range: 15000000,
            tilt: 0,
            heading: 0,
          ),
        );
      });

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        actions: [
          // Consumer scope here means the badge rebuilds when state changes
          // WITHOUT rebuilding the rest of the page. Performance + clarity win.
          Consumer<ConnectionProvider>(
            builder: (_, provider, __) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _StatusBadge(
                connected: provider.isConnected,
                busy: provider.isConnecting,
                host: provider.config.host,
                port: provider.config.port,
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            // We use a Selector so these buttons rebuild only when isConnected
            // changes, not on every log-entry change.
            Selector<ConnectionProvider, bool>(
              selector: (_, p) => p.isConnected,
              builder: (_, connected, __) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PrimaryActionButton(
                    icon: Icons.image_outlined,
                    label: 'Send LG Logo',
                    busy: _busyAction == 'Send LG Logo',
                    disabled: _busy || !connected,
                    onPressed: _onSendLogo,
                  ),
                  const SizedBox(height: 12),
                  _PrimaryActionButton(
                    icon: Icons.change_history,
                    label: 'Send Pyramid + Fly',
                    busy: _busyAction == 'Send Pyramid + Fly',
                    disabled: _busy || !connected,
                    onPressed: _onSendPyramidAndFly,
                  ),
                  const SizedBox(height: 12),
                  _PrimaryActionButton(
                    icon: Icons.public,
                    label: 'Fly Home',
                    busy: _busyAction == 'Fly Home',
                    disabled: _busy || !connected,
                    onPressed: _onFlyHome,
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(child: Divider(color: scheme.outlineVariant)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Cleanup',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      Expanded(child: Divider(color: scheme.outlineVariant)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              (_busy || !connected) ? null : _onCleanLogos,
                          icon: _busyAction == 'Clean Logos'
                              ? const _SmallSpinner()
                              : const Icon(Icons.layers_clear_outlined),
                          label: const Text('Clean Logos'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (_busy || !connected) ? null : _onCleanKml,
                          icon: _busyAction == 'Reset'
                              ? const _SmallSpinner()
                              : const Icon(Icons.refresh),
                          label: const Text('Reset'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Settings'),
              ),
              Consumer<ConnectionProvider>(
                builder: (_, p, __) => TextButton.icon(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (_) => _LogSheet(provider: p),
                    );
                  },
                  icon: const Icon(Icons.list_alt_outlined),
                  label: Text('Log (${p.log.entries.length})'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool busy;
  final bool disabled;
  final VoidCallback onPressed;

  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.disabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: disabled ? null : onPressed,
      icon: busy ? const _SmallSpinner() : Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _SmallSpinner extends StatelessWidget {
  const _SmallSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool connected;
  final bool busy;
  final String host;
  final int port;

  const _StatusBadge({
    required this.connected,
    required this.busy,
    required this.host,
    required this.port,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color =
        busy ? scheme.tertiary : (connected ? scheme.primary : scheme.error);
    final label =
        busy ? 'Connecting...' : (connected ? '$host:$port' : 'Disconnected');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _LogSheet extends StatelessWidget {
  final ConnectionProvider provider;
  const _LogSheet({required this.provider});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.2,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scroll) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Connection Log',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: () => provider.log.clear(),
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListenableBuilder(
                listenable: provider.log,
                builder: (_, __) {
                  final entries = provider.log.entries;
                  if (entries.isEmpty) {
                    return const Center(
                      child: Text('No events yet. Connect to start logging.'),
                    );
                  }
                  return ListView.builder(
                    controller: scroll,
                    itemCount: entries.length,
                    itemBuilder: (_, i) => _LogRow(entry: entries[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single colored log row: timestamp (muted) + severity (colored, bold) +
/// message (default foreground). Monospace throughout. Multi-modal per
/// PatternFly/Red Hat/Carbon: color + severity word + fixed position.
class _LogRow extends StatelessWidget {
  final LogEntry entry;

  const _LogRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.6);
    final severityColor = AppTheme.logColor(entry.severity, brightness);

    final h = entry.timestamp.hour.toString().padLeft(2, '0');
    final m = entry.timestamp.minute.toString().padLeft(2, '0');
    final s = entry.timestamp.second.toString().padLeft(2, '0');

    // Error rows get a subtle background tint so failures catch the eye
    // when scrolling. errorContainer at 8% alpha stays readable.
    final isError = entry.severity == LogSeverity.error;
    final bg = isError
        ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.14)
        : null;

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$h:$m:$s',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: muted,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48, // fits DEBUG/ERROR (5 chars) + breathing room
            child: Text(
              entry.severity.name.toUpperCase(),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: severityColor,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
