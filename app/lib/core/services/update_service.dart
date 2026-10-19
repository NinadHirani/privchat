import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../constants/app_version.dart';
import '../../ui/widgets/update_dialog.dart';

/// Asset item in a GitHub release.
class ReleaseAsset {
  final String name;
  final String downloadUrl;
  final int size;
  final String abi;

  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.abi,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String?) ?? '';
    final url = (json['browser_download_url'] as String?) ?? '';
    final size = (json['size'] as num?)?.toInt() ?? 0;

    final lower = name.toLowerCase();
    String abi = 'universal';
    if (lower.contains('arm64-v8a') || lower.contains('arm64')) {
      abi = 'arm64-v8a';
    } else if (lower.contains('armeabi-v7a') || lower.contains('arm-v7a') || lower.contains('armv7')) {
      abi = 'armeabi-v7a';
    } else if (lower.contains('x86_64')) {
      abi = 'x86_64';
    }

    return ReleaseAsset(
      name: name,
      downloadUrl: url,
      size: size,
      abi: abi,
    );
  }

  String get formattedSize {
    if (size <= 0) return '';
    final mb = size / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// Metadata representation of a GitHub release.
class AppRelease {
  final String tagName;
  final String version;
  final String title;
  final String body;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;

  const AppRelease({
    required this.tagName,
    required this.version,
    required this.title,
    required this.body,
    required this.publishedAt,
    required this.assets,
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String?) ?? '';
    final ver = tag.replaceFirst(RegExp(r'^[vV]'), '');
    final name = (json['name'] as String?) ?? tag;
    final body = (json['body'] as String?) ?? '';
    final pubStr = json['published_at'] as String?;
    final pubDate = pubStr != null ? DateTime.tryParse(pubStr) : null;

    final rawAssets = json['assets'] as List<dynamic>? ?? [];
    final assets = rawAssets
        .whereType<Map<String, dynamic>>()
        .map(ReleaseAsset.fromJson)
        .where((a) => a.name.endsWith('.apk'))
        .toList();

    return AppRelease(
      tagName: tag,
      version: ver,
      title: name,
      body: body,
      publishedAt: pubDate,
      assets: assets,
    );
  }
}

/// Result of an update check.
class UpdateCheckResult {
  final bool hasUpdate;
  final AppRelease? release;
  final ReleaseAsset? targetAsset;
  final String? error;

  const UpdateCheckResult({
    required this.hasUpdate,
    this.release,
    this.targetAsset,
    this.error,
  });
}

/// Download progress update model.
class DownloadProgress {
  final int received;
  final int total;
  final bool isMirror;
  final String? statusMessage;

  const DownloadProgress({
    required this.received,
    required this.total,
    this.isMirror = false,
    this.statusMessage,
  });

  double get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
  int get percent => (fraction * 100).toInt();

  String get formattedProgress {
    final curMb = (received / (1024 * 1024)).toStringAsFixed(1);
    if (total > 0) {
      final totalMb = (total / (1024 * 1024)).toStringAsFixed(1);
      return '$curMb / $totalMb MB ($percent%)';
    }
    return '$curMb MB';
  }
}

/// Service managing in-app auto updates from GitHub releases.
class UpdateService extends ChangeNotifier {
  static const String repoOwner = 'NinadHirani';
  static const String repoName = 'privchat';
  static const String fastMirrorPrefix = 'https://ghfast.top/';
  static const MethodChannel _sys = MethodChannel('privchat/system');

  bool _isChecking = false;
  bool get isChecking => _isChecking;

  bool _isDialogShowing = false;
  bool get isDialogShowing => _isDialogShowing;

  UpdateCheckResult? _lastResult;
  UpdateCheckResult? get lastResult => _lastResult;

  List<String>? _cachedAbis;

  /// Fetches device ABIs from Android native layer (e.g. arm64-v8a).
  Future<List<String>> getDeviceAbis() async {
    if (_cachedAbis != null) return _cachedAbis!;
    if (kIsWeb || !Platform.isAndroid) {
      _cachedAbis = ['arm64-v8a'];
      return _cachedAbis!;
    }

    try {
      final res = await _sys.invokeMethod<List<dynamic>>('getSupportedAbis');
      if (res != null && res.isNotEmpty) {
        _cachedAbis = res.map((e) => e.toString().toLowerCase()).toList();
        return _cachedAbis!;
      }
    } catch (_) {}

    // Fallback: 99% modern Android phones are arm64-v8a
    _cachedAbis = ['arm64-v8a', 'armeabi-v7a'];
    return _cachedAbis!;
  }

  /// Selects best APK asset matching the device architecture.
  ReleaseAsset? selectBestAsset(List<ReleaseAsset> assets, List<String> abis) {
    if (assets.isEmpty) return null;

    // 1. Try to find an asset matching the device ABIs in order of preference
    for (final abi in abis) {
      for (final a in assets) {
        if (a.abi == abi) return a;
        if (abi.contains('arm64') && a.name.toLowerCase().contains('arm64')) return a;
        if (abi.contains('v7') && (a.name.toLowerCase().contains('v7') || a.name.toLowerCase().contains('armeabi'))) return a;
        if (abi.contains('x86_64') && a.name.toLowerCase().contains('x86_64')) return a;
      }
    }

    // 2. Fall back to universal APK if available
    for (final a in assets) {
      if (a.abi == 'universal' || a.name.toLowerCase().contains('universal') || a.name == 'app-release.apk') {
        return a;
      }
    }

    // 3. Fall back to first available APK
    return assets.first;
  }

  /// Checks GitHub Releases API for latest version.
  Future<UpdateCheckResult> check({bool silent = true}) async {
    if (_isChecking) {
      return _lastResult ?? const UpdateCheckResult(hasUpdate: false);
    }

    _isChecking = true;
    notifyListeners();

    try {
      final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);

      final req = await client.getUrl(url);
      req.headers.set('User-Agent', 'Pritoy-App/${AppVersion.current}');
      req.headers.set('Accept', 'application/vnd.github.v3+json');

      final resp = await req.close().timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        final err = 'GitHub returned HTTP ${resp.statusCode}';
        final res = UpdateCheckResult(hasUpdate: false, error: err);
        _lastResult = res;
        _isChecking = false;
        notifyListeners();
        return res;
      }

      final bodyStr = await resp.transform(utf8.decoder).join();
      final data = jsonDecode(bodyStr) as Map<String, dynamic>;
      final release = AppRelease.fromJson(data);

      final isNewer = AppVersion.isNewer(release.tagName, AppVersion.current);
      if (!isNewer) {
        final res = UpdateCheckResult(hasUpdate: false, release: release);
        _lastResult = res;
        _isChecking = false;
        notifyListeners();
        return res;
      }

      final abis = await getDeviceAbis();
      final targetAsset = selectBestAsset(release.assets, abis);

      final res = UpdateCheckResult(
        hasUpdate: true,
        release: release,
        targetAsset: targetAsset,
      );
      _lastResult = res;
      _isChecking = false;
      notifyListeners();
      return res;
    } catch (e) {
      final res = UpdateCheckResult(hasUpdate: false, error: e.toString());
      _lastResult = res;
      _isChecking = false;
      notifyListeners();
      return res;
    }
  }

  /// Downloads an asset with streaming progress, automatically falling back to CDN fast mirror.
  Future<File> downloadAsset({
    required ReleaseAsset asset,
    required void Function(DownloadProgress) onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final sanitizeName = asset.name.replaceAll(RegExp(r'[^\w\.-]'), '_');
    final targetFile = File('${tempDir.path}/$sanitizeName');

    // Attempt direct GitHub download first
    try {
      onProgress(DownloadProgress(
        received: 0,
        total: asset.size,
        isMirror: false,
        statusMessage: 'Downloading from GitHub Releases…',
      ));
      return await _downloadToFile(
        url: asset.downloadUrl,
        targetFile: targetFile,
        expectedSize: asset.size,
        isMirror: false,
        onProgress: onProgress,
      );
    } catch (e) {
      debugPrint('Direct GitHub download failed ($e). Falling back to Fast CDN mirror…');
    }

    // Fallback: fast mirror
    final mirrorUrl = '$fastMirrorPrefix${asset.downloadUrl}';
    onProgress(DownloadProgress(
      received: 0,
      total: asset.size,
      isMirror: true,
      statusMessage: 'Connecting via Fast Global Mirror…',
    ));
    return await _downloadToFile(
      url: mirrorUrl,
      targetFile: targetFile,
      expectedSize: asset.size,
      isMirror: true,
      onProgress: onProgress,
    );
  }

  Future<File> _downloadToFile({
    required String url,
    required File targetFile,
    required int expectedSize,
    required bool isMirror,
    required void Function(DownloadProgress) onProgress,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', 'Pritoy-App/${AppVersion.current}');
    req.followRedirects = true;

    final resp = await req.close();
    if (resp.statusCode != 200 && resp.statusCode != 206) {
      throw HttpException('Failed with status ${resp.statusCode}', uri: Uri.parse(url));
    }

    final total = resp.contentLength > 0 ? resp.contentLength : expectedSize;
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    final sink = targetFile.openWrite();
    var received = 0;

    await resp.listen(
      (chunk) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(DownloadProgress(
          received: received,
          total: total,
          isMirror: isMirror,
        ));
      },
      cancelOnError: true,
    ).asFuture();

    await sink.flush();
    await sink.close();

    if (!await targetFile.exists() || await targetFile.length() == 0) {
      throw const FileSystemException('Downloaded APK file is empty');
    }

    return targetFile;
  }

  /// Prompts Android OS to install the downloaded APK.
  Future<bool> installApk(File file) async {
    if (!await file.exists()) return false;

    // Use OpenFilex to start the package installer intent
    try {
      final res = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      if (res.type == ResultType.done) return true;
    } catch (e) {
      debugPrint('OpenFilex install notice: $e');
    }

    return true;
  }

  /// Checks on launch and shows the blocking modal pop-up if an update is found.
  Future<void> checkOnLaunch(BuildContext context) async {
    if (_isDialogShowing) return;

    // Wait a brief delay for app UI bootstrap to settle
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!context.mounted) return;

    final res = await check(silent: true);
    if (!context.mounted) return;

    if (res.hasUpdate && res.release != null && res.targetAsset != null) {
      showUpdateDialog(context: context, result: res);
    }
  }

  /// Displays the blocking update modal dialog.
  Future<void> showUpdateDialog({
    required BuildContext context,
    required UpdateCheckResult result,
  }) async {
    if (_isDialogShowing) return;
    _isDialogShowing = true;
    notifyListeners();

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => UpdateDialog(
          service: this,
          result: result,
        ),
      );
    } finally {
      _isDialogShowing = false;
      notifyListeners();
    }
  }
}
