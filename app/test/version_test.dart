import 'package:flutter_test/flutter_test.dart';
import 'package:privchat/core/constants/app_version.dart';

void main() {
  group('AppVersion and SemVer', () {
    test('parses standard semver correctly', () {
      final v = SemVer.parse('1.2.3');
      expect(v.major, 1);
      expect(v.minor, 2);
      expect(v.patch, 3);
      expect(v.build, 0);
    });

    test('handles leading v and build numbers', () {
      final v = SemVer.parse('v2.4.1+5');
      expect(v.major, 2);
      expect(v.minor, 4);
      expect(v.patch, 1);
      expect(v.build, 5);
    });

    test('correctly identifies newer versions', () {
      expect(AppVersion.isNewer('v1.0.1', '1.0.0'), isTrue);
      expect(AppVersion.isNewer('1.1.0', '1.0.0'), isTrue);
      expect(AppVersion.isNewer('v2.0.0', '1.9.9'), isTrue);
      expect(AppVersion.isNewer('v1.0.0+2', '1.0.0+1'), isTrue);

      expect(AppVersion.isNewer('v1.0.0', '1.0.0'), isFalse);
      expect(AppVersion.isNewer('0.9.9', '1.0.0'), isFalse);
      expect(AppVersion.isNewer('v1.0.0', '1.0.1'), isFalse);
    });
  });
}
