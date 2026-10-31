import '../util/wall_clock.dart';
import 'api_client.dart';
import 'models.dart';

/// Typed access to the AP Gaming Hub backend endpoints the app uses.
class HubApi {
  HubApi(this._client);

  final ApiClient _client;

  // --------------- Auth ---------------

  Future<String> exchangeLoginCode(String code, String verifier) async {
    final json = await _client.post('/auth/mobile/token', {'code': code, 'verifier': verifier});
    return (json as Map<String, dynamic>)['token'] as String;
  }

  Future<Profile> profile() async => Profile.fromJson(await _client.get('/auth/profile') as Map<String, dynamic>);

  Future<LinkedProviders> linkedProviders() async =>
      LinkedProviders.fromJson(await _client.get('/auth/links') as Map<String, dynamic>);

  // --------------- Member reservations ---------------

  Future<MyReservations> myReservations() async =>
      MyReservations.fromJson(await _client.get('/reservations/me') as Map<String, dynamic>);

  Future<void> cancelMyReservation(String cuid) => _client.patch('/reservations/me/$cuid/cancel');

  Future<void> createReservation({
    required Hardware hardware,
    required int controllers,
    required DateTime day,
    required int startMinutes,
    required int endMinutes,
  }) => _client.post('/reservations', {
    'inventory': hardware.key,
    'controllers': controllers,
    'startTime': wallClockIso(day, startMinutes),
    'endTime': wallClockIso(day, endMinutes),
  });

  // --------------- Availability (public) ---------------

  Future<List<TimetableEntry>> timetable() async =>
      (await _client.get('/timetable') as List).map((e) => TimetableEntry.fromJson(e as Map<String, dynamic>)).toList();

  /// Inventory counts keyed like the settings: pc, ps5, switch, controller, Nintendo Controllers.
  Future<Map<String, int>> inventory() async {
    final settings = await _client.get('/settings/inventory') as List;
    return {
      for (final s in settings.cast<Map<String, dynamic>>()) s['key'] as String: int.tryParse('${s['value']}') ?? 0,
    };
  }

  Future<List<InventoryWindow>> occupiedSlots(DateTime day) async =>
      (await _client.get('/reservations/slots', query: {'date': dateKey(day)}) as List)
          .map((e) => InventoryWindow.slot(e as Map<String, dynamic>))
          .toList();

  Future<List<InventoryWindow>> adjustments(DateTime day) async =>
      (await _client.get('/reservations/adjustments', query: {'date': dateKey(day)}) as List)
          .map((e) => InventoryWindow.adjustment(e as Map<String, dynamic>))
          .toList();

  // --------------- Push notifications ---------------

  /// Registers (or updates) this phone; returns whether reservation reminders are on for it.
  Future<bool> registerPushDevice({required String fid, required String platform, bool? reservationReminders}) async {
    final json = await _client.post('/notifications/devices', {
      'fid': fid,
      'platform': platform,
      'reservationReminders': ?reservationReminders,
    });
    return (json as Map<String, dynamic>)['reservationReminders'] as bool? ?? true;
  }

  Future<void> unregisterPushDevice(String fid) => _client.delete('/notifications/devices/${Uri.encodeComponent(fid)}');

  // --------------- Staff ---------------

  Future<List<AdminReservation>> reservationsOn(DateTime day) async {
    final json = await _client.get('/reservations', query: {'date': dateKey(day)}) as List;
    return json
        .map((e) => AdminReservation.fromJson(e as Map<String, dynamic>))
        // The server filters by its own timezone; keep exactly the wall-clock day.
        .where((r) => isSameDay(r.start, day))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  Future<void> updateStatus(int id, ReservationStatus status) =>
      _client.patch('/reservations/$id/status', {'status': status.key});

  Future<void> deleteReservation(int id) => _client.delete('/reservations/$id');

  Future<void> adminCreateReservation(Map<String, dynamic> body) => _client.post('/reservations/admin', body);

  Future<void> adminUpdateReservation(int id, Map<String, dynamic> body) => _client.patch('/reservations/$id', body);

  /// Marks the reservation as present when it was still reserved.
  Future<VerifiedReservation> verify(String cuid) async => VerifiedReservation.fromJson(
    await _client.get('/reservations/verify/${Uri.encodeComponent(cuid)}') as Map<String, dynamic>,
  );

  Future<List<AdminReservation>> noShows() async => (await _client.get('/reservations/no-shows') as List)
      .map((e) => AdminReservation.fromJson(e as Map<String, dynamic>))
      .toList();

  Future<void> unblockUser(int userId) => _client.patch('/reservations/$userId/no-show');

  Future<void> resetAllNoShows() => _client.patch('/reservations/no-shows/reset');
}
