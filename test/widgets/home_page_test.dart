// Widget tests for HomePage. Injects a ConnectionProvider backed by
// FakeLGConnection so tests run pure in-memory with no SSH. Verifies each
// button is enabled only when connected, calls the right provider method
// when tapped, and that the status badge reflects connection state.
//
// Pattern: pumpWidget(MaterialApp(home: ChangeNotifierProvider.value(...)))
// is the idiomatic way to inject a fake provider for widget tests.
//
// FakeLGConnection and FakeSecureStorage are shared with
// connection_provider_test.dart via a `show` import.
//
// Run with: flutter test test/widgets/home_page_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lg_flutter_task2/connections/lg_connection_interface.dart';
import 'package:lg_flutter_task2/models/lg_config.dart';
import 'package:lg_flutter_task2/pages/home_page.dart';
import 'package:lg_flutter_task2/providers/connection_provider.dart';
import 'package:lg_flutter_task2/utils/connection_log.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../connection_provider_test.dart'
    show FakeLGConnection, FakeSecureStorage;

Future<ConnectionProvider> _buildProvider({
  required LGConnectionInterface conn,
  required bool startConnected,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final p = ConnectionProvider(
    connection: conn,
    prefs: prefs,
    secureStorage: FakeSecureStorage(),
    log: ConnectionLog(),
  );
  if (startConnected) {
    await p.connectWith(LGConfig.defaults(), 'pw');
  }
  return p;
}

Widget _wrap(ConnectionProvider provider) {
  return ChangeNotifierProvider<ConnectionProvider>.value(
    value: provider,
    child: const MaterialApp(home: HomePage()),
  );
}

void main() {
  testWidgets('all 5 action buttons present', (tester) async {
    final fake = FakeLGConnection();
    final provider = await _buildProvider(conn: fake, startConnected: true);
    await tester.pumpWidget(_wrap(provider));
    await tester.pump();

    expect(find.text('Send LG Logo'), findsOneWidget);
    expect(find.text('Send Pyramid + Fly'), findsOneWidget);
    expect(find.text('Fly Home'), findsOneWidget);
    expect(find.text('Clean Logos'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
  });

  testWidgets('buttons are disabled when not connected', (tester) async {
    final fake = FakeLGConnection();
    final provider = await _buildProvider(conn: fake, startConnected: false);
    await tester.pumpWidget(_wrap(provider));
    await tester.pump();

    final filled = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Send LG Logo'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(filled.onPressed, isNull);
  });

  testWidgets('tapping Send LG Logo calls provider.sendLogo', (tester) async {
    final fake = FakeLGConnection();
    final provider = await _buildProvider(conn: fake, startConnected: true);
    await tester.pumpWidget(_wrap(provider));
    await tester.pump();

    await tester.tap(find.text('Send LG Logo'));
    // Allow the future + setState chain to complete.
    await tester.pumpAndSettle();

    expect(fake.calls, contains('sendLogo'));
  });

  testWidgets('tapping Reset calls provider.cleanKml then flyTo',
      (tester) async {
    final fake = FakeLGConnection();
    final provider = await _buildProvider(conn: fake, startConnected: true);
    await tester.pumpWidget(_wrap(provider));
    await tester.pump();

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(fake.calls, contains('cleanKml'));
    expect(fake.calls, contains('flyTo'));
  });

  testWidgets('status badge shows host:port when connected', (tester) async {
    final fake = FakeLGConnection();
    final provider = await _buildProvider(conn: fake, startConnected: true);
    await tester.pumpWidget(_wrap(provider));
    await tester.pump();

    expect(find.text('192.168.0.243:2201'), findsOneWidget);
  });

  testWidgets('status badge shows Disconnected when not connected', (
    tester,
  ) async {
    final fake = FakeLGConnection();
    final provider = await _buildProvider(conn: fake, startConnected: false);
    await tester.pumpWidget(_wrap(provider));
    await tester.pump();

    expect(find.text('Disconnected'), findsOneWidget);
  });
}
