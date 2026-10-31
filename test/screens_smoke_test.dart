import 'dart:convert';

import 'package:ap_gaming_app/auth/auth_controller.dart';
import 'package:ap_gaming_app/main.dart';
import 'package:ap_gaming_app/util/wall_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Pumps a few frames so route transitions and chained fake HTTP calls finish
/// (pumpAndSettle never returns while a progress indicator spins).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Renders every screen at phone size against a fake backend to catch layout
/// overflows and runtime errors without a device.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('nl_BE');
  });

  final today = wallClockNow();
  String at(int dayOffset, int hour, [int minute = 0]) =>
      DateTime.utc(today.year, today.month, today.day + dayOffset, hour, minute).toIso8601String();

  final requests = <String>[];

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  final backend = MockClient((request) async {
    requests.add('${request.method} ${request.url.path}');
    final user = {'id': 7, 'name': 'Jamie Peeters', 'sNumber': 's145678', 'reservationCount': 1};
    return switch ((request.method, request.url.path)) {
      ('GET', '/api/auth/profile') => json({
        'id': 7,
        'name': 'Jamie Peeters',
        'email': 'jamie.peeters@student.ap.be',
        'sNumber': 's145678',
        'isAdmin': true,
        'roles': ['Admin'],
        'permissions': ['reservations.manage'],
      }),
      ('GET', '/api/auth/links') => json({
        'google': [],
        'microsoft': [
          {'id': 1, 'ssoId': 'x'},
        ],
      }),
      ('GET', '/api/reservations/me') => json({
        'reservations': [
          {
            'cuid': 'cm-upcoming',
            'inventory': 'ps5',
            'controllers': 2,
            'startTime': at(1, 14),
            'endTime': at(1, 15),
            'status': 'RESERVED',
          },
          {
            'cuid': 'cm-past',
            'inventory': 'pc',
            'controllers': 0,
            'startTime': at(-3, 12),
            'endTime': at(-3, 13),
            'status': 'NO_SHOW',
          },
        ],
        'noShowCount': 1,
        'noShowLimit': 3,
        'isBlocked': false,
      }),
      ('GET', '/api/timetable') => json([
        for (var d = 0; d < 7; d++)
          {
            'dayOfWeek': d,
            'startTime': '1970-01-01T10:00:00.000Z',
            'endTime': '1970-01-01T22:00:00.000Z',
            'type': 'OPEN',
          },
      ]),
      ('GET', '/api/settings/inventory') => json([
        {'id': 1, 'key': 'pc', 'value': '5'},
        {'id': 2, 'key': 'ps5', 'value': '1'},
      ]),
      ('GET', '/api/reservations/slots') || ('GET', '/api/reservations/adjustments') => json([]),
      ('POST', '/api/reservations') => json({'id': 99}, 201),
      ('GET', '/api/reservations') => json([
        {
          'id': 1,
          'cuid': 'cm-a',
          'userId': 7,
          'email': 'jamie.peeters@student.ap.be',
          'inventory': 'switch',
          'controllers': 3,
          'startTime': at(0, 16),
          'endTime': at(0, 17, 30),
          'status': 'RESERVED',
          'user': user,
        },
        {
          'id': 2,
          'cuid': 'cm-b',
          'userId': 8,
          'email': 'a.very.long.email.address.for.layout@student.ap.be',
          'inventory': 'pc',
          'controllers': 0,
          'startTime': at(0, 18),
          'endTime': at(0, 20),
          'status': 'PRESENT',
          'user': {'id': 8, 'name': 'Alexandra Van Den Broeck-Vermeulen', 'sNumber': 's999999', 'reservationCount': 12},
        },
      ]),
      ('GET', '/api/reservations/no-shows') => json([
        {
          'id': 3,
          'cuid': 'cm-c',
          'userId': 7,
          'email': 'jamie.peeters@student.ap.be',
          'inventory': 'pc',
          'controllers': 0,
          'startTime': at(-3, 12),
          'endTime': at(-3, 13),
          'status': 'NO_SHOW',
          'user': user,
        },
      ]),
      _ => json({'message': 'Not mocked'}, 404),
    };
  });

  testWidgets('member and staff flows render on a phone', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532); // iPhone 13/14
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final auth = AuthController(httpClient: backend);
    auth.client.token = 'test-token';
    await auth.refreshProfile();

    await tester.pumpWidget(GamingHubApp(auth: auth));
    await settle(tester);

    // My reservations
    expect(find.text('Reservaties'), findsWidgets);
    expect(find.text('PlayStation 5'), findsOneWidget);
    expect(find.textContaining('Nog 2 no-shows'), findsOneWidget);

    await tester.tap(find.text('PlayStation 5'));
    await settle(tester);
    expect(find.text('Laat deze code scannen door de Gaming Hub manager wanneer je aankomt.'), findsOneWidget);
    expect(find.text('Reservatie annuleren'), findsOneWidget);
    Navigator.of(tester.element(find.text('Reservatie annuleren'))).pop(); // dismiss the sheet
    await settle(tester);

    // New reservation flow
    await tester.tap(find.text('Nieuwe reservatie'));
    await settle(tester);
    expect(find.text('Kies je hardware'), findsOneWidget);
    await tester.tap(find.text('PlayStation 5'));
    await settle(tester);
    await tester.tap(find.text('1'));
    await settle(tester);
    await tester.tap(find.text('Volgende'));
    await settle(tester);

    expect(find.text('Wanneer wil je komen?'), findsOneWidget);
    await tester.tap(find.text('Morgen'));
    await settle(tester);
    await tester.tap(find.text('10:00'));
    await settle(tester);
    await tester.tap(find.text('Volgende'));
    await settle(tester);

    expect(find.text('Bevestigen'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await settle(tester);
    await tester.tap(find.text('Reserveren'));
    await settle(tester);
    expect(find.text('Reservatie ontvangen!'), findsOneWidget);
    expect(requests, contains('POST /api/reservations'));
    await tester.tap(find.text('Klaar'));
    await settle(tester);

    // Staff day overview
    await tester.tap(find.text('Beheer'));
    await settle(tester);
    expect(find.text('Alexandra Van Den Broeck-Vermeulen'), findsOneWidget);
    expect(find.text('Vandaag'), findsWidgets);
    await tester.tap(find.text('Jamie Peeters'));
    await settle(tester);
    expect(find.text('STATUS'), findsOneWidget);
    await tester.tap(find.text('Bewerken'));
    await settle(tester);
    expect(find.text('Reservatie bewerken'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await settle(tester);

    await tester.tap(find.byTooltip('No-shows'));
    await settle(tester);
    expect(find.text('Deblokkeren'), findsOneWidget);
    Navigator.of(tester.element(find.text('Deblokkeren'))).pop();
    await settle(tester);

    // Account
    await tester.tap(find.text('Account'));
    await settle(tester);
    expect(find.text('Google'), findsNothing);
    expect(find.text('Uitloggen'), findsOneWidget);
  });
}
