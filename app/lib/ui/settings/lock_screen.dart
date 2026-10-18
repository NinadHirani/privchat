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
        localizedReason: 'Unlock PrivChat',
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
            const Icon(Icons.lock, size: 72, color: AppTheme.teal),
            const SizedBox(height: 16),
            const Text('PrivChat is locked', style: TextStyle(fontSize: 20)),
            if (_err != null) Padding(padding: const EdgeInsets.all(12), child: Text(_err!, textAlign: TextAlign.center)),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: _unlock, icon: const Icon(Icons.fingerprint), label: const Text('Unlock')),
          ]),
        ),
      );
}
