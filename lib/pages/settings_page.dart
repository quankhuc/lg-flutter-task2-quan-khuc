// Form with host/port/user/password fields, a QR-scan trailing icon on the
// Host field, and a Connect/Disconnect button. Fields are editable when
// disconnected and locked + greyed when connected — this signals that config
// can't be changed mid-session without disconnecting first. The Connect
// button keeps the same physical position and flips its label to Disconnect
// when connected so muscle memory works.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lg_config.dart';
import '../providers/connection_provider.dart';
import '../utils/qr_payload.dart';
import 'qr_scan_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _host;
  late TextEditingController _port;
  late TextEditingController _user;
  late TextEditingController _pw;
  bool _pwVisible = false;

  @override
  void initState() {
    super.initState();
    // Seed from current ConnectionProvider config. Provider was loaded with
    // defaults or persisted values at app startup.
    final cfg = context.read<ConnectionProvider>().config;
    _host = TextEditingController(text: cfg.host);
    _port = TextEditingController(text: cfg.port.toString());
    _user = TextEditingController(text: cfg.user);
    _pw = TextEditingController(); // password never pre-filled (security)
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _onConnect() async {
    if (!_formKey.currentState!.validate()) return;
    final cfg = LGConfig(
      host: _host.text.trim(),
      port: int.parse(_port.text.trim()),
      user: _user.text.trim(),
      screens: context.read<ConnectionProvider>().config.screens,
    );
    try {
      await context.read<ConnectionProvider>().connectWith(cfg, _pw.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to ${cfg.host}:${cfg.port}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      // Pop back to wherever the user came from (HomePage).
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connect failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _openQrScanner() async {
    final payload = await Navigator.of(
      context,
    ).push<QrPayload>(MaterialPageRoute(builder: (_) => const QrScanPage()));
    if (payload == null || !mounted) return;
    setState(() {
      _host.text = payload.config.host;
      _port.text = payload.config.port.toString();
      _user.text = payload.config.user;
      _pw.text = payload.password;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rig settings populated from QR — tap Connect'),
      ),
    );
  }

  Future<void> _onDisconnect() async {
    await context.read<ConnectionProvider>().disconnect();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Disconnected'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Watch (not read) so this rebuilds when connection state changes.
    final provider = context.watch<ConnectionProvider>();
    final connected = provider.isConnected;
    final connecting = provider.isConnecting;
    final locked = connected || connecting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: const BackButton(),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                'Connection',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: scheme.primary),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _host,
                enabled: !locked,
                decoration: InputDecoration(
                  labelText: 'Host',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: locked ? null : _openQrScanner,
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Host required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _port,
                enabled: !locked,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null || n <= 0 || n > 65535) {
                    return 'Port must be 1-65535';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _user,
                enabled: !locked,
                decoration: const InputDecoration(
                  labelText: 'User',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'User required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pw,
                enabled: !locked,
                obscureText: !_pwVisible,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _pwVisible ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _pwVisible = !_pwVisible),
                  ),
                ),
                validator: (v) {
                  if (connected) return null; // not needed when disconnecting
                  return (v == null || v.isEmpty) ? 'Password required' : null;
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: connecting
                    ? null
                    : (connected ? _onDisconnect : _onConnect),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: connecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(connected ? 'Disconnect' : 'Connect'),
              ),
              if (provider.lastError != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Last error: ${provider.lastError}',
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ],
              // -------- Debug section --------
              const SizedBox(height: 32),
              Text(
                'Debug',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Hard Reset kills Google Earth on the master VM and lets it auto-relaunch. Use only if ghost content from other LG apps (SatNOGS etc) lingers after Clean KMLs.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: !connected ? null : () => _onHardReset(provider),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Hard Reset (kills GE on master)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.error,
                  side: BorderSide(color: scheme.error),
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------- _onHardReset() --------
  // Confirm-then-execute. The pkill on master interrupts everyone watching the
  // rig — that's why this needs a confirmation dialog. Demo viewers will see
  // a black screen for ~10s on lg1 while autostart relaunches GE.
  Future<void> _onHardReset(ConnectionProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hard Reset master GE?'),
        content: const Text(
          'This kills Google Earth on lg1 (the master/center screen). '
          'Autostart relaunches it in ~10 seconds. The center screen will go '
          'black during the relaunch.\n\n'
          'Use this only if ghost content from other LG apps is stuck after '
          'Clean KMLs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await provider.hardReset();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hard reset issued — master GE relaunching'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hard reset failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}
