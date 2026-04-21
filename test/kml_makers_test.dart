// Unit tests for kml_makers.dart.
//
// Pattern: every builder gets one golden test that compares its output to a
// committed file in test/fixtures/. When a builder's output is intentionally
// changed, regenerate the fixture via `dart run tool/gen_fixtures.dart` and
// commit both changes together.
//
// Why golden fixtures vs. substring assertions: substring checks (e.g.,
// `contains('<ScreenOverlay>')`) don't catch malformed XML, missing closing
// tags, or whitespace regressions that GE silently rejects. Golden fixtures
// catch any change and the failure diff points straight at what moved.
//
// xmlEscape gets dedicated tests because it's the highest-risk function: it
// is used by every builder that takes user input, and a regression there
// silently corrupts every KML containing a special character.
//
// Run with: flutter test test/kml_makers_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lg_flutter_task2/utils/kml/kml_makers.dart';

void main() {
  group('xmlEscape', () {
    test('escapes ampersand FIRST so later escapes are not double-escaped', () {
      // If we escaped < before & this would produce '&amp;amp;lt;'.
      expect(xmlEscape('<&>'), '&lt;&amp;&gt;');
    });

    test('escapes all 5 special characters', () {
      expect(xmlEscape('<>&\'"'), '&lt;&gt;&amp;&apos;&quot;');
    });

    test('passes through normal text untouched', () {
      expect(xmlEscape('Madrid, Spain'), 'Madrid, Spain');
    });

    test('handles empty string', () {
      expect(xmlEscape(''), '');
    });

    test('handles a real-world city name with apostrophe', () {
      expect(xmlEscape("Land's End"), 'Land&apos;s End');
    });
  });

  group('buildLogoKml', () {
    test('matches golden fixture', () {
      final actual = buildLogoKml(
        imageUrl:
            'https://raw.githubusercontent.com/lucisays/imagen/main/LGMasterWebAppLogo.png',
      );
      final expected = File('test/fixtures/golden_logo.kml').readAsStringSync();
      expect(actual, expected);
    });

    test(
      'escapes the imageUrl when it contains XML-significant characters',
      () {
        final out = buildLogoKml(imageUrl: 'https://x.com/img?a=1&b=2');
        expect(out, contains('a=1&amp;b=2'));
        expect(out, isNot(contains('a=1&b=2')));
      },
    );
  });

  group('buildPyramidKml', () {
    test('matches golden fixture (Madrid)', () {
      final actual = buildPyramidKml(centerLat: 40.4168, centerLng: -3.7038);
      final expected = File(
        'test/fixtures/golden_pyramid_madrid.kml',
      ).readAsStringSync();
      expect(actual, expected);
    });

    test('produces 4 faces + 1 base = 5 Placemarks', () {
      final out = buildPyramidKml(centerLat: 40.4168, centerLng: -3.7038);
      final placemarkCount = '<Placemark>'.allMatches(out).length;
      expect(placemarkCount, 5);
    });

    test('apex altitude reflects the heightMeters parameter', () {
      final out = buildPyramidKml(
        centerLat: 0,
        centerLng: 0,
        heightMeters: 2500,
      );
      // Apex appears as "0.0,0.0,2500.0" once per face. Dart formats doubles
      // with the trailing ".0", so we look for ",2500.0". Should appear 4
      // times — once in each of the 4 triangular faces.
      final matches = ',2500.0'.allMatches(out).length;
      expect(matches, 4);
    });
  });

  group('buildLookAtXml', () {
    test('matches golden fixture (Madrid)', () {
      final actual = buildLookAtXml(lat: 40.4168, lng: -3.7038);
      final expected = File(
        'test/fixtures/golden_lookat_madrid.kml',
      ).readAsStringSync();
      expect(actual, expected);
    });

    test('does NOT include a <kml> envelope (it is a fragment)', () {
      final out = buildLookAtXml(lat: 0, lng: 0);
      expect(out, isNot(contains('<kml')));
      expect(out, startsWith('<LookAt>'));
      expect(out, endsWith('</LookAt>'));
    });

    test('default range is 4500 (tuned for a ~1km pyramid)', () {
      final out = buildLookAtXml(lat: 0, lng: 0);
      expect(out, contains('<range>4500'));
    });
  });

  group('blankSlaveKml', () {
    test('matches golden fixture (slave_3)', () {
      final actual = blankSlaveKml(3);
      final expected = File(
        'test/fixtures/golden_blank_slave_3.kml',
      ).readAsStringSync();
      expect(actual, expected);
    });

    test('embeds the slave number in the <name>', () {
      expect(blankSlaveKml(2), contains('<name>slave_2</name>'));
      expect(blankSlaveKml(7), contains('<name>slave_7</name>'));
    });
  });
}
