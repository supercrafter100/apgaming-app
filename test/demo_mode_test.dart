import 'dart:convert';

import 'package:ap_gaming_app/api/api_client.dart';
import 'package:ap_gaming_app/api/hub_api.dart';
import 'package:ap_gaming_app/api/models.dart';
import 'package:ap_gaming_app/auth/auth_controller.dart';
import 'package:ap_gaming_app/demo/demo_backend.dart';
import 'package:ap_gaming_app/main.dart';
import 'package:ap_gaming_app/util/wall_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('nl_BE');
  });

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('demo mode', () {
    testWidgets('runs member and manager flows from the login screen without touching the network', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final network = <String>[];
      final auth = AuthController(
        httpClient: MockClient((request) async {
          network.add(request.url.toString());
          return http.Response('{}', 500);
        }),
      );
      await auth.restore();

      await tester.pumpWidget(GamingHubApp(auth: auth));
      await settle(tester);

      expect(find.text('Inloggen met Microsoft'), findsOneWidget);
      expect(find.textContaining('Google'), findsNothing);
      await tester.tap(find.text('Demo bekijken zonder account'));
      await settle(tester);

      // The seeded PS5 session is tomorrow, so booking one today or tomorrow stays possible.
      expect(auth.isDemo, isTrue);
      expect(find.textContaining('niets wordt echt gereserveerd'), findsOneWidget);
      expect(find.text('PlayStation 5'), findsOneWidget);
      expect(find.textContaining('Nog 2 no-shows'), findsOneWidget);

      // Book a session through the real flow
      await tester.tap(find.text('Nieuwe reservatie'));
      await settle(tester);
      await tester.tap(find.text('Gaming PC'));
      await settle(tester);
      await tester.tap(find.text('Volgende'));
      await settle(tester);
      await tester.tap(find.text('Morgen'));
      await settle(tester);
      await tester.tap(find.text('09:00'));
      await settle(tester);
      await tester.tap(find.text('Volgende'));
      await settle(tester);
      await tester.tap(find.byType(Checkbox));
      await settle(tester);
      await tester.tap(find.text('Reserveren'));
      await settle(tester);
      expect(find.text('Reservatie ontvangen!'), findsOneWidget);
      await tester.tap(find.text('Klaar'));
      await settle(tester);
      expect(find.text('Komende (2)'), findsOneWidget);

      // The Gaming Hub manager's overview is part of the demo
      await tester.tap(find.text('Beheer'));
      await settle(tester);
      expect(find.text('Robin Claes'), findsWidgets); // first of the day; later rows are built when scrolled to

      // Leaving goes back to a clean login screen
      await tester.tap(find.text('Account'));
      await settle(tester);
      await tester.tap(find.text('Demo afsluiten'));
      await settle(tester);
      expect(auth.isDemo, isFalse);
      expect(auth.status, AuthStatus.signedOut);
      expect(find.textContaining('niets wordt echt gereserveerd'), findsNothing);
      expect(find.text('Inloggen met Microsoft'), findsOneWidget);

      expect(network, isEmpty);
    });

    testWidgets('fits the login screen on a small phone', (tester) async {
      tester.view.physicalSize = const Size(640, 1136); // iPhone SE (1st generation)
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final auth = AuthController(httpClient: MockClient((_) async => http.Response('{}', 500)));
      await auth.restore();
      await tester.pumpWidget(GamingHubApp(auth: auth));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Demo bekijken zonder account'), findsOneWidget);
    });

    group('backend', () {
      late HubApi api;
      final now = DateTime.utc(2026, 11, 4, 12);

      setUp(() {
        final client = ApiClient(
          baseUrl: 'https://demo.invalid/api',
          onUnauthorized: () {},
          httpClient: DemoBackend(now: now),
        );
        api = HubApi(client);
      });

      test('checks in the sample QR code once it is scanned', () async {
        final verified = await api.verify(DemoBackend.checkInCode);
        expect(verified.status, ReservationStatus.present);

        final today = await api.reservationsOn(now);
        expect(today.singleWhere((r) => r.cuid == DemoBackend.checkInCode).status, ReservationStatus.present);
      });

      test('reports an unknown code the way the real backend does', () async {
        await expectLater(
          api.verify('does-not-exist'),
          throwsA(isA<ApiException>().having((e) => e.isNotFound, 'isNotFound', isTrue)),
        );
      });

      test('lets the manager create, edit, set a status and remove a reservation', () async {
        final tomorrow = DateTime.utc(2026, 11, 5);
        final body = {
          'email': 'new.member@example.com',
          'inventory': 'pc',
          'controllers': 0,
          'startTime': wallClockIso(tomorrow, 600),
          'endTime': wallClockIso(tomorrow, 660),
        };
        await api.adminCreateReservation(body);

        var day = await api.reservationsOn(tomorrow);
        final id = day.singleWhere((r) => r.email == 'new.member@example.com').id;

        await api.adminUpdateReservation(id, {...body, 'inventory': 'ps5', 'controllers': 2});
        await api.updateStatus(id, ReservationStatus.present);
        day = await api.reservationsOn(tomorrow);
        final updated = day.singleWhere((r) => r.id == id);
        expect(updated.hardware, Hardware.ps5);
        expect(updated.status, ReservationStatus.present);

        await api.deleteReservation(id);
        day = await api.reservationsOn(tomorrow);
        expect(day.where((r) => r.id == id), isEmpty);
      });

      test('clears no-shows for one user and for everyone', () async {
        final before = await api.noShows();
        expect(before, isNotEmpty);

        await api.unblockUser(before.first.userId);
        final after = await api.noShows();
        expect(after.where((r) => r.userId == before.first.userId), isEmpty);

        await api.resetAllNoShows();
        expect(await api.noShows(), isEmpty);
      });
    });
  });

  group('Microsoft-only sign-in', () {
    http.Client backend({required bool microsoft}) => MockClient((request) async {
      final body = switch (request.url.path) {
        '/api/auth/links' => {
          'google': [
            {'id': 1, 'ssoId': 'g'},
          ],
          'microsoft': microsoft
              ? [
                  {'id': 2, 'ssoId': 'm'},
                ]
              : <Object>[],
        },
        '/api/auth/profile' => {'id': 7, 'email': 'jamie@example.com', 'permissions': <String>[]},
        _ => <String, Object>{},
      };
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    });

    test('ends a saved session that has no Microsoft account', () async {
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'google-session'});
      const storage = FlutterSecureStorage();

      final auth = AuthController(httpClient: backend(microsoft: false), storage: storage);
      await auth.restore();

      expect(auth.status, AuthStatus.signedOut);
      expect(auth.error, contains('Microsoft'));
      expect(await storage.read(key: 'auth_token'), isNull);
    });

    test('keeps a saved session with a Microsoft account', () async {
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'microsoft-session'});
      const storage = FlutterSecureStorage();

      final auth = AuthController(httpClient: backend(microsoft: true), storage: storage);
      await auth.restore();

      expect(auth.status, AuthStatus.signedIn);
      expect(await storage.read(key: 'auth_token'), 'microsoft-session');
    });

    test('translates the backend refusing a reservation', () {
      expect(translateApiMessage('Reservations require a Microsoft account'), contains('AP Microsoft-account'));
    });
  });
}
