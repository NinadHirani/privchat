import 'package:flutter/material.dart';
import '../../core/services/app_core.dart';
import '../theme.dart';
import '../widgets/common.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController();
  int _page = 0;
  bool _busy = false;

  Future<void> _create() async {
    final n = _name.text.trim();
    if (n.isEmpty) return toast(context, 'Enter a name your friends will recognise');
    setState(() => _busy = true);
    try {
      await AppCore.boot(newName: n);
      widget.onDone();
    } catch (e) {
      if (mounted) toast(context, 'Setup failed: $e');
      setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final key = await promptText(context, 'Restore with recovery key', hint: 'XXXX-XXXX-…', maxLength: 80);
    if (key == null || key.isEmpty) return;
    final seed = AppCore.parseRecoveryKey(key);
    if (seed == null) {
      if (mounted) toast(context, 'That recovery key is not valid');
      return;
    }
    final name = await promptText(context, 'Your name');
    if (name == null || name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await AppCore.boot(newName: name, restoreSeed: seed);
      widget.onDone();
    } catch (e) {
      if (mounted) toast(context, 'Restore failed: $e');
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _info(Icons.lock_outline, 'Private by design',
          'No phone number. No email. No account. No servers.\nYour identity is a key that is created on this phone and never leaves it.'),
      _info(Icons.wifi_tethering, 'Works without internet',
          'Chat, share photos, videos, documents and location, and make voice & video calls with anyone on the same Wi-Fi, a phone hotspot, or Wi-Fi Direct — even with no internet at all.'),
      _info(Icons.verified_user_outlined, 'End-to-end encrypted',
          'Everything is encrypted with modern cryptography (X25519, Ed25519, XChaCha20-Poly1305). Scan a friend\'s QR code in person to verify nobody is in the middle.'),
    ];
    return Scaffold(
      body: SafeArea(
        child: _page < pages.length
            ? Column(children: [
                Expanded(child: pages[_page]),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i <= pages.length; i++)
                    Container(
                      margin: const EdgeInsets.all(4), width: 8, height: 8,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? AppTheme.teal : Colors.grey.shade400),
                    ),
                ]),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: () => setState(() => _page++), child: const Text('Next')),
                  ),
                ),
              ])
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 40),
                  const Icon(Icons.person_outline, size: 72, color: AppTheme.teal),
                  const SizedBox(height: 16),
                  const Text('Your profile', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Only shown to people you add.', textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _name, maxLength: 40, autofocus: true,
                    decoration: const InputDecoration(labelText: 'Your name', border: OutlineInputBorder()),
                    onSubmitted: (_) => _create(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _create,
                    child: _busy
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Create my private identity'),
                  ),
                  const Spacer(),
                  TextButton(onPressed: _busy ? null : _restore, child: const Text('I have a recovery key')),
                ]),
              ),
      ),
    );
  }

  Widget _info(IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 96, color: AppTheme.teal),
          const SizedBox(height: 32),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.4)),
        ]),
      );
}
