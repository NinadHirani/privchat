import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';
import '../theme_manager.dart';
import '../widgets/wallpaper_view.dart';

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key, this.convId, this.convTitle});
  final String? convId;
  final String? convTitle;

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  final tm = ThemeManager.I;

  static const List<Color> _outgoingPresets = [
    AppTheme.mustardBrown,
    Color(0xFF8B5A10),
    Color(0xFFB57D29),
    Color(0xFF2A5C70),
    Color(0xFF3B6E53),
    Color(0xFF7A2E3B),
    Color(0xFF2E3B4E),
  ];

  static const List<Color> _incomingPresets = [
    AppTheme.warmIvory,
    Color(0xFFF7F5EE),
    Color(0xFFEFECE4),
    Color(0xFFFFFFFF),
    Color(0xFFE2E7EA),
    Color(0xFF2B363C),
  ];

  static const List<Color> _solidWallpapers = [
    Color(0xFF8F9FA9),
    Color(0xFF7B8D99),
    Color(0xFF5A6B75),
    Color(0xFF28343B),
    Color(0xFF1B2327),
    Color(0xFF2F3E46),
    Color(0xFF354F52),
    Color(0xFF52796F),
  ];

  late WallpaperConfig _currentWallpaper;

  @override
  void initState() {
    super.initState();
    _currentWallpaper = widget.convId != null
        ? tm.getWallpaperForConv(widget.convId!)
        : tm.globalWallpaper;
  }

  void _applyWallpaper(WallpaperConfig cfg) {
    setState(() => _currentWallpaper = cfg);
    if (widget.convId != null) {
      tm.setConversationWallpaper(widget.convId!, cfg);
    } else {
      tm.setGlobalWallpaper(cfg);
    }
  }

  Future<void> _pickImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null) return;
    _applyWallpaper(WallpaperConfig(type: WallpaperType.image, value: x.path));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final title = widget.convTitle != null
        ? 'Theme for ${widget.convTitle}'
        : 'Chat Appearance';

    return ListenableBuilder(
      listenable: tm,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            TextButton(
              onPressed: () {
                if (widget.convId != null) {
                  _applyWallpaper(const WallpaperConfig(type: WallpaperType.def));
                } else {
                  tm.resetToDefaults();
                  setState(() => _currentWallpaper = tm.globalWallpaper);
                }
              },
              child: const Text('RESET', style: TextStyle(color: AppTheme.amberAccent)),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            // Live Preview Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('LIVE PREVIEW',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Container(
                    height: 220,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))
                      ],
                    ),
                    child: WallpaperView(
                      config: _currentWallpaper,
                      isDark: isDark,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Incoming Bubble (Warm Ivory)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 240),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: tm.peerBubbleColor,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    topRight: Radius.circular(16),
                                    bottomRight: Radius.circular(16),
                                    bottomLeft: Radius.circular(4),
                                  ),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4, offset: const Offset(0, 2)),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Hey! Loving this custom PrivChat aesthetic 🎨',
                                      style: TextStyle(color: tm.peerTextColor, fontSize: 14),
                                    ),
                                    const SizedBox(height: 4),
                                    Text('10:42 AM',
                                        style: TextStyle(
                                            color: tm.peerTextColor.withOpacity(0.5), fontSize: 11)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Outgoing Bubble (Mustard Brown)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 250),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: tm.myBubbleColor,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    topRight: Radius.circular(16),
                                    bottomLeft: Radius.circular(16),
                                    bottomRight: Radius.circular(4),
                                  ),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 4, offset: const Offset(0, 2)),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Mustard brown on cadet grey looks amazing! 🚀',
                                      style: TextStyle(color: tm.myTextColor, fontSize: 14),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('10:43 AM',
                                            style: TextStyle(
                                                color: tm.myTextColor.withOpacity(0.7), fontSize: 11)),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.done_all, size: 14, color: AppTheme.tickBlue),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Bubble Colors Section (Global Only)
            if (widget.convId == null) ...[
              _sectionTitle('YOUR MESSAGE BUBBLE (OUTGOING)'),
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _outgoingPresets.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final c = _outgoingPresets[i];
                    final isSel = tm.myBubbleColor.value == c.value;
                    return GestureDetector(
                      onTap: () => tm.setBubbleColors(myBubble: c),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: isSel ? Border.all(color: Colors.white, width: 3.5) : null,
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4)
                          ],
                        ),
                        child: isSel ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              _sectionTitle('OTHER PERSON BUBBLE (INCOMING)'),
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _incomingPresets.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final c = _incomingPresets[i];
                    final isSel = tm.peerBubbleColor.value == c.value;
                    final isDarkSwatch = ThemeData.estimateBrightnessForColor(c) == Brightness.dark;
                    return GestureDetector(
                      onTap: () => tm.setBubbleColors(
                        peerBubble: c,
                        peerText: isDarkSwatch ? Colors.white : AppTheme.deepCarbon,
                      ),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: isSel ? AppTheme.amberAccent : Colors.grey.shade400, width: isSel ? 3.5 : 1),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 4)
                          ],
                        ),
                        child: isSel
                            ? Icon(Icons.check,
                                color: isDarkSwatch ? Colors.white : AppTheme.deepCarbon, size: 20)
                            : null,
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),
              const Divider(height: 32),
            ],

            // Wallpaper Section
            _sectionTitle('CHAT WALLPAPER & BACKGROUND'),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppTheme.amberAccent,
                child: Icon(Icons.photo_library, color: Colors.black),
              ),
              title: const Text('Choose from Gallery / Photos'),
              subtitle: const Text('Import custom background image from device'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickImage,
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppTheme.cadetGrey,
                child: Icon(Icons.palette, color: Colors.white),
              ),
              title: const Text('Default Cadet Grey Canvas'),
              subtitle: const Text('Signature PrivChat neutral background'),
              onTap: () => _applyWallpaper(const WallpaperConfig(type: WallpaperType.def)),
            ),

            const SizedBox(height: 12),
            _sectionTitle('CURATED PREMADE WALLPAPERS'),
            SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: ThemeManager.premades.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final p = ThemeManager.premades[i];
                  final isSel = _currentWallpaper.type == WallpaperType.preset &&
                      _currentWallpaper.value == p.id;
                  return GestureDetector(
                    onTap: () => _applyWallpaper(WallpaperConfig(type: WallpaperType.preset, value: p.id)),
                    child: Container(
                      width: 90,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: isSel ? Border.all(color: AppTheme.amberAccent, width: 3) : Border.all(color: Colors.grey.shade400, width: 0.5),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          WallpaperView(
                            config: WallpaperConfig(type: WallpaperType.preset, value: p.id),
                            child: const SizedBox(),
                          ),
                          Container(
                            alignment: Alignment.bottomCenter,
                            padding: const EdgeInsets.all(6),
                            color: Colors.black45,
                            child: Text(
                              p.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (isSel)
                            const Center(
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: AppTheme.amberAccent,
                                child: Icon(Icons.check, size: 16, color: Colors.black),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),
            _sectionTitle('SOLID ACCENT COLORS'),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _solidWallpapers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final c = _solidWallpapers[i];
                  final isSel = _currentWallpaper.type == WallpaperType.color &&
                      _currentWallpaper.value == c.value.toString();
                  return GestureDetector(
                    onTap: () => _applyWallpaper(
                        WallpaperConfig(type: WallpaperType.color, value: c.value.toString())),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: isSel ? Border.all(color: AppTheme.amberAccent, width: 3.5) : null,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 4)
                        ],
                      ),
                      child: isSel ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          color: Colors.grey,
        ),
      ),
    );
  }
}
