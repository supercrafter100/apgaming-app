import 'package:ap_gaming_app/api/api_client.dart';
import 'package:ap_gaming_app/api/models.dart';
import 'package:ap_gaming_app/screens/admin/qr_scan_screen.dart';
import 'package:ap_gaming_app/util/wall_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    expect(
      translateApiMessage('You can only make two reservations per day'),
      'Je kan maximaal twee reservaties per dag maken.',
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
}
