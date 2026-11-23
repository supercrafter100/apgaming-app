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
2. The backend sends the user through Microsoft login if there's no session, or the session may not use the app, then redirects to `apgaminghub://auth?code=…`.
3. The app exchanges the code and its PKCE verifier at `POST /api/auth/mobile/token` for a bearer token, which it keeps in secure storage.

Reservations require a linked Microsoft account, which the backend enforces. Google sign-in is only for managing: the shield icon in the bottom-right corner of the login screen reveals it, and the backend only lets accounts with the `reservations.manage` permission into the app that way (`?provider=google` on the handoff). A Google-only manager gets the management pages but can't reserve for themselves, though any manager can create a reservation for someone else. Mention the shield in App Review's notes, since Apple doesn't allow undocumented features.

## Demo mode

**Demo bekijken zonder account** on the login screen opens the whole app, including the Gaming Hub manager screens, with sample data. It exists for App Review, because the Microsoft sign-in can't offer a test account.

`lib/demo/demo_backend.dart` replaces the HTTP client with an in-memory backend that speaks the same JSON as the real API, so the demo adds no login route to the server and can't reach real data. Nothing is saved: closing the app or the demo starts it over. Push notifications are the only feature it leaves out. The scan screen offers a sample QR code, since there's no second phone to show one.

When an API endpoint or its rules change, update the demo backend too.

## Builds (GitHub Actions)

`.github/workflows/build.yml` runs when a GitHub release or pre-release is published, and on demand:

- **Analyze & test**
- **Android**: release APK and app bundle (`android` artifact)
- **iOS**: `.ipa` (`ios` artifact), signed once the secrets below are set and unsigned before that

Publishing a release also attaches the builds to it, uploads the iOS build to TestFlight and the Android build to Google Play's internal testing. The build number is the workflow run number; the version name comes from `pubspec.yaml`.

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
- **External testers** (up to 10,000) can be anyone, invited by email or public link. Create a group under External Testing and add a build to it. The first build of each version goes through Apple's beta review, which needs a description and a contact. There's no test account to give the reviewer, so point them to the [demo mode](#demo-mode) in the review notes. Apple's guidelines only allow a demo mode instead of a demo account with App Review's prior approval.

Testers install the [TestFlight app](https://apps.apple.com/app/testflight/id899247664) and accept the invite. A build stops working 90 days after upload.

#### Releasing

Publish a GitHub release to send a build to TestFlight; a pre-release does the same. Which testers get it is decided by the groups in App Store Connect, not by the type of GitHub release.

- Every upload needs a new build number. Re-running a workflow keeps its run number, so if the upload itself succeeded, start a new run rather than re-running the old one.
- Change `version` in `pubspec.yaml` for a new version. Tag names don't affect the version in the app.

#### Yearly renewal

The certificate and profile expire after a year, and builds then fail at signing. Repeat steps 2 and 3 to renew them; the app and testers are unaffected. Also repeat step 3 if the App ID's capabilities change. The upload key doesn't expire.

### Installing an unsigned iOS build

Without the signing secrets, iOS refuses to install the build directly. To try it on your own iPhone, sideload the `.ipa` with [Sideloadly](https://sideloadly.io) or [AltStore](https://altstore.io): they sign it with your free Apple ID. Such installs expire after 7 days and need re-signing.

### Google Play

Like TestFlight, GitHub Actions builds, signs and uploads; no Android Studio is needed. The setup below is done once, in a browser and a Linux terminal with `gh` signed in.

Before the first upload, decide on the package name. It is `be.svinnovations.ap_gaming_app` (`applicationId` in `android/app/build.gradle.kts`, and `packageName` in the workflow). Google Play fixes it for good after the first upload; changing it later means a new app with new testers and reviews.

#### 1. Create the app in Play Console

In [Play Console](https://play.google.com/console), choose **Create app**: name `AP Gaming Hub`, default language Dutch (Belgium), **App**, **Free**, and accept the declarations. The package name isn't asked here; the first upload sets it.

The **Dashboard** then lists the setup tasks. Internal testing needs only some of them; closed testing and production need all. For the ones that ask about this app:

- **Privacy policy**: `https://apgaming.be/privacy`
- **App access**: all functionality needs an AP account, so describe the [demo mode](#demo-mode): *Demo bekijken zonder account* on the login screen opens the whole app with sample data.
- **Ads**: no ads.

#### 2. Create the upload key

Google re-signs the app for the store with its own key (Play App Signing); you sign uploads with an upload key. Keep it out of the repository, and keep a copy of the keystore and password in your password manager. If it's lost, Google can reset it, but only through a support request.

```bash
mkdir -p ~/android-signing && chmod 700 ~/android-signing && cd ~/android-signing
KEYSTORE_PASSWORD=$(openssl rand -base64 24)
keytool -genkeypair -v -keystore upload-keystore.jks -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload -storepass "$KEYSTORE_PASSWORD" -dname "CN=AP Gaming Hub, C=BE"

REPO=supercrafter100/apgaming-app
base64 -w0 upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64 -R $REPO
printf %s "$KEYSTORE_PASSWORD" | gh secret set ANDROID_KEYSTORE_PASSWORD -R $REPO
# A PKCS12 keystore has one password for the store and the key
printf %s "$KEYSTORE_PASSWORD" | gh secret set ANDROID_KEY_PASSWORD -R $REPO
gh secret set ANDROID_KEY_ALIAS -R $REPO --body upload
```

Without these secrets, release builds are signed with debug keys: they install fine, but Google Play won't accept them, and the workflow doesn't try.

#### 3. Create the upload access

The workflow uploads with a Google Cloud service account that has access to the app in Play Console.

1. In [Google Cloud Console](https://console.cloud.google.com/projectcreate), create a project, for example `ap-gaming-hub-play`. You can reuse the Firebase project instead.
2. [Enable the Google Play Android Developer API](https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com) in it.
3. Under [IAM & Admin → Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts), create a service account named `github-actions`. It needs no roles in the Cloud project. Open it, go to **Keys → Add key → Create new key → JSON**, and save the file to `~/android-signing/play-service-account.json`. If key creation is refused, an organisation policy (`iam.disableServiceAccountKeyCreation`) is blocking it; an admin of the Google Cloud organisation can lift it for this project.
4. In Play Console, go to **Users and permissions → Invite new users**, enter the service account's email (`github-actions@….iam.gserviceaccount.com`), and under **App permissions** add AP Gaming Hub with **Release apps to testing tracks**. Send the invitation; a service account doesn't need to accept it.

```bash
gh secret set PLAY_SERVICE_ACCOUNT_JSON -R $REPO < play-service-account.json
```

#### 4. Upload the first build by hand

Google's API only accepts uploads for an app that already has one, so the first `.aab` goes through Play Console. Build it signed, without uploading, and download it:

```bash
gh workflow run build.yml -R $REPO
sleep 10 # the new run takes a moment to show up
RUN=$(gh run list -R $REPO -w build.yml -L 1 --json databaseId -q '.[0].databaseId')
gh run watch -R $REPO $RUN
gh run download -R $REPO $RUN -n android -D ~/android-signing/first-build
```

In Play Console, go to **Test and release → Testing → Internal testing → Create new release**. Accept Play App Signing when asked, upload `first-build/ap-gaming-hub.aab`, then **Save**, **Next** and **Save and publish**. Add the testers (step 5) before or after; the release reaches them once they're in the list.

#### 5. Add testers

- **Internal testing** (up to 100 testers) is the counterpart of TestFlight's internal testing: no review, and a new build reaches the testers within minutes. On the **Testers** tab of Internal testing, create an email list such as `AP Gaming Hub testers`, add the testers' Google account addresses, and save. Then copy the **Join on the web** link and send it to them.
- **Closed testing** reaches more people, for example through a Google Group, but each build goes through Google's review. To upload there instead, set `gh variable set PLAY_TRACK -R $REPO --body alpha` (the default closed track) or a closed track's name.

Testers open the link on their Android phone with that Google account, accept, and install AP Gaming Hub from the Play Store. Updates then come through the Play Store like any other app.

A personal developer account created after November 2023 needs a closed test with at least 12 testers for 14 days before it can publish to production. This doesn't apply to an organisation account or to internal testing.

#### 6. Automatic uploads

From now on, every published GitHub release uploads the Android build to internal testing, next to the iOS build to TestFlight. To upload without a release:

```bash
gh workflow run build.yml -R $REPO -f play=true
```

If the upload fails with *Only releases with status draft may be created on draft app*, the app hasn't had a release rolled out yet: finish step 4, or meanwhile set `gh variable set PLAY_RELEASE_STATUS -R $REPO --body draft` and roll out each release in Play Console. Remove the variable once a release has been rolled out.

Each upload needs a higher version code than the last. The version code is the workflow run number, like the iOS build number, so start a new run rather than re-running one whose upload succeeded.

### Store assets

`store/google-play/` holds what the Play Store listing asks for: the 512 × 512 icon, the 1024 × 500 feature graphic and six 1080 × 1920 phone screenshots. The screenshots are the real screens with the demo data, so after a visible change to the app, rebuild them all:

```bash
tool/store_assets.sh   # needs rsvg-convert and ImageMagick 7
```

The sample reservations are relative to the current time; run it during the day so today still has sessions to come.

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
