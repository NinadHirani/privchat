import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/crypto/crypto.dart';
import '../../core/services/app_core.dart';
import '../../core/services/directory_service.dart';
import '../../core/storage/media_store.dart';
import '../../core/storage/secure_store.dart';
import '../media/media_utils.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'appearance_screen.dart';
import 'network_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final core = AppCore.I;
  bool _lock = false;
  int _vault = 0;

  @override
  void initState() {
    super.initState();
    SecureStore.appLockEnabled().then((v) => setState(() => _lock = v));
    MediaStore.vaultSize().then((v) => setState(() => _vault = v));
  }

  Future<void> _toggleLock(bool v) async {
    if (v) {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) {
        if (mounted) toast(context, 'Set a screen lock / fingerprint on your phone first');
        return;
      }
      final ok = await auth.authenticate(localizedReason: 'Enable app lock');
      if (!ok) return;
    }
    await SecureStore.setAppLock(v);
    setState(() => _lock = v);
  }

  Future<void> _showRecovery() async {
    final ok = await confirm(context, 'Show recovery key?',
        'Anyone with this key can become you. Write it on paper. Never screenshot it or send it to anyone.', ok: 'Show');
    if (!ok || !mounted) return;
    final key = await core.recoveryKey();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Your recovery key'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SelectableText(key, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'monospace', fontSize: 16, height: 1.6)),
          const SizedBox(height: 12),
          const Text('This restores your identity (your contacts will recognise you) on a new phone. '
              'Messages are NOT recoverable — they only ever existed on your devices.', style: TextStyle(fontSize: 12.5)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
      ),
    );
  }

  Future<void> _linkGoogle() async {
    try {
      final googleSignIn = GoogleSignIn();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return;
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      final email = userCred.user?.email ?? googleUser.email;
      final photo = userCred.user?.photoURL ?? googleUser.photoUrl;

      core.db.kvSet('user_email', email);
      if (photo != null && photo.isNotEmpty) {
        core.db.kvSet('user_photo_url', photo);
      }

      await DirectoryService.I.publishIdentity(
        userId: core.identity.userId,
        edPublicKey: Crypto.b64e(core.identity.edPk),
        displayName: core.displayName,
        phone: core.db.kvGet('user_phone'),
        email: email,
        photoUrl: photo,
      );

      if (mounted) {
        setState(() {});
        toast(context, 'Connected Google account: $email');
      }
    } catch (e) {
      if (mounted) toast(context, 'Failed to connect Google: $e');
    }
  }

  Future<void> _linkPhone() async {
    final current = core.db.kvGet('user_phone') ?? '';
    final ph = await promptText(context, 'Enter Phone Number', initial: current, hint: '+1 234 567 8900');
    if (ph == null) return;
    final cleaned = ph.trim();
    if (cleaned.isEmpty) {
      core.db.kvSet('user_phone', '');
      if (mounted) setState(() {});
      return;
    }
    core.db.kvSet('user_phone', cleaned);
    await DirectoryService.I.publishIdentity(
      userId: core.identity.userId,
      edPublicKey: Crypto.b64e(core.identity.edPk),
      displayName: core.displayName,
      phone: cleaned,
      email: core.db.kvGet('user_email'),
      photoUrl: core.db.kvGet('user_photo_url'),
    );
    if (mounted) {
      setState(() {});
      toast(context, 'Phone number updated');
    }
  }

  Future<void> _wipe() async {
    if (!await confirm(context, 'Erase everything?',
        'Your identity, contacts, messages and media will be permanently destroyed on this phone. This cannot be undone.',
        ok: 'ERASE', danger: true)) return;
    await core.wipeEverything();
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: core,
        builder: (context, _) {
          final userPhone = core.db.kvGet('user_phone');
          final userEmail = core.db.kvGet('user_email');
          return Scaffold(
            appBar: AppBar(title: const Text('Settings')),
            body: ListView(children: [
              ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: GestureDetector(
                  onTap: () async {
                    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
                    if (x == null) return;
                    await core.updateProfile(avatar: await MediaUtils.makeAvatar(x.path));
                  },
                  child: Avatar(name: core.displayName, bytes: core.avatar, radius: 32),
                ),
                title: Text(core.displayName, style: const TextStyle(fontSize: 20)),
                subtitle: Text(core.about),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final n = await promptText(context, 'Your name', initial: core.displayName, maxLength: 40);
                  if (n != null && n.isNotEmpty) await core.updateProfile(name: n);
                  if (!context.mounted) return;
                  final a = await promptText(context, 'About', initial: core.about, maxLength: 140);
                  if (a != null) await core.updateProfile(about: a);
                },
              ),
              if (core.avatar != null)
                TextButton(onPressed: () => core.updateProfile(clearAvatar: true), child: const Text('Remove profile photo')),
              const Divider(),
              _section('Account & Discovery'),
              ListTile(
                leading: const Icon(Icons.account_circle_outlined, color: AppTheme.mustardBrown),
                title: const Text('Google Account'),
                subtitle: Text(userEmail != null && userEmail.isNotEmpty ? userEmail : 'Not linked (tap to sign in)'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _linkGoogle,
              ),
              ListTile(
                leading: const Icon(Icons.phone_android, color: AppTheme.mustardBrown),
                title: const Text('Phone Number'),
                subtitle: Text(userPhone != null && userPhone.isNotEmpty ? userPhone : 'Not linked (tap to add)'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _linkPhone,
              ),
              const Divider(),
              _section('Appearance & Customization'),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Chat Appearance & Wallpapers'),
              subtitle: const Text('Cadet grey, mustard bubbles & custom wallpapers'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppearanceScreen())),
            ),
            const Divider(),
            _section('Privacy'),
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: const Text('App lock'),
              subtitle: const Text('Require fingerprint / face / PIN to open'),
              value: _lock,
              onChanged: _toggleLock,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.done_all),
              title: const Text('Read receipts'),
              subtitle: const Text('If off, you won\'t send or see blue ticks for status views'),
              value: core.readReceipts,
              onChanged: (v) => core.setFlag('read_receipts', v),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.shield_outlined),
              title: const Text('Only contacts can message me'),
              subtitle: const Text('Silently ignore messages and group invites from nearby strangers'),
              value: core.contactsOnly,
              onChanged: (v) => core.setFlag('contacts_only', v),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_off_outlined),
              title: const Text('Hide notification content'),
              subtitle: const Text('Show "New message" instead of sender and text'),
              value: core.flag('hide_previews'),
              onChanged: (v) {
                core.setFlag('hide_previews', v);
                core.notifications.hidePreview = v;
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Hide my status from…'),
              subtitle: Text('${core.status.hiddenFrom.length} contacts'),
              onTap: _statusPrivacy,
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Blocked contacts'),
              subtitle: Text('${core.db.contacts().where((c) => c.blocked).length}'),
              onTap: _blocked,
            ),
            const Divider(),
            _section('Security'),
            ListTile(leading: const Icon(Icons.key), title: const Text('Recovery key'), subtitle: const Text('Restore your identity on a new phone'), onTap: _showRecovery),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('My Pritoy ID'),
              subtitle: Text(core.identity.userId, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
            const Divider(),
            _section('Connectivity'),
            SwitchListTile(
              secondary: const Icon(Icons.bolt_outlined),
              title: const Text('Background standby'),
              subtitle: const Text('Keep listening for messages and calls with near-zero battery usage'),
              value: core.backgroundStandby,
              onChanged: (v) => core.setBackgroundStandby(v),
            ),
            ListTile(
              leading: const Icon(Icons.wifi_tethering),
              title: const Text('Network & nearby devices'),
              subtitle: Text('${core.cm.online.length} connected · ${core.db.outboxCount()} messages waiting'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NetworkScreen())),
            ),
            const Divider(),
            _section('Storage'),
            ListTile(leading: const Icon(Icons.sd_storage_outlined), title: const Text('Encrypted media'), subtitle: Text(fmtBytes(_vault))),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('How Pritoy protects you'),
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'Pritoy',
                applicationVersion: '1.0.0',
                applicationIcon: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset('assets/icon/app_icon.png', width: 48, height: 48),
                ),
                children: const [
                  Text('• No servers, accounts, phone numbers or analytics.\n'
                      '• Devices talk directly over Wi-Fi, hotspot, Wi-Fi Direct (Android) or Multipeer (iPhone).\n'
                      '• Messages: X25519 + Ed25519 authenticated key exchange, per-message keys (forward secrecy), XChaCha20-Poly1305.\n'
                      '• Groups: signed membership + sender keys, rotated when someone leaves.\n'
                      '• Calls: WebRTC (DTLS-SRTP) with keys authenticated through the encrypted chat channel.\n'
                      '• On-device: SQLCipher database, encrypted media vault, keys in Keystore/Keychain.\n'
                      '• Photos are re-encoded to strip GPS/EXIF metadata before sending.'),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Erase everything', style: TextStyle(color: Colors.red)),
              onTap: _wipe,
            ),
            const SizedBox(height: 32),
          ]),
        ),
      );

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(t, style: const TextStyle(color: AppTheme.teal, fontWeight: FontWeight.w600)),
      );

  Future<void> _statusPrivacy() async {
    final sel = {...core.status.hiddenFrom};
    final contacts = core.db.contacts().where((c) => c.added > 0).toList();
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Hide status from'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(shrinkWrap: true, children: [
              for (final ct in contacts)
                CheckboxListTile(
                  value: sel.contains(ct.userId),
                  title: Text(ct.name),
                  onChanged: (v) => set(() => v! ? sel.add(ct.userId) : sel.remove(ct.userId)),
                ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
        ),
      ),
    );
    core.status.setHiddenFrom(sel);
  }

  void _blocked() {
    showModalBottomSheet(
      context: context,
      builder: (c) => ListenableBuilder(
        listenable: core,
        builder: (_, __) {
          final b = core.db.contacts().where((x) => x.blocked).toList();
          return ListView(children: [
            const ListTile(title: Text('Blocked', style: TextStyle(fontWeight: FontWeight.bold))),
            if (b.isEmpty) const ListTile(title: Text('Nobody blocked')),
            for (final x in b)
              ListTile(
                leading: Avatar(name: x.name, bytes: x.avatar),
                title: Text(x.name),
                trailing: TextButton(onPressed: () { core.db.setBlocked(x.userId, false); core.notify(); }, child: const Text('Unblock')),
              ),
          ]);
        },
      ),
    );
  }
}
