# AP Gaming Hub app

iOS and Android app for the AP Gaming Hub. Members reserve a PC or console and manage their account; Gaming Hub managers see the day's reservations, check people in by scanning their QR code and handle no-shows.

The app has no backend of its own. It talks to the [AP Gaming Community Platform](https://github.com/MilanMareels/ap-gaming-community-platform) API under `/api` on the website, and signing in goes through the website's own login page.

## Running locally

```bash
flutter pub get
flutter run                                               # against https://apgaming.be
flutter run --dart-define=WEB_URL=http://localhost:3000  # against a local platform
```

For a local platform on an Android device or emulator, forward the port first: `adb reverse tcp:3000 tcp:3000`. The iOS simulator reaches `localhost` directly.

```bash
flutter analyze
flutter test
```

## How login works

1. The app opens `/api/auth/mobile/handoff?challenge=…` in an in-app browser tab, with a PKCE challenge.
2. The backend sends the user through the website's `/login` if needed, then redirects to `apgaminghub://auth?code=…`.
3. The app exchanges the code and its PKCE verifier at `POST /api/auth/mobile/token` for a bearer token, which it keeps in secure storage.

## Builds (GitHub Actions)

`.github/workflows/build.yml` runs on every push to `main`, on pull requests and on demand:

- **Analyze & test**
- **Android**: release APK and app bundle (`android` artifact)
- **iOS**: unsigned release build packaged as an `.ipa` (`ios` artifact)

Pushing a tag like `v1.0.0` also attaches the builds to a GitHub release. The build number is the workflow run number; the version name comes from `pubspec.yaml`.

### Android signing

Without secrets, release builds are signed with debug keys: they install fine, but Google Play won't accept them. To sign with an upload key, add these repository secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password |

Create the keystore with `keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`.

### Pointing a build at another server

Set the repository variable `WEB_URL` (for example a staging site). Without it, builds use the default in `lib/config.dart`.
