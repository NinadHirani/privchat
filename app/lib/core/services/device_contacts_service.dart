import 'dart:typed_data';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../storage/db.dart';

class DeviceContactItem {
  DeviceContactItem({
    required this.id,
    required this.displayName,
    this.phone = '',
    this.photo,
    this.isOnPrivChat = false,
    this.privchatUserId,
  });

  final String id;
  final String displayName;
  final String phone;
  final Uint8List? photo;
  bool isOnPrivChat;
  String? privchatUserId;

  String get initials => displayName.trim().isEmpty
      ? '?'
      : displayName.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
}

class DeviceContactsService {
  DeviceContactsService._();
  static final DeviceContactsService I = DeviceContactsService._();

  List<DeviceContactItem> _cached = [];
  List<DeviceContactItem> get contacts => _cached;

  static String normalizePhone(String raw) {
    return raw.replaceAll(RegExp(r'[^\d+]'), '');
  }

  Future<bool> hasPermission() async {
    try {
      return await fc.FlutterContacts.requestPermission(readonly: true);
    } catch (_) {
      return false;
    }
  }

  Future<List<DeviceContactItem>> loadGoogleContacts(AppDb db) async {
    final granted = await hasPermission();
    if (!granted) return [];

    try {
      final list = await fc.FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: true,
      );

      final knownDbContacts = db.contacts();
      final phoneToUserId = <String, String>{};
      for (final c in knownDbContacts) {
        final ph = db.kvGet('contact_phone:${c.userId}');
        if (ph != null && ph.isNotEmpty) {
          phoneToUserId[normalizePhone(ph)] = c.userId;
        }
      }

      final items = <DeviceContactItem>[];
      for (final c in list) {
        final phone = c.phones.isNotEmpty ? c.phones.first.number : '';
        final norm = normalizePhone(phone);
        final onPrivChatUid = norm.isNotEmpty ? phoneToUserId[norm] : null;

        items.add(DeviceContactItem(
          id: c.id,
          displayName: c.displayName.isNotEmpty ? c.displayName : (phone.isNotEmpty ? phone : 'Unknown'),
          phone: phone,
          photo: c.photo,
          isOnPrivChat: onPrivChatUid != null,
          privchatUserId: onPrivChatUid,
        ));
      }

      items.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      _cached = items;
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<void> inviteContact(DeviceContactItem contact) async {
    final text = 'Hey ${contact.displayName}! Let\'s talk on PrivChat — the serverless, private encrypted messenger. Download it here: https://github.com/NinadHirani/privchat/releases/latest';
    if (contact.phone.isNotEmpty) {
      final uri = Uri.parse('sms:${contact.phone}?body=${Uri.encodeComponent(text)}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return;
      }
    }
    await Share.share(text, subject: 'Join me on PrivChat');
  }
}
