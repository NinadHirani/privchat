import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/services/app_core.dart';
import 'core/services/call_service.dart';
import 'core/storage/media_store.dart';
import 'core/storage/secure_store.dart';
import 'ui/calls/call_screen.dart';
import 'ui/chats/chat_screen.dart';
import 'ui/home/home_screen.dart';
import 'ui/onboarding/onboarding_screen.dart';
import 'ui/settings/lock_screen.dart';
import 'ui/theme.dart';

final navKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const PrivChatApp());
}

class PrivChatApp extends StatelessWidget {
  const PrivChatApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Pritoy',
        debugShowCheckedModeBanner: false,
        navigatorKey: navKey,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const Bootstrap(),
      );
}

/// Decides: onboarding → (lock) → home. Also owns global call-screen routing and app-lock-on-background.
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> with WidgetsBindingObserver {
  bool _loading = true, _hasIdentity = false, _locked = false;
  String? _error;
  bool _callOpen = false;
  bool _inForeground = true;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      _hasIdentity = await AppCore.hasIdentity();
      if (_hasIdentity) {
        _locked = await SecureStore.appLockEnabled();
        await AppCore.boot();
        _wire();
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _wire() {
    final core = AppCore.I;
    core.calls.addListener(_onCall);
    core.notifications.hidePreview = core.flag('hide_previews');
    core.notifications.onTap = (payload) {
      if (payload.startsWith('d:') || payload.startsWith('g:')) {
        navKey.currentState?.push(MaterialPageRoute(builder: (_) => ChatScreen(convId: payload)));
      } else if (payload.startsWith('call')) {
        _openCallScreen();
      }
    };
    core.notifications.onCallAnswer = (callId) async {
      await core.calls.accept();
      _openCallScreen();
    };
    core.notifications.onCallDecline = (callId) async {
      await core.calls.decline();
    };
  }

  void _openCallScreen() {
    if (!_callOpen && (AppCore.I.calls.busy || AppCore.I.calls.state != CallState.idle)) {
      _callOpen = true;
      navKey.currentState
          ?.push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const CallScreen()))
          .then((_) => _callOpen = false);
    }
  }

  void _onCall() {
    final s = AppCore.I.calls.state;
    // For outgoing calls: always open call screen immediately
    if (s == CallState.outgoing) {
      _openCallScreen();
      return;
    }
    // If call transitioned to active / connecting (e.g. accepted via notification action):
    if (s == CallState.active || s == CallState.connecting) {
      _openCallScreen();
      return;
    }
    // For incoming calls:
    // When other apps are open or PrivChat is in the background, do NOT hijack the screen.
    // The notification banner with 'Answer' and 'Decline' actions will be shown.
    if (s == CallState.incoming && _inForeground) {
      _openCallScreen();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    _inForeground = state == AppLifecycleState.resumed;
    if (!AppCore.ready) return;
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      await MediaStore.wipeCache(); // decrypted temp files never linger
    } else if (state == AppLifecycleState.resumed) {
      final lock = await SecureStore.appLockEnabled();
      final away = _pausedAt == null ? Duration.zero : DateTime.now().difference(_pausedAt!);
      if (lock && away > const Duration(seconds: 30) && !AppCore.I.calls.busy) setState(() => _locked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Startup failed:\n$_error'))));
    }
    if (!_hasIdentity) {
      return OnboardingScreen(onDone: () {
        _wire();
        setState(() => _hasIdentity = true);
      });
    }
    if (_locked) return LockScreen(onUnlocked: () => setState(() => _locked = false));
    return const HomeScreen();
  }
}
