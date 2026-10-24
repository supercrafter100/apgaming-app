import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

// Firebase client config, passed at build time from config/firebase.json:
//   flutter run --dart-define-from-file=config/firebase.json
// These values only identify the Firebase project; they are not secrets.
// Without them the app runs normally, just without push notifications.
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const _senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
const _androidApiKey = String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
const _androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
const _iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');
const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');

FirebaseOptions? get firebaseOptions => switch (defaultTargetPlatform) {
  TargetPlatform.android when _androidAppId.isNotEmpty => const FirebaseOptions(
    apiKey: _androidApiKey,
    appId: _androidAppId,
    messagingSenderId: _senderId,
    projectId: _projectId,
  ),
  TargetPlatform.iOS when _iosAppId.isNotEmpty => const FirebaseOptions(
    apiKey: _iosApiKey,
    appId: _iosAppId,
    messagingSenderId: _senderId,
    projectId: _projectId,
    iosBundleId: 'be.svinnovations.apGamingApp',
  ),
  _ => null,
};
