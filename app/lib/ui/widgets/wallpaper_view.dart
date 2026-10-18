import 'dart:io';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../theme_manager.dart';

/// Wraps chat content with the configured wallpaper (default, preset pattern, gallery image, or color).
class WallpaperView extends StatelessWidget {
  const WallpaperView({
    super.key,
    required this.config,
    required this.child,
    this.isDark = false,
  });

  final WallpaperConfig config;
  final Widget child;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildBackground(context),
        child,
      ],
    );
  }

  Widget _buildBackground(BuildContext context) {
    switch (config.type) {
      case WallpaperType.image:
        if (config.value.isNotEmpty) {
          final file = File(config.value);
          if (file.existsSync()) {
            return Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _defaultBackground(),
            );
          }
        }
        return _defaultBackground();

      case WallpaperType.color:
        if (config.value.isNotEmpty) {
          try {
            final col = Color(int.parse(config.value));
            return Container(color: col);
          } catch (_) {}
        }
        return _defaultBackground();

      case WallpaperType.preset:
        final p = ThemeManager.premades.firstWhere(
          (e) => e.id == config.value,
          orElse: () => ThemeManager.premades.first,
        );
        return CustomPaint(
          painter: _PresetWallpaperPainter(preset: p),
          size: Size.infinite,
        );

      case WallpaperType.def:
      default:
        return _defaultBackground();
    }
  }

  Widget _defaultBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF1E262B), Color(0xFF141A1E)]
              : const [Color(0xFF9AAAB5), Color(0xFF8696A0)],
        ),
      ),
      child: CustomPaint(
        painter: _SubtleDoodlePainter(isDark: isDark),
        size: Size.infinite,
      ),
    );
  }
}

class _PresetWallpaperPainter extends CustomPainter {
  _PresetWallpaperPainter({required this.preset});
  final PremadeWallpaper preset;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [preset.primaryColor, preset.secondaryColor],
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    if (preset.id == 'geometric_grid') {
      final gridPaint = Paint()
        ..color = Colors.white.withOpacity(0.04)
        ..strokeWidth = 1;
      const step = 28.0;
      for (double x = 0; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (double y = 0; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    } else if (preset.id == 'constellation') {
      final starPaint = Paint()..color = Colors.white.withOpacity(0.18);
      final glowPaint = Paint()..color = AppTheme.amberAccent.withOpacity(0.08);
      canvas.drawCircle(Offset(size.width * 0.25, size.height * 0.2), 4, glowPaint);
      canvas.drawCircle(Offset(size.width * 0.25, size.height * 0.2), 1.5, starPaint);
      canvas.drawCircle(Offset(size.width * 0.75, size.height * 0.35), 1.8, starPaint);
      canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.65), 2.2, starPaint);
      canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.8), 1.5, starPaint);
      canvas.drawCircle(Offset(size.width * 0.15, size.height * 0.85), 2, starPaint);
    } else if (preset.id == 'minimal_dots') {
      final dotPaint = Paint()..color = Colors.black.withOpacity(0.05);
      const step = 24.0;
      for (double x = 12; x < size.width; x += step) {
        for (double y = 12; y < size.height; y += step) {
          canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PresetWallpaperPainter oldDelegate) =>
      oldDelegate.preset.id != preset.id;
}

class _SubtleDoodlePainter extends CustomPainter {
  _SubtleDoodlePainter({required this.isDark});
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.025)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    const spacing = 120.0;
    for (double x = 40; x < size.width; x += spacing) {
      for (double y = 40; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 14, p);
        canvas.drawRect(Rect.fromCenter(center: Offset(x + 50, y + 40), width: 18, height: 18), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SubtleDoodlePainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
