import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/constants/app_version.dart';
import '../../core/services/update_service.dart';
import '../theme.dart';

enum UpdateStage {
  ready,
  downloading,
  downloaded,
  installing,
  error,
}

class UpdateDialog extends StatefulWidget {
  final UpdateService service;
  final UpdateCheckResult result;

  const UpdateDialog({
    super.key,
    required this.service,
    required this.result,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  UpdateStage _stage = UpdateStage.ready;
  DownloadProgress? _progress;
  File? _downloadedFile;
  String? _errorMessage;

  AppRelease get release => widget.result.release!;
  ReleaseAsset? get asset => widget.result.targetAsset;

  Future<void> _startUpdate() async {
    if (asset == null) {
      setState(() {
        _stage = UpdateStage.error;
        _errorMessage = 'No compatible release APK found for this device.';
      });
      return;
    }

    setState(() {
      _stage = UpdateStage.downloading;
      _errorMessage = null;
      _progress = DownloadProgress(
        received: 0,
        total: asset!.size,
        statusMessage: 'Starting download…',
      );
    });

    try {
      final file = await widget.service.downloadAsset(
        asset: asset!,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _progress = p;
            });
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _downloadedFile = file;
        _stage = UpdateStage.downloaded;
      });

      // Automatically launch installer once downloaded
      await _install();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = UpdateStage.error;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _install() async {
    if (_downloadedFile == null) return;
    setState(() => _stage = UpdateStage.installing);

    final ok = await widget.service.installApk(_downloadedFile!);
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _stage = UpdateStage.error;
        _errorMessage = 'Failed to launch installer. Please check app permissions.';
      });
    } else {
      // Revert to downloaded so they can tap install again if they backed out of Android prompt
      setState(() => _stage = UpdateStage.downloaded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF1E262C) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1C2429);
    final cardBg = isDark ? const Color(0xFF141A1E) : const Color(0xFFF3F5F7);

    return PopScope(
      canPop: false, // Mandatory blocking update
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: dialogBg,
        elevation: 16,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Header Icon & Tag
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.amberAccent, AppTheme.mustardBrown],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.mustardBrown.withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    size: 34,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Title
              Text(
                'Update Available',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),

              // Version Badges: current -> new
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _versionChip('v${AppVersion.current}', isOld: true),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
                  ),
                  _versionChip(release.tagName, isOld: false),
                ],
              ),
              const SizedBox(height: 16),

              // ABI / Size Badge
              if (asset != null) ...[
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.mustardBrown.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Optimized for ${asset!.abi.toUpperCase()} • ${asset!.formattedSize}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.mustardBrown,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Release notes / changelog card
              if (release.body.trim().isNotEmpty) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                    ),
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        child: Text(
                          release.body.trim(),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ] else ...[
                Text(
                  'A new update is required to continue using Pritoy. Please install the latest release to keep your conversations encrypted and active.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black54,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
              ],

              // Download / Progress Area
              if (_stage == UpdateStage.downloading && _progress != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress!.total > 0 ? _progress!.fraction : null,
                    minHeight: 8,
                    backgroundColor: isDark ? Colors.white12 : Colors.black12,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.mustardBrown),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _progress!.formattedProgress,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    if (_progress!.isMirror)
                      const Row(
                        children: [
                          Icon(Icons.bolt_rounded, size: 14, color: AppTheme.amberAccent),
                          SizedBox(width: 2),
                          Text(
                            'Fast Mirror',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.amberAccent,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Error display
              if (_stage == UpdateStage.error && _errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Installing indicator
              if (_stage == UpdateStage.installing) ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.mustardBrown),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Launching package installer…',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Action button
              FilledButton(
                onPressed: _stage == UpdateStage.downloading || _stage == UpdateStage.installing
                    ? null
                    : () {
                        if (_stage == UpdateStage.downloaded) {
                          _install();
                        } else {
                          _startUpdate();
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.mustardBrown,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                child: Text(
                  _buttonLabel(),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buttonLabel() {
    switch (_stage) {
      case UpdateStage.ready:
        return 'Update Now';
      case UpdateStage.downloading:
        return 'Downloading update…';
      case UpdateStage.downloaded:
        return 'Install Update';
      case UpdateStage.installing:
        return 'Installing…';
      case UpdateStage.error:
        return 'Retry Update';
    }
  }

  Widget _versionChip(String text, {required bool isOld}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: isOld ? Colors.grey.withOpacity(0.15) : AppTheme.amberAccent.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOld ? Colors.grey.withOpacity(0.3) : AppTheme.amberAccent,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isOld ? Colors.grey : AppTheme.mustardBrown,
        ),
      ),
    );
  }
}
