/// Centralized application version constants and SemVer utilities.
class AppVersion {
  static const String current = '1.0.0';

  /// Returns true if [remoteTag] is strictly newer than [currentVersion].
  /// Handles prefixes like 'v', build metadata ('+1'), and tags.
  static bool isNewer(String remoteTag, [String localVersion = current]) {
    try {
      final remote = SemVer.parse(remoteTag);
      final local = SemVer.parse(localVersion);
      return remote.compareTo(local) > 0;
    } catch (_) {
      return false;
    }
  }
}

class SemVer implements Comparable<SemVer> {
  final int major;
  final int minor;
  final int patch;
  final int build;

  const SemVer({
    required this.major,
    required this.minor,
    required this.patch,
    this.build = 0,
  });

  factory SemVer.parse(String text) {
    var clean = text.trim();
    if (clean.startsWith('v') || clean.startsWith('V')) {
      clean = clean.substring(1).trim();
    }

    // Split build metadata (+1) if present
    var buildNum = 0;
    if (clean.contains('+')) {
      final plusParts = clean.split('+');
      clean = plusParts[0];
      if (plusParts.length > 1) {
        buildNum = int.tryParse(plusParts[1]) ?? 0;
      }
    }

    // Remove pre-release tags (-beta, -rc1) from version comparison core
    if (clean.contains('-')) {
      clean = clean.split('-')[0];
    }

    final parts = clean.split('.');
    final maj = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 0) : 0;
    final min = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final pat = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;

    return SemVer(
      major: maj,
      minor: min,
      patch: pat,
      build: buildNum,
    );
  }

  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return build.compareTo(other.build);
  }

  @override
  String toString() => '$major.$minor.$patch${build > 0 ? '+$build' : ''}';
}
