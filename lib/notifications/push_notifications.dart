import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/hub_api.dart';
import 'firebase_options.dart';

enum PushStatus {
  /// Not configured in this build, or not signed in yet.
  unavailable,

  /// The user declined notifications in the system prompt or settings.
  denied,

  /// Registered with the backend.
  enabled,
}

/// Registers this phone with the backend for push notifications (Firebase Cloud Messaging).
/// The backend decides what to send, e.g. a reminder 15 minutes before every reservation,
/// including ones made on the website.
class PushNotifications extends ChangeNotifier {
  PushNotifications({FirebaseOptions? options}) : _options = options ?? firebaseOptions;

  final FirebaseOptions? _options;

  /// Lets foreground messages show as a snackbar on Android (iOS shows its own banner).
  final messengerKey = GlobalKey<ScaffoldMessengerState>();

  HubApi? _api;
  String? _fid;
  final _subscriptions = <StreamSubscription<Object>>[];

  PushStatus status = PushStatus.unavailable;
  bool reservationReminders = true;

  bool get isConfigured => _options != null;

  static String get _platform => defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// Asks for permission (once, the OS remembers the answer) and registers the phone. Call after sign-in.
  Future<void> start(HubApi api) async {
    final options = _options;
    if (options == null || _api != null) return;
    _api = api;

    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: options);
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        _setStatus(PushStatus.denied);
        return;
      }

      await messaging.setForegroundNotificationPresentationOptions(alert: true, sound: true);
      _subscriptions
        ..add(messaging.onRegistered.listen(_registerDevice))
        ..add(FirebaseMessaging.onMessage.listen(_showForegroundMessage));
      await messaging.register();
    } catch (error) {
      // E.g. an iOS build without APNs signing: the app keeps working without push.
      debugPrint('Push notifications unavailable: $error');
    }
  }

  Future<void> setReservationReminders(bool enabled) async {
    final fid = _fid;
    final api = _api;
    if (fid == null || api == null) return;

    reservationReminders = enabled;
    notifyListeners();
    try {
      await api.registerPushDevice(fid: fid, platform: _platform, reservationReminders: enabled);
    } catch (_) {
      reservationReminders = !enabled;
      notifyListeners();
      rethrow;
    }
  }

  /// Stops pushes to this phone. Call before signing out, while the session is still valid.
  Future<void> stop({bool unregisterDevice = true}) async {
    final fid = _fid;
    final api = _api;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    _api = null;
    _fid = null;
    _setStatus(PushStatus.unavailable);

    if (unregisterDevice && fid != null && api != null) {
      try {
        await api.unregisterPushDevice(fid);
      } catch (error) {
        debugPrint('Could not unregister push device: $error');
      }
    }
  }

  Future<void> _registerDevice(String fid) async {
    final api = _api;
    if (api == null) return;
    try {
      reservationReminders = await api.registerPushDevice(fid: fid, platform: _platform);
      _fid = fid;
      _setStatus(PushStatus.enabled);
    } catch (error) {
      debugPrint('Could not register push device: $error');
    }
  }

  void _showForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null || defaultTargetPlatform == TargetPlatform.iOS) return;
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Row(
          children: [
            const Icon(Icons.notifications_active_outlined, color: Color(0xFFD42422)),
            const SizedBox(width: 12),
            Expanded(child: Text([notification.title, notification.body].whereType<String>().join('\n'))),
          ],
        ),
      ),
    );
  }

  void _setStatus(PushStatus value) {
    status = value;
    notifyListeners();
  }
}
