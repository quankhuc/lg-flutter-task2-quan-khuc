// Tests for the ConnectionProvider state machine. Uses hand-rolled fakes
// for LGConnectionInterface and FlutterSecureStorage (no mockito codegen
// needed at this size). Covers connect success/failure, auto-reconnect,
// verb-wrapper delegation, and config persistence.
//
// The Fake pattern (vs Mock): a Fake is a real implementation of the
// interface that records what happened in a controllable way. Easier to
// reason about than a generated mock and no codegen step.
//
// Run with: flutter test test/connection_provider_test.dart

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lg_flutter_task2/connections/lg_connection_interface.dart';
import 'package:lg_flutter_task2/models/lg_config.dart';
import 'package:lg_flutter_task2/providers/connection_provider.dart';
import 'package:lg_flutter_task2/utils/connection_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeLGConnection implements LGConnectionInterface {
  bool _connected = false;
  bool failNextConnect = false;
  LGConfig? lastConfig;
  String? lastPassword;
  final List<String> calls = [];

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect(LGConfig cfg, String password) async {
    calls.add('connect');
    if (failNextConnect) {
      failNextConnect = false;
      throw Exception('simulated auth failure');
    }
    lastConfig = cfg;
    lastPassword = password;
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    _connected = false;
  }

  @override
  Future<void> sendLogo(String kml) async => calls.add('sendLogo');
  @override
  Future<void> sendPyramidAndFly(String k, String l) async =>
      calls.add('sendPyramidAndFly');
  @override
  Future<void> flyTo(String l) async => calls.add('flyTo');
  @override
  Future<void> cleanLogos() async => calls.add('cleanLogos');
  @override
  Future<void> cleanKml() async => calls.add('cleanKml');
  @override
  Future<void> hardReset() async => calls.add('hardReset');
}

class FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  // Other methods left noImplemented — provider only uses read+write.
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late FakeLGConnection fakeConn;
  late SharedPreferences prefs;
  late FakeSecureStorage secure;
  late ConnectionLog log;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    fakeConn = FakeLGConnection();
    secure = FakeSecureStorage();
    log = ConnectionLog();
  });

  ConnectionProvider build() => ConnectionProvider(
        connection: fakeConn,
        prefs: prefs,
        secureStorage: secure,
        log: log,
      );

  group('connectWith', () {
    test('on success: persists config + password + isConnected=true', () async {
      final p = build();
      const cfg = LGConfig(host: 'h', port: 22, user: 'u', screens: 3);
      await p.connectWith(cfg, 'pw');

      expect(p.isConnected, isTrue);
      expect(prefs.getString('lg_host'), 'h');
      expect(prefs.getInt('lg_port'), 22);
      expect(prefs.getString('lg_user'), 'u');
      expect(await secure.read(key: 'lg_password'), 'pw');
      expect(p.lastError, isNull);
    });

    test(
      'on failure: rethrows + sets lastError + leaves isConnected=false',
      () async {
        fakeConn.failNextConnect = true;
        final p = build();
        const cfg = LGConfig(host: 'h', port: 22, user: 'u', screens: 3);

        await expectLater(() => p.connectWith(cfg, 'wrong'), throwsException);
        expect(p.isConnected, isFalse);
        expect(p.lastError, contains('simulated auth failure'));
      },
    );

    test('notifyListeners fires on both attempt and result', () async {
      final p = build();
      var notified = 0;
      p.addListener(() => notified++);

      await p.connectWith(
        const LGConfig(host: 'h', port: 22, user: 'u', screens: 3),
        'pw',
      );
      // Fires for: start (connecting=true) + finally (connecting=false).
      expect(notified, greaterThanOrEqualTo(2));
    });
  });

  group('tryAutoReconnect', () {
    test('returns false when no saved password', () async {
      final p = build();
      final ok = await p.tryAutoReconnect();
      expect(ok, isFalse);
      expect(fakeConn.calls, isEmpty);
    });

    test('returns true when saved password connects successfully', () async {
      // Pre-populate the secure storage as if a prior session saved.
      await secure.write(key: 'lg_password', value: 'pw');
      final p = build();
      final ok = await p.tryAutoReconnect();
      expect(ok, isTrue);
      expect(p.isConnected, isTrue);
    });

    test('returns false when saved password fails to authenticate', () async {
      await secure.write(key: 'lg_password', value: 'wrong');
      fakeConn.failNextConnect = true;
      final p = build();
      final ok = await p.tryAutoReconnect();
      expect(ok, isFalse);
      expect(p.isConnected, isFalse);
    });
  });

  group('verb wrappers', () {
    test('all 5 verbs delegate to underlying connection', () async {
      final p = build();
      await p.sendLogo('kml');
      await p.sendPyramidAndFly('kml', 'la');
      await p.flyTo('la');
      await p.cleanLogos();
      await p.cleanKml();
      expect(fakeConn.calls, [
        'sendLogo',
        'sendPyramidAndFly',
        'flyTo',
        'cleanLogos',
        'cleanKml',
      ]);
    });
  });

  group('config persistence on construction', () {
    test('loads from prefs when present', () async {
      SharedPreferences.setMockInitialValues({
        'lg_host': 'saved',
        'lg_port': 9999,
        'lg_user': 'savedUser',
        'lg_screens': 5,
      });
      prefs = await SharedPreferences.getInstance();
      final p = build();
      expect(p.config.host, 'saved');
      expect(p.config.port, 9999);
      expect(p.config.user, 'savedUser');
      expect(p.config.screens, 5);
    });

    test('uses defaults when prefs are empty', () async {
      final p = build();
      expect(p.config.host, '192.168.0.243');
      expect(p.config.port, 2201);
      expect(p.config.user, 'lg');
      expect(p.config.screens, 3);
    });
  });
}
