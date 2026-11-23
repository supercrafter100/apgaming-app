// Renders the Google Play screenshots from the real screens, filled by the demo backend.
// Run it through tool/store_assets.sh, which first downloads Inter into FONT_DIR (Inter-100.ttf … Inter-900.ttf).
// The PNGs land in store/google-play/phone/. The sample data is relative to now, so run it during the day.
// ignore_for_file: invalid_use_of_visible_for_testing_member (a test, kept out of test/ so CI doesn't run it)

import 'dart:io';
import 'dart:ui' as ui;

import 'package:ap_gaming_app/auth/auth_controller.dart';
import 'package:ap_gaming_app/demo/demo_backend.dart';
import 'package:ap_gaming_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phone screenshots at 1080 × 1920 (9:16), as Google Play recommends.
const _size = Size(1080, 1920);
const _pixelRatio = 2.625; // a common Android phone density: 411 × 731 logical pixels

const _fontDir = String.fromEnvironment('FONT_DIR');
const _outDir = 'store/google-play/phone';

Future<void> _loadFonts() async {
  // google_fonts names a family by weight: Inter_regular, Inter_500, …
  for (final weight in [100, 200, 300, 400, 500, 600, 700, 800, 900]) {
    final bytes = File('$_fontDir/Inter-$weight.ttf').readAsBytesSync();
    final loader = FontLoader(weight == 400 ? 'Inter_regular' : 'Inter_$weight')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync();
  await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons)))).load();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  final boundary = GlobalKey();

  setUpAll(() async {
    if (_fontDir.isEmpty) fail('Pass --dart-define=FONT_DIR=… with the Inter font files.');
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('nl_BE');
    await _loadFonts();
    Directory(_outDir).createSync(recursive: true);
  });

  Future<void> shoot(WidgetTester tester, String name) async {
    await _settle(tester);
    final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: _pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File('$_outDir/$name.png').writeAsBytesSync(bytes!);
  }

  Future<AuthController> start(WidgetTester tester, {required bool signedIn}) async {
    tester.view.physicalSize = _size;
    tester.view.devicePixelRatio = _pixelRatio;
    addTearDown(tester.view.reset);

    // A stored session against the demo backend: the real screens, without the demo banner.
    FlutterSecureStorage.setMockInitialValues(signedIn ? {'auth_token': 'store-screenshots'} : {});
    SharedPreferences.setMockInitialValues({});
    final auth = AuthController(httpClient: DemoBackend());
    await tester.runAsync(auth.restore);
    await tester.pumpWidget(RepaintBoundary(key: boundary, child: GamingHubApp(auth: auth)));
    return auth;
  }

  testWidgets('login', (tester) async {
    await start(tester, signedIn: false);
    await shoot(tester, '1-login');
  });

  testWidgets('member', (tester) async {
    await start(tester, signedIn: true);
    await shoot(tester, '2-my-reservations');

    await tester.tap(find.text('Nieuwe reservatie'));
    await _settle(tester);
    await shoot(tester, '3-choose-hardware');

    await tester.tap(find.text('Gaming PC'));
    await _settle(tester);
    await tester.tap(find.text('Volgende'));
    await _settle(tester);
    await tester.tap(find.text('Morgen'));
    await _settle(tester);
    await tester.tap(find.text('15:00'));
    await _settle(tester);
    await shoot(tester, '4-choose-time');
  });

  testWidgets('manager', (tester) async {
    await start(tester, signedIn: true);
    await tester.tap(find.text('Beheer'));
    await _settle(tester);
    // Tomorrow has people still to come, with a note and a block
    await tester.tap(find.byTooltip('Volgende dag'));
    await _settle(tester);
    await shoot(tester, '5-manager-day');

    await tester.tap(find.text('Jules Peeters').last);
    await _settle(tester);
    await shoot(tester, '6-manager-notes');
  });
}
