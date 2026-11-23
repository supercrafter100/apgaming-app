import 'package:ap_gaming_app/api/api_client.dart';
import 'package:ap_gaming_app/api/models.dart';
import 'package:ap_gaming_app/screens/admin/qr_scan_screen.dart';
import 'package:ap_gaming_app/util/wall_clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('nl_BE'));

  test('reservation times keep their wall-clock value', () {
    final r = MyReservation.fromJson({
      'cuid': 'abc',
      'inventory': 'switch',
      'controllers': 2,
      'startTime': '2026-10-23T14:00:00.000Z',
      'endTime': '2026-10-23T15:30:00.000Z',
      'status': 'RESERVED',
    });

    expect(r.hardware, Hardware.nintendoSwitch);
    expect(formatMinutes(minutesOfDay(r.start)), '14:00');
    expect(formatMinutes(minutesOfDay(r.end)), '15:30');
  });

  test('serializes wall-clock times like the website', () {
    expect(wallClockIso(DateTime.utc(2026, 10, 23), 14 * 60 + 30), '2026-10-23T14:30:00.000Z');
  });

  test('extracts the reservation code from a scanned value', () {
    expect(extractCuid('  cm9x8k2df0000a1b2c3d4e5f6 '), 'cm9x8k2df0000a1b2c3d4e5f6');
    expect(extractCuid('https://hub.example/cancel-reservation/cm9x8k2df'), 'cm9x8k2df');
    expect(extractCuid('https://hub.example/verify?reservation=cm9x8k2df'), 'cm9x8k2df');
  });

  test('translates known backend errors to Dutch', () {
    expect(translateApiMessage('You can only make 1 reservation per day'), 'Je kan maximaal 1 reservatie per dag maken.');
    expect(translateApiMessage('You can only make 3 reservations per day'), 'Je kan maximaal 3 reservaties per dag maken.');
    expect(
      translateApiMessage('You must have at least 90 minutes between reservations'),
      'Er moet minstens 90 minuten tussen je reservaties zitten.',
    );
    expect(translateApiMessage('All pcs are already reserved for this time slot'), contains('al gereserveerd'));
    expect(translateApiMessage('Something new'), 'Something new');
  });

  test('profile exposes staff permissions', () {
    final profile = Profile.fromJson({
      'id': 1,
      'name': null,
      'email': 'jamie@student.ap.be',
      'sNumber': 'N/A',
      'isAdmin': false,
      'roles': ['Medewerker'],
      'permissions': ['reservations.noshows.manage'],
    });

    expect(profile.displayName, 'jamie@student.ap.be');
    expect(profile.hasSNumber, isFalse);
    expect(profile.canManageReservations, isFalse);
    expect(profile.canManageNoShows, isTrue);
  });

  test('reads someone\'s active notes, most serious first', () {
    final r = AdminReservation.fromJson({
      'id': 1,
      'cuid': 'abc',
      'userId': 7,
      'email': 'jamie@example.com',
      'inventory': 'pc',
      'controllers': 0,
      'startTime': '2026-11-24T14:00:00.000Z',
      'endTime': '2026-11-24T15:00:00.000Z',
      'status': 'RESERVED',
      'user': {
        'name': 'Jamie',
        'activeNotes': [
          {
            'id': 1,
            'type': 'NOTE',
            'content': 'Vriendelijk',
            'authorName': null,
            'createdAt': '2026-11-20T10:00:00.000Z',
            'expiresAt': null,
          },
          {
            'id': 2,
            'type': 'BLOCK',
            'content': 'Headset beschadigd',
            'authorName': 'Staff',
            'createdAt': '2026-11-22T10:00:00.000Z',
            'expiresAt': '2026-11-30T17:00:00.000Z',
          },
        ],
      },
    });

    expect(r.activeNotes.map((n) => n.type), [NoteType.block, NoteType.note]);
    expect(r.worstNote, NoteType.block);
    expect(r.isBlocked, isTrue);
    // A note's end is a real moment, so it keeps its instant instead of being read as wall-clock time
    expect(r.activeNotes.first.expiresAt!.toUtc(), DateTime.utc(2026, 11, 30, 17));
    expect(r.activeNotes.last.expiresAt, isNull);
  });

  test('a reservation without notes is not flagged', () {
    final r = VerifiedReservation.fromJson({
      'email': 'jamie@example.com',
      'inventory': 'pc',
      'startTime': '2026-11-24T14:00:00.000Z',
      'endTime': '2026-11-24T15:00:00.000Z',
      'status': 'PRESENT',
    });
    expect(r.activeNotes, isEmpty);
    expect(r.worstNote, isNull);
    expect(r.isBlocked, isFalse);
  });

  test('explains a blocked account, with the end when known', () {
    expect(translateApiMessage('Account blocked'), accountBlockedMessage);
    expect(accountBlockedUntil(null), accountBlockedMessage);
    expect(accountBlockedUntil(DateTime.utc(2026, 11, 30, 17)), contains('2026'));
  });
}
