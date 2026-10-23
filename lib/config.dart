/// Base URL of the AP Gaming Hub website. The API lives under `/api` on the same host,
/// which is also where the web login sets its session cookie.
///
/// Override per build: `flutter run --dart-define=WEB_URL=https://gaming.example.be`
const webUrl = String.fromEnvironment('WEB_URL', defaultValue: 'https://apgaming.be');
// const webUrl = String.fromEnvironment('WEB_URL', defaultValue: 'http://localhost:3000');

const apiUrl = '$webUrl/api';

/// Must match MOBILE_APP_CALLBACK_URL in the backend and the scheme in AndroidManifest.xml.
const authCallbackScheme = 'apgaminghub';
