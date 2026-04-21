// Tests for the QR codec: round-trip + edge cases.
//
// Run with: flutter test test/qr_payload_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:lg_flutter_task2/models/lg_config.dart';
import 'package:lg_flutter_task2/utils/qr_payload.dart';

void main() {
  group('QrPayload.encode/decode round trip', () {
    test('preserves all 4 fields', () {
      final original = QrPayload(
        config: const LGConfig(
          host: '192.168.0.243',
          port: 2201,
          user: 'lg',
          screens: 3,
        ),
        password: 'lqgalaxy',
      );
      final encoded = original.encode();
      final decoded = QrPayload.tryDecode(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.config.host, '192.168.0.243');
      expect(decoded.config.port, 2201);
      expect(decoded.config.user, 'lg');
      expect(decoded.password, 'lqgalaxy');
    });

    test('handles password with special URI characters', () {
      final original = QrPayload(
        config: const LGConfig(
          host: 'lg.local',
          port: 22,
          user: 'lg',
          screens: 3,
        ),
        password: r'p@ss:w/ord!',
      );
      final encoded = original.encode();
      final decoded = QrPayload.tryDecode(encoded);
      expect(decoded?.password, r'p@ss:w/ord!');
    });
  });

  group('QrPayload.tryDecode failure cases', () {
    test('returns null for non-lg scheme', () {
      expect(QrPayload.tryDecode('https://example.com'), isNull);
    });

    test('returns null when userInfo is missing', () {
      expect(QrPayload.tryDecode('lg://192.168.0.1:2201'), isNull);
    });

    test('returns null when userInfo lacks colon (no password)', () {
      expect(QrPayload.tryDecode('lg://lg@192.168.0.1:2201'), isNull);
    });

    test('returns null on garbage input', () {
      expect(QrPayload.tryDecode('not a uri at all'), isNull);
      expect(QrPayload.tryDecode(''), isNull);
    });

    test('trims whitespace before parsing', () {
      final p = QrPayload.tryDecode('  lg://lg:lqgalaxy@192.168.0.243:2201  ');
      expect(p, isNotNull);
    });
  });

  test('encode produces a parseable URI', () {
    final p = QrPayload(
      config: const LGConfig(host: 'h', port: 1, user: 'u', screens: 3),
      password: 'p',
    );
    expect(p.encode(), startsWith('lg://'));
    expect(Uri.tryParse(p.encode())?.scheme, 'lg');
  });
}
