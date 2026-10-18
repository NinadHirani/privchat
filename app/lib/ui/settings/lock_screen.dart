import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../theme.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _auth = LocalAuthentication();
  String? _err;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock Pritoy',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
      if (ok) widget.onUnlocked();
    } catch (e) {
      setState(() => _err = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset('assets/icon/app_icon.png', width: 80, height: 80),
            ),
            const SizedBox(height: 20),
            const Text('Pritoy is locked', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if (_err != null) Padding(padding: const EdgeInsets.all(12), child: Text(_err!, textAlign: TextAlign.center)),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: _unlock, icon: const Icon(Icons.fingerprint), label: const Text('Unlock')),
          ]),
        ),
      );
}
