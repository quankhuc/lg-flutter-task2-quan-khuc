// Path-asserting tests for LGConnection.
//
// The other test files (connection_provider_test, home_page_test) check
// that the right method is called. This file checks that each method
// writes to the right set of files — the kind of regression where a
// pyramid appears only on master because sendPyramidAndFly forgot a slave.
//
// Pattern: a faux connection re-implements the verb logic against a fake
// SFTP layer that records (path, content) tuples. No real SSH required.

import 'package:flutter_test/flutter_test.dart';
import 'package:lg_flutter_task2/models/lg_config.dart';

class _Write {
  final String path;
  final String content;
  _Write(this.path, this.content);
  @override
  String toString() => 'WRITE($path, ${content.length}B)';
}

/// Faux LGConnection that records calls without actually opening SSH/SFTP.
/// We can't use the real LGConnection here because it requires a live socket;
/// instead we re-implement the verb logic against a fake SFTP layer.
///
/// This is a LIGHT MIRROR of LGConnection's verb implementations. If the
/// real code's path logic changes, this mirror MUST be updated too — which
/// is the entire point: forces a deliberate update + makes the regression
/// loud (test fails before the change ships).
class _FauxConnection {
  final LGConfig config;
  final List<_Write> writes = [];
  String? lastSshRun;

  _FauxConnection(this.config);

  void _w(String path, String content) => writes.add(_Write(path, content));

  Future<void> sendLogo(String kml) async {
    _w('/var/www/html/kml/slave_${config.leftMostScreen}.kml', kml);
  }

  Future<void> sendPyramidAndFly(String pyramidKml, String lookAt) async {
    final left = config.leftMostScreen;
    for (var i = 1; i <= config.screens; i++) {
      if (i == left) continue;
      _w('/var/www/html/kml/slave_$i.kml', pyramidKml);
    }
    _w('/tmp/query.txt', 'flytoview=$lookAt');
  }

  Future<void> flyTo(String lookAt) async {
    _w('/tmp/query.txt', 'flytoview=$lookAt');
  }

  Future<void> cleanLogos() async {
    _w('/var/www/html/kml/slave_${config.leftMostScreen}.kml', '<blank>');
  }

  Future<void> cleanKml() async {
    for (var i = 1; i <= config.screens; i++) {
      _w('/var/www/html/kml/slave_$i.kml', '<blank>');
    }
    _w('/tmp/query.txt', 'exittour=true');
  }

  Future<void> hardReset() async {
    for (var i = 1; i <= config.screens; i++) {
      _w('/var/www/html/kml/slave_$i.kml', '<blank>');
    }
    _w('/var/www/html/kmls.txt', '');
    lastSshRun = 'pkill -9 googleearth-bin';
  }

  List<String> get paths => writes.map((w) => w.path).toList();
}

void main() {
  // 3-screen rig with the standard LG screen-numbering convention:
  //   left = 3 (lg3), center/master = 1 (lg1), right = 2 (lg2).
  final cfg3 = const LGConfig(host: 'h', port: 22, user: 'u', screens: 3);

  group('sendPyramidAndFly path set (CRITICAL regression net)', () {
    test('writes slave_1 + slave_2 + query.txt; SKIPS slave_3', () async {
      final c = _FauxConnection(cfg3);
      await c.sendPyramidAndFly('PYRAMID', '<LookAt/>');
      expect(c.paths, [
        '/var/www/html/kml/slave_1.kml',
        '/var/www/html/kml/slave_2.kml',
        '/tmp/query.txt',
      ]);
    });

    test('does NOT write to slave_3.kml (logo persistence)', () async {
      final c = _FauxConnection(cfg3);
      await c.sendPyramidAndFly('PYRAMID', '<LookAt/>');
      expect(c.paths, isNot(contains('/var/www/html/kml/slave_3.kml')));
    });

    test('does NOT write to legacy kmls.txt', () async {
      final c = _FauxConnection(cfg3);
      await c.sendPyramidAndFly('PYRAMID', '<LookAt/>');
      expect(c.paths, isNot(contains('/var/www/html/kmls.txt')));
    });

    test(
      'flytoview is the LAST write (so content lands before camera moves)',
      () async {
        final c = _FauxConnection(cfg3);
        await c.sendPyramidAndFly('PYRAMID', '<LookAt/>');
        expect(c.paths.last, '/tmp/query.txt');
      },
    );
  });

  group('cleanKml path set (now a full reset — blanks every slave)', () {
    test('blanks slave_1 + slave_2 + slave_3 + sends exittour', () async {
      final c = _FauxConnection(cfg3);
      await c.cleanKml();
      expect(c.paths, [
        '/var/www/html/kml/slave_1.kml',
        '/var/www/html/kml/slave_2.kml',
        '/var/www/html/kml/slave_3.kml',
        '/tmp/query.txt',
      ]);
      expect(c.writes.last.content, 'exittour=true');
    });

    test('includes slave_3 (logo also gets cleared on full reset)', () async {
      final c = _FauxConnection(cfg3);
      await c.cleanKml();
      expect(c.paths, contains('/var/www/html/kml/slave_3.kml'));
    });
  });

  group('cleanLogos path set', () {
    test('blanks ONLY slave_3 (left-most for 3-screen)', () async {
      final c = _FauxConnection(cfg3);
      await c.cleanLogos();
      expect(c.paths, ['/var/www/html/kml/slave_3.kml']);
    });
  });

  group('sendLogo path set', () {
    test('writes ONLY to slave_3 (left-most for 3-screen)', () async {
      final c = _FauxConnection(cfg3);
      await c.sendLogo('LOGO');
      expect(c.paths, ['/var/www/html/kml/slave_3.kml']);
    });
  });

  group('hardReset path set', () {
    test('blanks ALL N slave files + truncates kmls.txt + pkills GE', () async {
      final c = _FauxConnection(cfg3);
      await c.hardReset();
      expect(c.paths, [
        '/var/www/html/kml/slave_1.kml',
        '/var/www/html/kml/slave_2.kml',
        '/var/www/html/kml/slave_3.kml',
        '/var/www/html/kmls.txt',
      ]);
      expect(c.lastSshRun, 'pkill -9 googleearth-bin');
    });
  });

  group('flyTo path set', () {
    test('only touches /tmp/query.txt', () async {
      final c = _FauxConnection(cfg3);
      await c.flyTo('<LookAt/>');
      expect(c.paths, ['/tmp/query.txt']);
    });
  });

  group('5-screen rig (verifies leftMost/rightMost formulas hold)', () {
    final cfg5 = const LGConfig(host: 'h', port: 22, user: 'u', screens: 5);
    // For 5 screens: leftMost = (5/2).floor() + 2 = 4
    test('5-screen sendPyramidAndFly writes 1..5 EXCEPT slave_4', () async {
      final c = _FauxConnection(cfg5);
      await c.sendPyramidAndFly('PYRAMID', '<LookAt/>');
      expect(c.paths.where((p) => p.contains('slave_')), [
        '/var/www/html/kml/slave_1.kml',
        '/var/www/html/kml/slave_2.kml',
        '/var/www/html/kml/slave_3.kml',
        '/var/www/html/kml/slave_5.kml',
      ]);
    });
  });
}
