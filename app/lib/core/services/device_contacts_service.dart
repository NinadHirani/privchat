import 'dart:typed_data';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../storage/db.dart';
import 'directory_service.dart';

class DeviceContactItem {
  DeviceContactItem({
    required this.id,
    required this.displayName,
    this.phone = '',
    this.email = '',
    this.photo,
    this.isOnPrivChat = false,
    this.privchatUserId,
  });

  final String id;
  final String displayName;
  final String phone;
  final String email;
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
    return DirectoryService.normalizePhone(raw);
  }

  static String normalizeEmail(String raw) {
    return DirectoryService.normalizeEmail(raw);
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
      final emailToUserId = <String, String>{};

      for (final c in knownDbContacts) {
        final ph = db.kvGet('contact_phone:${c.userId}');
        if (ph != null && ph.isNotEmpty) {
          phoneToUserId[normalizePhone(ph)] = c.userId;
        }
        final em = db.kvGet('contact_email:${c.userId}');
        if (em != null && em.isNotEmpty) {
          emailToUserId[normalizeEmail(em)] = c.userId;
        }
      }

      final items = <DeviceContactItem>[];
      final hashesToQuery = <String>{};
      final hashToItemIndices = <String, List<int>>{};

      for (final c in list) {
        final phone = c.phones.isNotEmpty ? c.phones.first.number : '';
        final email = c.emails.isNotEmpty ? c.emails.first.address : '';
        final normPhone = normalizePhone(phone);
        final normEmail = normalizeEmail(email);

        String? onPrivChatUid;
        if (normPhone.isNotEmpty && phoneToUserId.containsKey(normPhone)) {
          onPrivChatUid = phoneToUserId[normPhone];
        } else if (normEmail.isNotEmpty && emailToUserId.containsKey(normEmail)) {
          onPrivChatUid = emailToUserId[normEmail];
        }

        final itemIdx = items.length;
        items.add(DeviceContactItem(
          id: c.id,
          displayName: c.displayName.isNotEmpty
              ? c.displayName
              : (phone.isNotEmpty ? phone : (email.isNotEmpty ? email : 'Unknown')),
          phone: phone,
          email: email,
          photo: c.photo,
          isOnPrivChat: onPrivChatUid != null,
          privchatUserId: onPrivChatUid,
        ));

        // Prepare hashes for privacy-preserving online directory lookup
        if (onPrivChatUid == null) {
          if (normPhone.length >= 7) {
            final phHash = DirectoryService.hashIdentifier(normPhone);
            hashesToQuery.add(phHash);
            hashToItemIndices.putIfAbsent(phHash, () => []).add(itemIdx);
          }
          if (normEmail.contains('@')) {
            final emHash = DirectoryService.hashIdentifier(normEmail);
            hashesToQuery.add(emHash);
            hashToItemIndices.putIfAbsent(emHash, () => []).add(itemIdx);
          }
        }
      }

      // Check online Firestore directory using SHA-256 hashes
      if (hashesToQuery.isNotEmpty) {
        try {
          final foundMap = await DirectoryService.I.batchLookupHashes(hashesToQuery);
          for (final entry in foundMap.entries) {
            final hash = entry.key;
            final user = entry.value;
            final indices = hashToItemIndices[hash] ?? [];
            for (final idx in indices) {
              final it = items[idx];
              it.isOnPrivChat = true;
              it.privchatUserId = user.userId;
              // Cache locally in db
              if (it.phone.isNotEmpty) {
                db.kvSet('contact_phone:${user.userId}', it.phone);
              }
              if (it.email.isNotEmpty) {
                db.kvSet('contact_email:${user.userId}', it.email);
              }
            }
          }
        } catch (_) {}
      }

      items.sort((a, b) {
        if (a.isOnPrivChat && !b.isOnPrivChat) return -1;
        if (!a.isOnPrivChat && b.isOnPrivChat) return 1;
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });

      _cached = items;
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<void> inviteContact(DeviceContactItem contact) async {
    const text = 'Hey! Let\'s talk on PrivChat — the private, end-to-end encrypted messenger. Download it here: https://github.com/NinadHirani/privchat/releases/latest';

    if (contact.phone.isNotEmpty) {
      final uri = Uri.parse('sms:${contact.phone}?body=${Uri.encodeComponent(text)}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return;
      }
    }

    if (contact.email.isNotEmpty) {
      final uri = Uri.parse('mailto:${contact.email}?subject=${Uri.encodeComponent("Join me on PrivChat")}&body=${Uri.encodeComponent(text)}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return;
      }
    }

    await Share.share(text, subject: 'Join me on PrivChat');
  }
}
