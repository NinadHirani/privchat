import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

/// Tracks whether Firebase finished initializing at startup.
///
/// Pritoy works fully offline with a local identity, so a Firebase failure
/// must never block launch. Sign-in flows (Google and phone) read [ready] and
/// degrade gracefully when Firebase is unavailable instead of erroring out at
/// the button tap.
class FirebaseStatus {
  static bool ready = false;
  static String? error;

  static Future<void> ensureInitialized() async {
    if (ready) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      ready = true;
      error = null;
    } catch (e) {
      error = e.toString();
      debugPrint(
        'Firebase initialization failed; Google/phone sign-in will be '
        'unavailable this session. Offline identity mode still works. Error: $e',
      );
    }
  }
}
