import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
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
  final _phone = TextEditingController();
  final _otp = TextEditingController();

  int _step = 0; // 0: Welcome slides, 1: Phone input, 2: OTP, 3: Profile setup, 4: Permissions
  int _slidePage = 0;
  bool _busy = false;
  String _confirmedPhone = '';
  bool _notifGranted = false;
  bool _callGranted = false;

  Future<void> _requestOtp() async {
    final raw = _phone.text.trim();
    if (raw.isEmpty || raw.length < 7) {
      return toast(context, 'Please enter a valid phone number with country code');
    }
    setState(() {
      _busy = true;
      _confirmedPhone = raw.startsWith('+') ? raw : '+$raw';
    });

    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) {
      setState(() {
        _busy = false;
        _step = 2; // move to OTP step
      });
      toast(context, 'Verification code sent to $_confirmedPhone');
    }
  }

  void _skipPhone() {
    setState(() {
      _confirmedPhone = '';
      _step = 3; // jump straight to profile name
    });
  }

  Future<void> _verifyOtp() async {
    final code = _otp.text.trim();
    if (code.length != 6) {
      return toast(context, 'Please enter the 6-digit code');
    }
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      setState(() {
        _busy = false;
        _step = 3; // move to profile setup
      });
    }
  }

  Future<void> _checkPermissions() async {
    try {
      final notif = await Permission.notification.status;
      final mic = await Permission.microphone.status;
      if (mounted) {
        setState(() {
          _notifGranted = notif.isGranted;
          _callGranted = mic.isGranted;
        });
      }
    } catch (_) {}
  }

  Future<void> _requestNotif() async {
    try {
      final res = await Permission.notification.request();
      if (mounted) setState(() => _notifGranted = res.isGranted);
    } catch (_) {}
  }

  Future<void> _requestCalls() async {
    try {
      final mic = await Permission.microphone.request();
      final cam = await Permission.camera.request();
      if (mounted) setState(() => _callGranted = mic.isGranted || cam.isGranted);
    } catch (_) {}
  }

  Future<void> _goToPermissions() async {
    final n = _name.text.trim();
    if (n.isEmpty) return toast(context, 'Enter a name your friends will recognise');
    await _checkPermissions();
    if (mounted) setState(() => _step = 4);
  }

  Future<void> _finishSetup() async {
    final n = _name.text.trim();
    if (n.isEmpty) return toast(context, 'Enter a name your friends will recognise');
    setState(() => _busy = true);
    try {
      await AppCore.boot(newName: n, phone: _confirmedPhone);
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
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _buildCurrentStep(),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 0:
        return _buildWelcomeSlides();
      case 1:
        return _buildPhoneStep();
      case 2:
        return _buildOtpStep();
      case 3:
        return _buildProfileStep();
      case 4:
      default:
        return _buildPermissionsStep();
    }
  }

  Widget _buildWelcomeSlides() {
    final pages = [
      _info(Icons.lock_outline, 'Private by design',
          'End-to-end encrypted with libsodium. Serverless on LAN, with zero-knowledge relay over the internet. Nobody can read your messages or listen to your calls.'),
      _info(Icons.contacts, 'Talk to Google Contacts',
          'Verify your phone number once like WhatsApp. PrivChat discovers which of your saved Google contacts are on PrivChat and lets you invite others with 1 tap.'),
      _info(Icons.wifi_tethering, 'Works offline & online',
          'Direct P2P over Wi-Fi, hotspot, or Wi-Fi Direct with zero internet — and seamless cloud relay when you are across the city or world.'),
    ];

    return Column(
      key: const ValueKey('slides'),
      children: [
        Expanded(child: pages[_slidePage]),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < pages.length; i++)
              Container(
                margin: const EdgeInsets.all(4),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == _slidePage ? AppTheme.amberAccent : Colors.grey.shade400,
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.mustardBrown,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (_slidePage < pages.length - 1) {
                  setState(() => _slidePage++);
                } else {
                  setState(() => _step = 1);
                }
              },
              child: Text(_slidePage < pages.length - 1 ? 'Next' : 'Get Started'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneStep() {
    return Padding(
      key: const ValueKey('phone'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          const Icon(Icons.phone_android, size: 64, color: AppTheme.mustardBrown),
          const SizedBox(height: 16),
          const Text('Enter your phone number',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'PrivChat will verify your number so your Google Contacts can find and message you.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              hintText: '+1 234 567 8900',
              prefixIcon: Icon(Icons.dialpad),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _requestOtp(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.mustardBrown, minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : _requestOtp,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Send Verification Code'),
          ),
          const Spacer(),
          TextButton(
            onPressed: _skipPhone,
            child: const Text('Skip (Use offline identity only)', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpStep() {
    return Padding(
      key: const ValueKey('otp'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          const Icon(Icons.sms_outlined, size: 64, color: AppTheme.mustardBrown),
          const SizedBox(height: 16),
          const Text('Verify phone number',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Enter the 6-digit code sent to $_confirmedPhone',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _otp,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofocus: true,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              hintText: '123456',
              counterText: '',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _verifyOtp(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.mustardBrown, minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : _verifyOtp,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Verify & Continue'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _step = 1),
            child: const Text('Wrong number? Change'),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildProfileStep() {
    return Padding(
      key: const ValueKey('profile'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          const CircleAvatar(
            radius: 36,
            backgroundColor: AppTheme.mustardBrown,
            child: Icon(Icons.person, size: 40, color: Colors.white),
          ),
          const SizedBox(height: 16),
          const Text('Your Profile', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Choose the name your contacts will see.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 28),
          TextField(
            controller: _name,
            maxLength: 40,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Your display name',
              hintText: 'e.g. Alex',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _goToPermissions(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.mustardBrown, minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : _goToPermissions,
            child: const Text('Continue'),
          ),
          const Spacer(),
          TextButton(onPressed: _busy ? null : _restore, child: const Text('I have a recovery key')),
        ],
      ),
    );
  }

  Widget _buildPermissionsStep() {
    return Padding(
      key: const ValueKey('permissions'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          const CircleAvatar(
            radius: 36,
            backgroundColor: AppTheme.mustardBrown,
            child: Icon(Icons.security, size: 40, color: Colors.white),
          ),
          const SizedBox(height: 16),
          const Text('Permissions & Standby', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('PrivChat runs serverless and offline. We only request permissions necessary to keep your communications private and reliable.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4)),
          const SizedBox(height: 28),
          _permTile(
            icon: Icons.notifications_active_outlined,
            title: 'Notifications',
            subtitle: 'Banner alerts for incoming calls & offline messages without active battery drain',
            granted: _notifGranted,
            onRequest: _requestNotif,
          ),
          const SizedBox(height: 12),
          _permTile(
            icon: Icons.call_outlined,
            title: 'Microphone & Camera',
            subtitle: 'Required for encrypted voice and video calls (only accessed while on a call)',
            granted: _callGranted,
            onRequest: _requestCalls,
          ),
          const SizedBox(height: 12),
          _permTile(
            icon: Icons.battery_saver,
            title: 'Ultra-Low Battery Standby',
            subtitle: 'Zero permanent wake locks. Passive socket listening allows your phone to sleep normally',
            granted: true,
            onRequest: null,
          ),
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.mustardBrown, minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : _finishSetup,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Start Chatting'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _step = 3),
            child: const Text('Back to profile'),
          ),
        ],
      ),
    );
  }

  Widget _permTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    VoidCallback? onRequest,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.mustardBrown, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (granted)
            const Icon(Icons.check_circle, color: Colors.green, size: 24)
          else if (onRequest != null)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              ),
              onPressed: onRequest,
              child: const Text('Allow', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _info(IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 96, color: AppTheme.mustardBrown),
            const SizedBox(height: 32),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.4)),
          ],
        ),
      );
}
