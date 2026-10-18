import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../crypto/crypto.dart';
import '../crypto/identity.dart';
import '../network/connection_manager.dart';
import '../network/file_transfer.dart';
import '../storage/db.dart';
import '../storage/media_store.dart';
import '../storage/secure_store.dart';
import '../../models/models.dart';
import '../../ui/theme_manager.dart';
import 'call_service.dart';
import 'group_service.dart';
import 'message_service.dart';
import 'notification_service.dart';
import 'status_service.dart';

/// Composition root. One instance for the app's lifetime; UI listens via ListenableBuilder.
class AppCore extends ChangeNotifier {
  AppCore._();
  static AppCore? _i;
  static AppCore get I => _i!;
  static bool get ready => _i != null;
  static const _bg = MethodChannel('privchat/background');

  late final Identity identity;
  late final AppDb db;
  late final ConnectionManager cm;
  late final FileTransfer files;
  late final MessageService messages;
  late final GroupService groups;
  late final StatusService status;
  late final CallService calls;
  late final NotificationService notifications;
  String displayName = '';
  Uint8List? avatar;
  String about = 'Hey there! I am using PrivChat.';
  final Set<String> typingPeers = {}; // convIds where the peer is typing
  Timer? _housekeeping;

  static Future<bool> hasIdentity() async {
    await Crypto.init();
    return (await SecureStore.seed()) != null;
  }

  /// Boot with the stored identity, or create one when [newName] is given, or restore from [restoreSeed].
  static Future<AppCore> boot({String? newName, Uint8List? restoreSeed, String? phone}) async {
    if (_i != null) return _i!;
    await Crypto.init();
    final c = AppCore._();
    var seed = restoreSeed ?? await SecureStore.seed();
    if (seed == null) {
      if (newName == null) throw StateError('no identity');
      seed = Crypto.I.random(32);
    }
    await SecureStore.saveSeed(seed);
    if (newName != null) await SecureStore.saveDisplayName(newName);
    c.identity = Identity.fromSeed(seed);
    c.displayName = (await SecureStore.displayName()) ?? newName ?? 'Me';
    c.db = await AppDb.open(await SecureStore.dbKey());
    if (phone != null && phone.isNotEmpty) {
      c.db.kvSet('user_phone', phone);
    }
    ThemeManager.I.init();
    await MediaStore.init();
    await MediaStore.wipeCache();
    c.about = c.db.kvGet('about') ?? c.about;
    final av = c.db.kvGet('avatar');
    if (av != null && av.isNotEmpty) c.avatar = Crypto.b64d(av);

    c.cm = ConnectionManager(identity: c.identity, displayName: c.displayName);
    c.cm.isBlocked = (uid) => c.db.contact(uid)?.blocked ?? false;
    c.files = FileTransfer(c.cm);
    c.notifications = NotificationService();
    await c.notifications.init();
    c.messages = MessageService(c);
    c.groups = GroupService(c);
    c.status = StatusService(c);
    c.calls = CallService(c);
    c.files.canServe = c.messages.canServeFile;
    c.files.progress.listen((_) => c.notify());
    c.cm.events.listen((e) {
      c.db.touchContact(e.peerId, DateTime.now().millisecondsSinceEpoch);
      if (e.type == 'online') c.messages.onPeerOnline(e.peerId);
      if (e.type == 'offline') c.calls.onPeerOffline(e.peerId);
      c.notify();
    });
    c.cm.envelopes.listen((e) => c._dispatch(e.$1.peerId, e.$2));
    _i = c;
    await c.cm.start();
    c.cm.discovery?.peers.listen((_) => c.notify());
    c._housekeeping = Timer.periodic(const Duration(seconds: 30), (_) {
      if (c.db.purgeExpired() > 0) c.notify();
    });
    c.db.purgeExpired();
    if (c.backgroundStandby) {
      try {
        await _bg.invokeMethod('start'); // Android foreground service + multicast lock
      } catch (_) {}
    }
    return c;
  }

  void _dispatch(String from, Map<String, dynamic> env) {
    final t = env['type'] as String? ?? '';
    try {
      if (t.startsWith('group.')) {
        groups.handle(from, env);
      } else if (t.startsWith('status.')) {
        status.handle(from, env);
      } else if (t.startsWith('call.')) {
        calls.handle(from, env);
      } else if (t == 'file.req' || t == 'file.done') {
        // FileTransfer listens directly
      } else {
        messages.handle(from, env);
      }
    } catch (e, st) {
      debugPrint('dispatch error $t: $e\n$st');
    }
  }

  void notify() => notifyListeners();

  // ---- settings flags ----
  bool flag(String k, {bool def = false}) {
    final v = db.kvGet(k);
    return v == null ? def : v == '1';
  }

  void setFlag(String k, bool v) {
    db.kvSet(k, v ? '1' : '0');
    notify();
  }

  bool get readReceipts => flag('read_receipts', def: true);
  bool get contactsOnly => flag('contacts_only', def: false);
  bool get backgroundStandby => flag('bg_standby', def: true);

  Future<void> setBackgroundStandby(bool enabled) async {
    setFlag('bg_standby', enabled);
    try {
      await _bg.invokeMethod(enabled ? 'start' : 'stop');
    } catch (_) {}
  }

  // ---- profile ----
  Future<void> updateProfile({String? name, Uint8List? avatar, String? about, bool clearAvatar = false}) async {
    if (name != null && name.trim().isNotEmpty) {
      displayName = name.trim();
      await SecureStore.saveDisplayName(displayName);
      await cm.updateDisplayName(displayName);
    }
    if (clearAvatar) {
      this.avatar = null;
      db.kvSet('avatar', '');
    }
    if (avatar != null) {
      this.avatar = avatar;
      db.kvSet('avatar', Crypto.b64e(avatar));
    }
    if (about != null) {
      this.about = about;
      db.kvSet('about', about);
    }
    messages.broadcastProfile();
    notify();
  }

  Contact? contact(String uid) => db.contact(uid);
  String nameOf(String uid) =>
      uid == identity.userId ? 'You' : (db.contact(uid)?.name ?? uid.substring(0, 8));
  Uint8List? avatarOf(String uid) => uid == identity.userId ? avatar : db.contact(uid)?.avatar;

  /// Recovery key = base32 of the 32-byte identity seed (52 chars), grouped for readability.
  Future<String> recoveryKey() async {
    final s = Crypto.b32NoPad((await SecureStore.seed())!);
    return [for (var i = 0; i < s.length; i += 4) s.substring(i, (i + 4).clamp(0, s.length))].join('-');
  }

  static Uint8List? parseRecoveryKey(String key) {
    const alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final clean = key.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');
    if (clean.length != 52) return null;
    final out = <int>[];
    int bits = 0, value = 0;
    for (final ch in clean.split('')) {
      value = (value << 5) | alpha.indexOf(ch);
      bits += 5;
      if (bits >= 8) {
        out.add((value >> (bits - 8)) & 0xff);
        bits -= 8;
      }
    }
    return out.length >= 32 ? Uint8List.fromList(out.sublist(0, 32)) : null;
  }

  Future<void> wipeEverything() async {
    try {
      await _bg.invokeMethod('stop');
    } catch (_) {}
    await cm.stop();
    db.close();
    await AppDb.wipeFiles();
    await MediaStore.wipeAll();
    await SecureStore.wipe();
    _i = null;
  }

  @override
  void dispose() {
    _housekeeping?.cancel();
    super.dispose();
  }
}
