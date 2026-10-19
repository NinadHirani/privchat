import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

/// Normalizes loose phone input into E.164 (+<country code><subscriber number>).
///
/// Accepts spaces, hyphens, parentheses and dots; adds a leading `+` when it is
/// missing. Returns null when the input cannot be a valid E.164 number, so
/// callers can reject it before it reaches Firebase or the directory.
String? normalizeE164(String raw) {
  var cleaned = raw.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
  cleaned = cleaned.replaceAll(RegExp(r'[^\d+]'), '');
  if (cleaned.isEmpty) return null;
  if (!cleaned.startsWith('+')) cleaned = '+$cleaned';
  final e164 = RegExp(r'^\+[1-9]\d{6,14}$');
  if (!e164.hasMatch(cleaned)) return null;
  return cleaned;
}

/// True when [error] is a user-initiated cancellation of a sign-in flow
/// (Android and iOS surface cancellations through different error codes).
bool isAuthCancelled(Object error) {
  if (error is PlatformException) {
    if (error.code == 'sign_in_canceled' || error.code == 'canceled') return true;
    final details = error.details?.toString() ?? '';
    if (error.code == 'sign_in_failed' &&
        (details.contains('12501') ||
            details.toUpperCase().contains('SIGN_IN_CANCELLED'))) {
      return true;
    }
  }
  if (error is FirebaseAuthException && error.code == 'user-cancelled') return true;
  return false;
}

/// Maps low-level auth errors to short, actionable user-facing messages.
String friendlyAuthError(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-verification-code':
        return 'That code is not correct. Check the SMS and try again.';
      case 'code-expired':
      case 'session-expired':
        return 'The verification session expired. Please request a new code.';
      case 'invalid-phone-number':
        return 'That phone number is not valid. Include the country code, e.g. +91 9876543210.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes before trying again.';
      case 'quota-exceeded':
        return 'The SMS quota for this project is exhausted. Try again later.';
      case 'network-request-failed':
        return 'Network problem. Check your internet connection and try again.';
      case 'operation-not-allowed':
        return 'This sign-in method is disabled in the Firebase console.';
      case 'configuration-not-found':
        return 'Sign-in is not configured for this app yet. The project owner needs to enable it in the Firebase console.';
      case 'app-not-authorized':
        return 'This app is not authorized to use Firebase Authentication with the given key.';
      case 'invalid-credential':
        return 'Sign-in was rejected. The app may need its signing fingerprint registered in the Firebase console.';
      case 'credential-already-in-use':
        return 'That account is already linked to another user.';
      case 'provider-already-linked':
        return 'This sign-in method is already linked to your account.';
      case 'user-mismatch':
      case 'requires-recent-login':
        return 'Please sign in again and retry.';
      case 'email-already-in-use':
        return 'That account is already registered. Sign in with it instead.';
    }
    final message = error.message;
    if (message != null && message.trim().isNotEmpty) return message;
    return error.code;
  }
  if (error is PlatformException) {
    switch (error.code) {
      case 'network_error':
        return 'Network problem. Check your internet connection and try again.';
      case 'sign_in_failed':
        final details = error.details?.toString() ?? '';
        if (details.toUpperCase().contains('DEVELOPER_ERROR') ||
            details.contains('ApiException: 10')) {
          return 'Google Sign-In is misconfigured for this build. The app needs its signing fingerprint registered in the Firebase console.';
        }
        return 'Google Sign-In failed. Please try again.';
    }
    return error.message ?? error.code;
  }
  return error.toString();
}
