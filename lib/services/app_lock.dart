import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

enum AuthResult {
  success,

  /// Cancelled, wrong, locked out, or the prompt couldn't be shown.
  failed,

  /// The device has no screen lock or fingerprint to check against.
  unavailable,
}

/// Asks for the device's own fingerprint, face, PIN, pattern or password.
/// The app keeps no secret of its own.
abstract class Authenticator {
  Future<AuthResult> authenticate(String reason);
}

class DeviceAuthenticator implements Authenticator {
  DeviceAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<AuthResult> authenticate(String reason) async {
    try {
      if (!await _auth.isDeviceSupported()) return AuthResult.unavailable;
      final ok = await _auth.authenticate(localizedReason: reason);
      return ok ? AuthResult.success : AuthResult.failed;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.noBiometricsEnrolled => AuthResult.unavailable,
        _ => AuthResult.failed,
      };
    } on MissingPluginException {
      return AuthResult.unavailable;
    } on PlatformException {
      return AuthResult.failed;
    }
  }
}

const _privacy = MethodChannel('lift_flow/privacy');

/// Hides the app from the recents thumbnail (see MainActivity.kt).
Future<void> setRecentsHidden(bool hidden) async {
  if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) return;
  try {
    await _privacy.invokeMethod<void>('setRecentsHidden', hidden);
  } on PlatformException catch (e) {
    debugPrint('Recents privacy unavailable: $e');
  } on MissingPluginException catch (e) {
    debugPrint('Recents privacy unavailable: $e');
  }
}
