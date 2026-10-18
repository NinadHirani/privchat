import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/storage/db.dart';
import 'theme.dart';

enum WallpaperType { def, preset, image, color }

class WallpaperConfig {
  const WallpaperConfig({required this.type, this.value = ''});
  final WallpaperType type;
  final String value;

  Map<String, dynamic> toJson() => {'type': type.name, 'value': value};

  factory WallpaperConfig.fromJson(Map<String, dynamic> j) {
    final t = WallpaperType.values.firstWhere(
      (e) => e.name == j['type'],
      orElse: () => WallpaperType.def,
    );
    return WallpaperConfig(type: t, value: j['value'] ?? '');
  }
}

class PremadeWallpaper {
  const PremadeWallpaper({
    required this.id,
    required this.name,
    required this.description,
    required this.primaryColor,
    required this.secondaryColor,
    this.isDark = false,
  });

  final String id;
  final String name;
  final String description;
  final Color primaryColor;
  final Color secondaryColor;
  final bool isDark;
}

class ThemeManager extends ChangeNotifier {
  ThemeManager._();
  static final ThemeManager I = ThemeManager._();

  static const List<PremadeWallpaper> premades = [
    PremadeWallpaper(
      id: 'cadet_slate',
      name: 'Cadet Slate',
      description: 'Signature slate cadet grey with subtle depth',
      primaryColor: Color(0xFF8F9FA9),
      secondaryColor: Color(0xFF7A8B95),
    ),
    PremadeWallpaper(
      id: 'geometric_grid',
      name: 'Privacy Matrix',
      description: 'Architectural subtle cyber grid',
      primaryColor: Color(0xFF1F282D),
      secondaryColor: Color(0xFF141A1E),
      isDark: true,
    ),
    PremadeWallpaper(
      id: 'constellation',
      name: 'Deep Orbit',
      description: 'Midnight obsidian with starlight glow',
      primaryColor: Color(0xFF121820),
      secondaryColor: Color(0xFF223040),
      isDark: true,
    ),
    PremadeWallpaper(
      id: 'dusk_gradient',
      name: 'Warm Dusk',
      description: 'Twilight gradient blending amber and slate',
      primaryColor: Color(0xFF382A1E),
      secondaryColor: Color(0xFF1E252A),
      isDark: true,
    ),
    PremadeWallpaper(
      id: 'minimal_dots',
      name: 'Dot Canvas',
      description: 'Soft cadet grey with subtle matrix dots',
      primaryColor: Color(0xFFA2B0B9),
      secondaryColor: Color(0xFF8F9FA9),
    ),
    PremadeWallpaper(
      id: 'pure_charcoal',
      name: 'Stealth Carbon',
      description: 'Deep matte dark mode slate',
      primaryColor: Color(0xFF161A1D),
      secondaryColor: Color(0xFF0F1214),
      isDark: true,
    ),
  ];

  Color _myBubbleColor = AppTheme.mustardBrown;
  Color _peerBubbleColor = AppTheme.warmIvory;
  Color _myTextColor = Colors.white;
  Color _peerTextColor = AppTheme.deepCarbon;
  WallpaperConfig _globalWallpaper = const WallpaperConfig(type: WallpaperType.def);
  final Map<String, WallpaperConfig> _convWallpapers = {};

  Color get myBubbleColor => _myBubbleColor;
  Color get peerBubbleColor => _peerBubbleColor;
  Color get myTextColor => _myTextColor;
  Color get peerTextColor => _peerTextColor;
  WallpaperConfig get globalWallpaper => _globalWallpaper;

  void init() {
    try {
      final db = AppDb.I;
      final raw = db.kvGet('theme_config');
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        if (j['myBubble'] != null) _myBubbleColor = Color(j['myBubble'] as int);
        if (j['peerBubble'] != null) _peerBubbleColor = Color(j['peerBubble'] as int);
        if (j['myText'] != null) _myTextColor = Color(j['myText'] as int);
        if (j['peerText'] != null) _peerTextColor = Color(j['peerText'] as int);
        if (j['wallpaper'] != null) {
          _globalWallpaper = WallpaperConfig.fromJson(j['wallpaper'] as Map<String, dynamic>);
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  void _persist() {
    try {
      final db = AppDb.I;
      final data = {
        'myBubble': _myBubbleColor.value,
        'peerBubble': _peerBubbleColor.value,
        'myText': _myTextColor.value,
        'peerText': _peerTextColor.value,
        'wallpaper': _globalWallpaper.toJson(),
      };
      db.kvSet('theme_config', jsonEncode(data));
    } catch (_) {}
  }

  void setBubbleColors({
    Color? myBubble,
    Color? peerBubble,
    Color? myText,
    Color? peerText,
  }) {
    if (myBubble != null) _myBubbleColor = myBubble;
    if (peerBubble != null) _peerBubbleColor = peerBubble;
    if (myText != null) _myTextColor = myText;
    if (peerText != null) _peerTextColor = peerText;
    _persist();
    notifyListeners();
  }

  void setGlobalWallpaper(WallpaperConfig cfg) {
    _globalWallpaper = cfg;
    _persist();
    notifyListeners();
  }

  WallpaperConfig getWallpaperForConv(String convId) {
    if (_convWallpapers.containsKey(convId)) {
      return _convWallpapers[convId]!;
    }
    try {
      final raw = AppDb.I.kvGet('conv_wallpaper:$convId');
      if (raw != null) {
        final cfg = WallpaperConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        _convWallpapers[convId] = cfg;
        return cfg;
      }
    } catch (_) {}
    return _globalWallpaper;
  }

  void setConversationWallpaper(String convId, WallpaperConfig? cfg) {
    if (cfg == null || cfg.type == WallpaperType.def) {
      _convWallpapers.remove(convId);
      try {
        AppDb.I.kvSet('conv_wallpaper:$convId', '');
      } catch (_) {}
    } else {
      _convWallpapers[convId] = cfg;
      try {
        AppDb.I.kvSet('conv_wallpaper:$convId', jsonEncode(cfg.toJson()));
      } catch (_) {}
    }
    notifyListeners();
  }

  void resetToDefaults() {
    _myBubbleColor = AppTheme.mustardBrown;
    _peerBubbleColor = AppTheme.warmIvory;
    _myTextColor = Colors.white;
    _peerTextColor = AppTheme.deepCarbon;
    _globalWallpaper = const WallpaperConfig(type: WallpaperType.def);
    _convWallpapers.clear();
    _persist();
    notifyListeners();
  }
}
