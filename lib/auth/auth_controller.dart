import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../api/hub_api.dart';
import '../api/models.dart';
import '../config.dart';
import '../demo/demo_backend.dart';
import '../notifications/push_notifications.dart';
import '../util/futures.dart';

enum AuthStatus { loading, signedOut, signedIn }

/// Owns the session. Signing in goes through Microsoft in an in-app browser tab;
/// the backend then hands a one-time code back to the app (bound to a PKCE
/// verifier) which is exchanged for a bearer token. Members use Microsoft; Google
/// is only for Gaming Hub managers, for the management pages.
class AuthController extends ChangeNotifier {
  AuthController({FlutterSecureStorage? storage, http.Client? httpClient, PushNotifications? push})
    : _storage = storage ?? const FlutterSecureStorage(),
      push = push ?? PushNotifications() {
    client = ApiClient(baseUrl: apiUrl, onUnauthorized: _handleUnauthorized, httpClient: httpClient);
    api = HubApi(client);
    _liveHttp = client.httpClient;
  }

  static const _tokenKey = 'auth_token';
  static const _microsoftRequired =
      'Log in met je AP Microsoft-account. Inloggen met Google is alleen voor Gaming Hub managers.';

  late final http.Client _liveHttp;

  final FlutterSecureStorage _storage;
  late final ApiClient client;
  late final HubApi api;
  final PushNotifications push;

  AuthStatus status = AuthStatus.loading;
  Profile? profile;
  String? error;
  bool signingIn = false;

  /// True while exploring the app with sample data. Nothing in the demo reaches the backend or is saved on the phone.
  bool isDemo = false;

  /// Only accounts with Microsoft linked can reserve; the backend enforces this too.
  /// Managers who signed in with Google still get the management pages.
  bool canReserve = true;

  Future<void> restore() async {
    client.token = await _storage.read(key: _tokenKey);
    if (client.token == null) return _setSignedOut();

    try {
      // Sessions from before the app became Microsoft-only may belong to a Google account.
      if (!await _mayUseApp()) {
        error = _microsoftRequired;
        await signOut();
        return;
      }
      await refreshProfile();
      unawaited(push.start(api));
    } on ApiException catch (e) {
      // Keep the session when we're just offline; the screens show their own errors.
      if (e.isUnauthorized) return _setSignedOut();
      status = AuthStatus.signedOut;
      error = e.message;
      notifyListeners();
    }
  }

  Future<void> refreshProfile() async {
    profile = await api.profile();
    status = AuthStatus.signedIn;
    error = null;
    notifyListeners();
  }

  Future<void> signIn({bool withGoogle = false}) async {
    if (signingIn) return;
    signingIn = true;
    error = null;
    notifyListeners();

    try {
      final verifier = _randomVerifier();
      final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

      final result = await FlutterWebAuth2.authenticate(
        url: '$apiUrl/auth/mobile/handoff?challenge=$challenge${withGoogle ? '&provider=google' : ''}',
        callbackUrlScheme: authCallbackScheme,
      );

      final callback = Uri.parse(result).queryParameters;
      if (callback['error'] == 'not-manager') throw ApiException(_microsoftRequired);

      final code = callback['code'];
      if (code == null) throw ApiException('Inloggen is mislukt. Probeer opnieuw.');

      final token = await api.exchangeLoginCode(code, verifier);
      client.token = token;
      if (!await _mayUseApp()) {
        client.token = null;
        error = _microsoftRequired;
        return;
      }
      await _storage.write(key: _tokenKey, value: token);
      await refreshProfile();
      unawaited(push.start(api));
    } on PlatformException catch (e) {
      // CANCELED: the user closed the browser tab themselves.
      if (e.code != 'CANCELED') error = 'Inloggen is mislukt. Probeer opnieuw.';
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      signingIn = false;
      notifyListeners();
    }
  }

  Future<void> startDemo() async {
    isDemo = true;
    canReserve = true;
    error = null;
    client.httpClient = DemoBackend();
    client.token = 'demo';
    await refreshProfile();
  }

  Future<void> signOut({bool unregisterDevice = true}) async {
    if (isDemo) {
      isDemo = false;
      client.httpClient = _liveHttp;
      return _setSignedOut();
    }

    // Unregister first: it needs the session that is about to be cleared.
    await push.stop(unregisterDevice: unregisterDevice);
    await _storage.delete(key: _tokenKey);
    _setSignedOut();
  }

  Future<bool> _mayUseApp() async {
    final (links, account) = await both(api.linkedProviders(), api.profile());
    canReserve = links.microsoft > 0;
    return canReserve || account.canManageReservations;
  }

  void _handleUnauthorized() {
    if (status != AuthStatus.signedIn) return;
    error = 'Je sessie is verlopen. Log opnieuw in.';
    // The session is already invalid, so the backend can't be told to unregister the phone.
    signOut(unregisterDevice: false);
  }

  void _setSignedOut() {
    client.token = null;
    // The profile stays: the home screen still reads it while it fades out. Use [status] to check for a session.
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  static String _randomVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
