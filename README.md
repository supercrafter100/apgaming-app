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

`.github/workflows/build.yml` runs when a GitHub release or pre-release is published, and on demand:

- **Analyze & test**
- **Android**: release APK and app bundle (`android` artifact)
- **iOS**: `.ipa` (`ios` artifact), signed once the secrets below are set and unsigned before that

Publishing a release also attaches the builds to it and uploads the iOS build to TestFlight. The build number is the workflow run number; the version name comes from `pubspec.yaml`.

### TestFlight

No Mac is needed: GitHub Actions does the building and signing. The setup below is done once, in a browser and a Linux terminal with `gh` signed in.

#### 1. Register the app with Apple

1. In [Identifiers](https://developer.apple.com/account/resources/identifiers/list), add an **App ID** of type **App**. Use the explicit bundle ID `be.svinnovations.apGamingApp` and tick **Push Notifications** under Capabilities. The build fails without that capability, because the app requests the push entitlement.
2. In [App Store Connect](https://appstoreconnect.apple.com/apps), add a **New App**: platform iOS, name `AP Gaming Hub`, primary language Dutch, the bundle ID you just registered, and any SKU (for example `ap-gaming-hub`).

#### 2. Create the distribution certificate

Keep these files out of the repository. Run this in a folder of its own, and keep that terminal open for the next steps:

```bash
mkdir -p ~/apple-signing && chmod 700 ~/apple-signing && cd ~/apple-signing
openssl genrsa -out dist.key 2048
openssl req -new -key dist.key -out dist.csr -subj "/CN=AP Gaming Hub Distribution/C=BE"
```

In [Certificates](https://developer.apple.com/account/resources/certificates/list), add an **Apple Distribution** certificate, upload `dist.csr`, and download the result to `~/apple-signing/distribution.cer`. Then package it and store it as secrets:

```bash
curl -fsSO https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
openssl x509 -inform DER -in AppleWWDRCAG3.cer -out wwdr.pem
openssl x509 -inform DER -in distribution.cer -out distribution.pem
P12_PASSWORD=$(openssl rand -base64 24)
# -legacy: the macOS keychain can't read the newer default format
openssl pkcs12 -export -legacy -inkey dist.key -in distribution.pem -certfile wwdr.pem -out dist.p12 -passout "pass:$P12_PASSWORD"

REPO=supercrafter100/apgaming-app
base64 -w0 dist.p12 | gh secret set IOS_DIST_CERT_P12_BASE64 -R $REPO
printf %s "$P12_PASSWORD" | gh secret set IOS_DIST_CERT_PASSWORD -R $REPO
```

#### 3. Create the provisioning profile

In [Profiles](https://developer.apple.com/account/resources/profiles/list), add a profile of type **App Store Connect** (under Distribution). Select the App ID and the certificate, name it `AP Gaming Hub App Store`, and download it to `~/apple-signing/profile.mobileprovision`.

```bash
base64 -w0 profile.mobileprovision | gh secret set IOS_PROVISIONING_PROFILE_BASE64 -R $REPO
```

#### 4. Create the upload key

In App Store Connect, go to [Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api). The Account Holder has to request API access the first time. Under **Team Keys**, generate a key named `GitHub Actions` with the **App Manager** role and download the `.p8` file to `~/apple-signing`. Apple only lets you download it once. The key ID and issuer ID are shown on the same page.

```bash
gh secret set ASC_KEY_ID -R $REPO --body "YOUR_KEY_ID"
gh secret set ASC_ISSUER_ID -R $REPO --body "YOUR_ISSUER_ID"
base64 -w0 AuthKey_YOUR_KEY_ID.p8 | gh secret set ASC_KEY_P8_BASE64 -R $REPO
```

#### 5. Run the first upload

With the workflow on `main`, start a build without publishing a release:

```bash
gh workflow run build.yml -R $REPO -f testflight=true
```

The build appears in App Store Connect under the app's **TestFlight** tab, usually within half an hour of the upload. Apple emails the account holder if processing finds a problem.

#### 6. Add testers

- **Internal testers** (up to 100) need an App Store Connect account on your team. Under TestFlight → Internal Testing, create a group, add them and enable automatic distribution, so that each new build reaches them without a review.
- **External testers** (up to 10,000) can be anyone, invited by email or public link. Create a group under External Testing and add a build to it. The first build of each version goes through Apple's beta review, which needs a description, a contact and a working test account, since the app requires a login.

Testers install the [TestFlight app](https://apps.apple.com/app/testflight/id899247664) and accept the invite. A build stops working 90 days after upload.

#### Releasing

Publish a GitHub release to send a build to TestFlight; a pre-release does the same. Which testers get it is decided by the groups in App Store Connect, not by the type of GitHub release.

- Every upload needs a new build number. Re-running a workflow keeps its run number, so if the upload itself succeeded, start a new run rather than re-running the old one.
- Change `version` in `pubspec.yaml` for a new version. Tag names don't affect the version in the app.

#### Yearly renewal

The certificate and profile expire after a year, and builds then fail at signing. Repeat steps 2 and 3 to renew them; the app and testers are unaffected. Also repeat step 3 if the App ID's capabilities change. The upload key doesn't expire.

### Installing an unsigned iOS build

Without the signing secrets, iOS refuses to install the build directly. To try it on your own iPhone, sideload the `.ipa` with [Sideloadly](https://sideloadly.io) or [AltStore](https://altstore.io): they sign it with your free Apple ID. Such installs expire after 7 days and need re-signing.

### Android signing

Without secrets, release builds are signed with debug keys: they install fine, but Google Play won't accept them. To sign with an upload key, add these repository secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password |

Create the keystore with `keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`.

### App icon and launch screen

The icon is the website's gamepad mark. Its sources are the SVGs in `assets/icon`; after editing one, render it to PNG and regenerate:

```bash
for f in assets/icon/*.svg; do rsvg-convert -w 1024 -h 1024 "$f" -o "${f%.svg}.png"; done
magick assets/icon/icon.png -alpha off assets/icon/icon.png   # App Store icons may not have transparency
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

`flutter_launcher_icons` sets `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` to `AppIcon` in the Xcode project; revert that line (it must stay `YES`).

### Push notifications

Members get a push notification 15 minutes before each reservation. The backend sends it through Firebase Cloud Messaging, so it also works for reservations made on the website or by a Gaming Hub manager. The app registers the phone after sign-in and unregisters it on sign-out; the reminder can be switched off under Account → Meldingen.

Until Firebase is configured, builds simply have no push notifications. To switch them on:

1. Create a Firebase project and add an Android app (`be.svinnovations.ap_gaming_app`) and an iOS app (`be.svinnovations.apGamingApp`).
2. Copy `config/firebase.example.json` to `config/firebase.json` and fill in the values from both apps' config (the API key, app ID, sender ID and project ID). These identify the project and aren't secret, so the file can be committed; CI then builds with it.
3. Give the platform backend the service account key: `FIREBASE_SERVICE_ACCOUNT` (see its `.env.prod.example`).
4. iOS only: create an APNs key under [Keys](https://developer.apple.com/account/resources/authkeys/list) and upload it in Firebase (Project settings → Cloud Messaging). The push entitlement is already in `ios/Runner/Runner.entitlements`, and the workflow switches it to production for signed builds.

Locally: `flutter run --dart-define-from-file=config/firebase.json`.

### Pointing a build at another server

Set the repository variable `WEB_URL` (for example a staging site). Without it, builds use the default in `lib/config.dart`.
