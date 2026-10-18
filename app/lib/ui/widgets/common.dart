import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme.dart';

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.bytes, this.radius = 22, this.group = false, this.online = false});
  final String name;
  final Uint8List? bytes;
  final double radius;
  final bool group, online;

  static const _palette = [Color(0xFF6BCBEF), Color(0xFFE4A5D8), Color(0xFFF7B267), Color(0xFF8FD694),
    Color(0xFFB39DDB), Color(0xFFFF8A80), Color(0xFF80CBC4), Color(0xFFFFD54F)];

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.characters.first.toUpperCase()).join();
    final color = _palette[name.hashCode.abs() % _palette.length];
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: bytes != null ? Colors.transparent : color,
      backgroundImage: bytes != null ? MemoryImage(bytes!) : null,
      child: bytes != null
          ? null
          : group
              ? Icon(Icons.group, color: Colors.white, size: radius)
              : Text(initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: radius * 0.75)),
    );
    if (!online) return avatar;
    return Stack(children: [
      avatar,
      Positioned(
        right: 0, bottom: 0,
        child: Container(
          width: radius * 0.55, height: radius * 0.55,
          decoration: BoxDecoration(color: AppTheme.green, shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2)),
        ),
      ),
    ]);
  }
}

String fmtTime(int ms) => DateFormat.Hm().format(DateTime.fromMillisecondsSinceEpoch(ms));

String fmtListTime(int ms) {
  if (ms == 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms), now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) return DateFormat.Hm().format(d);
  if (now.difference(d).inDays < 7) return DateFormat.E().format(d);
  return DateFormat.yMd().format(d);
}

String fmtDay(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms), now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day), that = DateTime(d.year, d.month, d.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat.yMMMd().format(d);
}

String fmtLastSeen(int ms) {
  if (ms == 0) return 'not seen nearby yet';
  return 'last nearby ${fmtDay(ms).toLowerCase()} at ${fmtTime(ms)}';
}

String fmtDuration(int secs) {
  final m = secs ~/ 60, s = secs % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String fmtBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1 << 20) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1 << 30) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
  return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
}

void toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'OK', bool danger = false}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(ok, style: TextStyle(color: danger ? Colors.red : null))),
        ],
      ),
    ) ??
    false;

Future<String?> promptText(BuildContext context, String title, {String initial = '', String hint = '', int maxLength = 64}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctrl, autofocus: true, maxLength: maxLength, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

/// Small banner explaining the offline connectivity state.
class NearbyBanner extends StatelessWidget {
  const NearbyBanner({super.key, required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: count > 0 ? AppTheme.green.withOpacity(.15) : Colors.orange.withOpacity(.15),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          Icon(count > 0 ? Icons.wifi_tethering : Icons.wifi_tethering_off, size: 16,
              color: count > 0 ? AppTheme.teal : Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              count > 0
                  ? '$count ${count == 1 ? 'person' : 'people'} nearby · messages deliver instantly'
                  : 'Nobody nearby · messages will send when you meet on the same Wi-Fi/hotspot',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ]),
      );
}
