import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/auth_config.dart';
import '../../core/services/app_core.dart';
import '../../core/services/auth_helpers.dart';
import '../../core/services/firebase_status.dart';
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
  final _email = TextEditingController();
  final _password = TextEditingController();

  int _step = 0; // 0: Welcome slides, 1: Auth choice / Phone, 2: OTP, 3: Profile setup, 4: Permissions
  int _slidePage = 0;
  bool _busy = false;
  bool _showPhoneInput = false;
  bool _showEmailInput = false;

  String _confirmedPhone = '';
  String? _googleEmail;
  String? _photoUrl;
  String? _verificationId;
  int? _resendToken;
  bool _notifGranted = false;
  bool _callGranted = false;

  Future<void> _signInWithGoogle() async {
    if (_busy) return;
    if (!FirebaseStatus.ready) {
      return toast(context, kSignInUnavailableMessage);
    }
    setState(() => _busy = true);
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(serverClientId: kGoogleWebClientId);
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _busy = false);
        return; // user cancelled
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      final fbUser = userCred.user;

      setState(() {
        _googleEmail = fbUser?.email ?? googleUser.email;
        _photoUrl = fbUser?.photoURL ?? googleUser.photoUrl;
        if (googleUser.displayName != null && googleUser.displayName!.isNotEmpty) {
          _name.text = googleUser.displayName!;
        }
        _busy = false;
        _step = 3; // jump straight to profile setup with name/avatar pre-filled
      });

      if (mounted) {
        toast(context, 'Signed in as ${_googleEmail ?? 'Google user'}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        // A user-initiated cancellation is not an error: return quietly.
        if (!isAuthCancelled(e)) {
          toast(context, 'Google Sign-In failed: ${friendlyAuthError(e)}');
        }
      }
    }
  }

  Future<void> _requestOtp({bool isResend = false}) async {
    if (_busy) return;
    if (!FirebaseStatus.ready) {
      return toast(context, kSignInUnavailableMessage);
    }
    // Normalize loose input (spaces, hyphens, missing +) into E.164 before
    // it reaches Firebase or is stored as the user's directory phone.
    final formatted = normalizeE164(_phone.text);
    if (formatted == null) {
      return toast(context, 'Enter a valid phone number with country code, e.g. +91 9876543210');
    }
    setState(() {
      _busy = true;
      _confirmedPhone = formatted;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _confirmedPhone,
        timeout: const Duration(seconds: 60),
        forceResendingToken: isResend ? _resendToken : null,
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            await FirebaseAuth.instance.signInWithCredential(credential);
            if (mounted) {
              setState(() {
                _busy = false;
                _step = 3; // move to profile setup
              });
              toast(context, 'Phone verified automatically!');
            }
          } catch (e) {
            debugPrint('Auto-verification sign-in failed: $e');
            if (mounted) {
              setState(() => _busy = false);
              toast(context, 'Automatic verification failed: ${friendlyAuthError(e)}');
            }
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('FirebaseAuthException during phone verify [${e.code}]: ${e.message}');
          if (mounted) {
            setState(() => _busy = false);
            toast(context, 'Verification failed: ${friendlyAuthError(e)}');
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _resendToken = resendToken;
              _busy = false;
              _step = 2; // move to OTP step
            });
            toast(context, 'Verification code sent to $_confirmedPhone');
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'Error requesting code: ${friendlyAuthError(e)}');
      }
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
    if (_verificationId == null) {
      return toast(context, 'Verification session expired. Please request a new code.');
    }
    setState(() => _busy = true);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      if (mounted) {
        setState(() {
          _busy = false;
          _step = 3; // move to profile setup
        });
        toast(context, 'Phone number verified successfully!');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, friendlyAuthError(e));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'Verification failed: ${friendlyAuthError(e)}');
      }
    }
  }

  Future<void> _signInWithEmail({String? dummyEmail, String? dummyPass}) async {
    if (_busy) return;
    final email = (dummyEmail ?? _email.text).trim().toLowerCase();
    final password = (dummyPass ?? _password.text).trim().isNotEmpty
        ? (dummyPass ?? _password.text).trim()
        : 'Password123!';

    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      return toast(context, 'Please enter a valid email address');
    }

    setState(() => _busy = true);

    try {
      UserCredential? userCred;
      if (FirebaseStatus.ready) {
        try {
          userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
        } on FirebaseAuthException catch (e) {
          if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
            try {
              userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
                email: email,
                password: password,
              );
            } catch (createErr) {
              debugPrint('Create email user failed: $createErr');
            }
          } else {
            debugPrint('FirebaseAuth email notice [${e.code}]: ${e.message}');
          }
        } catch (e) {
          debugPrint('Firebase email auth general notice: $e');
        }
      }

      final fbUser = userCred?.user;
      setState(() {
        _googleEmail = fbUser?.email ?? email;
        _photoUrl = fbUser?.photoURL;
        if (_name.text.trim().isEmpty) {
          final prefix = email.split('@').first;
          _name.text = prefix.isNotEmpty
              ? prefix[0].toUpperCase() + (prefix.length > 1 ? prefix.substring(1) : '')
              : 'User';
        }
        _busy = false;
        _step = 3; // jump straight to profile setup
      });

      if (mounted) {
        toast(context, 'Signed in as $_googleEmail');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'Sign-in failed: ${friendlyAuthError(e)}');
      }
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
      await AppCore.boot(
        newName: n,
        phone: _confirmedPhone,
        email: _googleEmail,
        photoUrl: _photoUrl,
      );
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
        return _buildAuthChoiceStep();
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
      _info('assets/icon/app_icon.png', 'Private by design',
          'End-to-end encrypted with libsodium. Serverless on LAN, with zero-knowledge relay over the internet. Nobody can read your messages or listen to your calls.'),
      _info(Icons.contacts, 'Talk to Google Contacts',
          'Sign in with Google or verify your phone number. PrivChat automatically matches contacts who are on PrivChat and lets you invite others with 1 tap.'),
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

  Widget _buildAuthChoiceStep() {
    return SingleChildScrollView(
      key: const ValueKey('auth_choice'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          const Center(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: AppTheme.mustardBrown,
              child: Icon(Icons.lock_person_outlined, size: 40, color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Connect & Discover',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Connect with Google, phone, or dummy email so your contacts can message you securely. Your data stays end-to-end encrypted.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 24),

          if (!FirebaseStatus.ready) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                kSignInUnavailableMessage,
                style: TextStyle(fontSize: 12.5, height: 1.35),
              ),
            ),
          ],

          if (!_showPhoneInput && !_showEmailInput) ...[
            // Google Sign-In Button
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                side: BorderSide(color: Colors.grey.withOpacity(0.35)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: Theme.of(context).cardColor,
              ),
              onPressed: (_busy || !FirebaseStatus.ready) ? null : _signInWithGoogle,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.network(
                    'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                    width: 20,
                    height: 20,
                    errorBuilder: (_, __, ___) => const Icon(Icons.account_circle, color: Colors.redAccent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Continue with Google',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Phone authentication button
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.mustardBrown,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.phone_android, size: 20),
              label: const Text('Use Phone Number'),
              onPressed: !FirebaseStatus.ready
                  ? null
                  : () => setState(() {
                        _showPhoneInput = true;
                        _showEmailInput = false;
                      }),
            ),

            const SizedBox(height: 12),

            // Email / Dummy mail authentication button
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                side: BorderSide(color: AppTheme.mustardBrown.withOpacity(0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.mail_outline, size: 20, color: AppTheme.mustardBrown),
              label: const Text('Use Email / Dummy Mail', style: TextStyle(color: AppTheme.mustardBrown)),
              onPressed: () => setState(() {
                _showEmailInput = true;
                _showPhoneInput = false;
              }),
            ),

            const SizedBox(height: 12),

            // Quick 1-tap dummy login pill
            Center(
              child: ActionChip(
                avatar: const Icon(Icons.bolt, size: 16, color: Colors.amber),
                label: const Text('1-Tap Dummy Login (test@privchat.app)', style: TextStyle(fontSize: 12)),
                onPressed: _busy ? null : () => _signInWithEmail(dummyEmail: 'test@privchat.app', dummyPass: 'Password123!'),
              ),
            ),
          ] else if (_showPhoneInput) ...[
            // Phone input flow
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[+\d\s\-\(\)]'))],
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: '+91 98765 43210',
                prefixIcon: Icon(Icons.dialpad),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _requestOtp(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.mustardBrown,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _busy ? null : _requestOtp,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Send Verification Code'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _showPhoneInput = false),
              child: const Text('← Other sign-in options'),
            ),
          ] else if (_showEmailInput) ...[
            // Email input flow
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Email address',
                hintText: 'e.g. test@privchat.app or user@mail.com',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password (Optional)',
                hintText: 'Default: Password123!',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _signInWithEmail(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.mustardBrown,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _busy ? null : () => _signInWithEmail(),
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Continue with Email'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.flash_on, size: 16),
              label: const Text('Fill & Sign in with test@privchat.app'),
              onPressed: _busy ? null : () => _signInWithEmail(dummyEmail: 'test@privchat.app', dummyPass: 'Password123!'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _showEmailInput = false),
              child: const Text('← Other sign-in options'),
            ),
          ],

          const SizedBox(height: 24),
          const Divider(),
          TextButton(
            onPressed: _busy ? null : _skipPhone,
            child: const Text('Skip (Use offline identity only)', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: _busy ? null : _restore,
            child: const Text('Restore from recovery key', style: TextStyle(fontSize: 13)),
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
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _busy ? null : () => _requestOtp(isResend: true),
                child: const Text('Resend code'),
              ),
              const Text('•', style: TextStyle(color: Colors.grey)),
              TextButton(
                onPressed: _busy ? null : () => setState(() => _step = 1),
                child: const Text('Wrong number? Change'),
              ),
            ],
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

  Widget _buildProfileStep() {
    return Padding(
      key: const ValueKey('profile'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          Center(
            child: _photoUrl != null && _photoUrl!.isNotEmpty
                ? CircleAvatar(
                    radius: 38,
                    backgroundImage: NetworkImage(_photoUrl!),
                  )
                : const CircleAvatar(
                    radius: 38,
                    backgroundColor: AppTheme.mustardBrown,
                    child: Icon(Icons.person, size: 44, color: Colors.white),
                  ),
          ),
          const SizedBox(height: 16),
          const Text('Your Profile', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            _googleEmail != null ? 'Signed in with $_googleEmail' : 'Choose the name your contacts will see.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
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

  Widget _info(dynamic iconOrAsset, String title, String body) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (iconOrAsset is String)
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(iconOrAsset, width: 104, height: 104),
              )
            else if (iconOrAsset is IconData)
              Icon(iconOrAsset, size: 96, color: AppTheme.mustardBrown),
            const SizedBox(height: 32),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.4)),
          ],
        ),
      );
}
