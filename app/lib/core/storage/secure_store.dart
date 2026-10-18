import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../crypto/crypto.dart';

/// Keys live in Android Keystore / iOS Keychain (Secure Enclave-backed where available).
class SecureStore {
  static const _st = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  static const _kSeed = 'identity_seed', _kDb = 'db_key', _kName = 'display_name', _kLock = 'app_lock';

  static Future<Uint8List?> seed() async {
    final s = await _st.read(key: _kSeed);
    return s == null ? null : Crypto.b64d(s);
  }
  static Future<void> saveSeed(Uint8List seed) => _st.write(key: _kSeed, value: Crypto.b64e(seed));

  static Future<Uint8List> dbKey() async {
    final s = await _st.read(key: _kDb);
    if (s != null) return Crypto.b64d(s);
    final k = Crypto.I.random(32);
    await _st.write(key: _kDb, value: Crypto.b64e(k));
    return k;
  }

  static Future<String?> displayName() => _st.read(key: _kName);
  static Future<void> saveDisplayName(String n) => _st.write(key: _kName, value: n);

  static Future<bool> appLockEnabled() async => (await _st.read(key: _kLock)) == '1';
  static Future<void> setAppLock(bool v) => _st.write(key: _kLock, value: v ? '1' : '0');

  static Future<void> wipe() => _st.deleteAll();
}
