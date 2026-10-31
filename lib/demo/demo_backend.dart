import 'dart:convert';

import 'package:http/http.dart' as http;

import '../util/wall_clock.dart';

/// A stand-in for the platform API that keeps everything in memory, so the demo
/// never reaches the real backend or real people's data. It speaks the same JSON
/// and uses the same error messages, which means the screens run unchanged.
class DemoBackend extends http.BaseClient {
  DemoBackend({DateTime? now}) {
    _seed(now ?? wallClockNow());
  }

  /// Today's example booking, offered as a sample QR code on the scan screen.
  static const checkInCode = 'demo-checkin';

  static const _latency = Duration(milliseconds: 120);
  static const _noShowLimit = 3;
  static const _maxPerDay = 2;
  static const _minGap = Duration(minutes: 30);
  static const _maxAdvanceDays = 3;

  static const _inventory = {'pc': 5, 'ps5': 2, 'switch': 2, 'controller': 4, 'Nintendo Controllers': 4};

  final _me = _DemoUser(1000, 'Demo Gebruiker', 'demo@example.com', 's000000');
  final _users = <_DemoUser>[];
  final _reservations = <_DemoReservation>[];
  late DateTime _today;
  int _nextId = 1;

  void _seed(DateTime now) {
    _today = DateTime.utc(now.year, now.month, now.day);
    DateTime at(int dayOffset, int hour, [int minute = 0]) =>
        DateTime.utc(now.year, now.month, now.day + dayOffset, hour, minute);

    final robin = _DemoUser(1001, 'Robin Claes', 'robin.claes@example.com', 's100001');
    final noor = _DemoUser(1002, 'Noor Willems', 'noor.willems@example.com', 's100002');
    final sam = _DemoUser(1003, 'Sam Janssens', 'sam.janssens@example.com', 's100003');
    final lotte = _DemoUser(1004, 'Lotte Maes', 'lotte.maes@example.com', 's100004');
    _users.addAll([_me, robin, noor, sam, lotte]);

    void add(
      _DemoUser user,
      String inventory,
      DateTime start,
      DateTime end, {
      int controllers = 0,
      String status = 'RESERVED',
      String? cuid,
    }) {
      final id = _nextId++;
      _reservations.add(_DemoReservation(id, cuid ?? 'demo-$id', user, inventory, controllers, start, end, status));
    }

    // Your own reservations
    add(_me, 'ps5', at(1, 14), at(1, 15), controllers: 2);
    add(_me, 'pc', at(-3, 12), at(-3, 13), status: 'PRESENT');
    add(_me, 'switch', at(-7, 16), at(-7, 17), controllers: 1, status: 'NO_SHOW');
    add(_me, 'ps5', at(-10, 18), at(-10, 19), controllers: 2, status: 'CANCELLED');

    // Today's overview for the Gaming Hub manager; earlier sessions have already happened.
    String earlier(DateTime end, String status) => end.isBefore(now) ? status : 'RESERVED';
    add(robin, 'pc', at(0, 10), at(0, 11), status: earlier(at(0, 11), 'PRESENT'));
    add(noor, 'ps5', at(0, 12), at(0, 13, 30), controllers: 2, status: earlier(at(0, 13, 30), 'PRESENT'));
    add(sam, 'switch', at(0, 15), at(0, 16), controllers: 2, status: earlier(at(0, 16), 'NO_SHOW'));
    add(lotte, 'pc', at(0, 18), at(0, 20));
    add(robin, 'ps5', at(0, 21), at(0, 22), controllers: 1, cuid: checkInCode);

    // Tomorrow, and an earlier no-show for the manager to handle
    add(noor, 'pc', at(1, 11), at(1, 13));
    add(lotte, 'switch', at(1, 16), at(1, 17), controllers: 2);
    add(sam, 'pc', at(-2, 13), at(-2, 14), status: 'NO_SHOW');
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await Future<void>.delayed(_latency);

    final body = request is http.Request && request.body.isNotEmpty
        ? jsonDecode(request.body) as Map<String, dynamic>
        : const <String, dynamic>{};
    final segments = request.url.pathSegments;
    final path = segments.sublist(segments.indexOf('api') + 1);

    int status = 200;
    Object? result;
    try {
      result = _route(request.method, path, request.url.queryParameters, body);
    } on _DemoError catch (e) {
      status = e.status;
      result = {'message': e.message, 'statusCode': e.status};
    }

    return http.StreamedResponse(
      http.ByteStream.fromBytes(utf8.encode(jsonEncode(result))),
      status,
      headers: const {'content-type': 'application/json'},
    );
  }

  Object? _route(String method, List<String> path, Map<String, String> query, Map<String, dynamic> body) {
    return switch ((method, path)) {
      ('GET', ['auth', 'profile']) => {
        'id': _me.id,
        'name': _me.name,
        'email': _me.email,
        'sNumber': _me.sNumber,
        'isAdmin': false,
        'roles': ['Gaming Hub manager'],
        'permissions': ['reservations.manage'],
      },
      ('GET', ['auth', 'links']) => {
        'google': const <Object>[],
        'microsoft': [
          {'id': 1, 'ssoId': 'demo'},
        ],
      },
      ('GET', ['timetable']) => [
        for (var day = 0; day < 7; day++)
          {
            'dayOfWeek': day,
            'startTime': '1970-01-01T09:00:00.000Z',
            'endTime': '1970-01-01T23:00:00.000Z',
            'type': 'OPEN',
          },
      ],
      ('GET', ['settings', 'inventory']) => [
        for (final entry in _inventory.entries) {'key': entry.key, 'value': '${entry.value}'},
      ],
      ('GET', ['reservations', 'me']) => _myReservations(),
      ('GET', ['reservations', 'slots']) => [
        for (final r in _on(query['date']))
          if (r.isActive)
            {'inventory': r.inventory, 'startTime': r.start.toIso8601String(), 'endTime': r.end.toIso8601String()},
      ],
      ('GET', ['reservations', 'adjustments']) => const <Object>[],
      ('GET', ['reservations', 'no-shows']) => [
        for (final r in _reservations)
          if (r.status == 'NO_SHOW') _adminJson(r),
      ],
      ('GET', ['reservations', 'verify', final cuid]) => _verify(cuid),
      ('GET', ['reservations']) => [for (final r in _on(query['date'])) _adminJson(r)],
      ('POST', ['reservations', 'admin']) => _adminCreate(body),
      ('POST', ['reservations']) => _create(body),
      ('PATCH', ['reservations', 'no-shows', 'reset']) => _clearNoShows(),
      ('PATCH', ['reservations', 'me', final cuid, 'cancel']) => _cancel(cuid),
      ('PATCH', ['reservations', final id, 'status']) => _setStatus(id, body),
      ('PATCH', ['reservations', final userId, 'no-show']) => _clearNoShows(userId: int.parse(userId)),
      ('PATCH', ['reservations', final id]) => _adminUpdate(id, body),
      ('DELETE', ['reservations', final id]) => _delete(id),
      _ => throw _DemoError(404, 'Niet beschikbaar in de demo.'),
    };
  }

  Iterable<_DemoReservation> _on(String? date) => _reservations.where((r) => dateKey(r.start) == date);

  Map<String, dynamic> _myReservations() {
    final mine = _reservations.where((r) => r.user == _me).toList()..sort((a, b) => b.start.compareTo(a.start));
    final noShows = mine.where((r) => r.status == 'NO_SHOW').length;
    return {
      'reservations': [
        for (final r in mine)
          {
            'cuid': r.cuid,
            'inventory': r.inventory,
            'controllers': r.controllers,
            'startTime': r.start.toIso8601String(),
            'endTime': r.end.toIso8601String(),
            'status': r.status,
          },
      ],
      'noShowCount': noShows,
      'noShowLimit': _noShowLimit,
      'isBlocked': noShows >= _noShowLimit,
    };
  }

  Map<String, dynamic> _adminJson(_DemoReservation r) => {
    'id': r.id,
    'cuid': r.cuid,
    'userId': r.user.id,
    'email': r.user.email,
    'inventory': r.inventory,
    'controllers': r.controllers,
    'startTime': r.start.toIso8601String(),
    'endTime': r.end.toIso8601String(),
    'status': r.status,
    'user': {
      'id': r.user.id,
      'name': r.user.name,
      'sNumber': r.user.sNumber,
      'reservationCount': _reservations.where((other) => other.user == r.user).length,
    },
  };

  /// The same rules a member runs into on the real backend, with the same messages.
  Map<String, dynamic> _create(Map<String, dynamic> body) {
    final start = parseWallClock(body['startTime'] as String);
    final end = parseWallClock(body['endTime'] as String);
    final inventory = body['inventory'] as String;

    if (start.isBefore(wallClockNow())) throw _DemoError(400, 'Cannot reserve in the past');
    if (start.difference(_today).inDays > _maxAdvanceDays) {
      throw _DemoError(400, 'Reservations can only be made up to 3 days in advance');
    }

    final taken = _reservations.where((r) => r.isActive && r.inventory == inventory && r.overlaps(start, end)).length;
    if (taken >= (_inventory[inventory] ?? 0)) {
      throw _DemoError(400, 'All ${inventory}s are already reserved for this time slot');
    }

    final mine = _reservations.where((r) => r.user == _me);
    if (mine.where((r) => r.status == 'NO_SHOW').length >= _noShowLimit) {
      throw _DemoError(400, 'You already have three no-shows this semester.');
    }

    final active = mine.where((r) => r.isActive);
    if (active.any((r) => r.overlaps(start, end))) {
      throw _DemoError(400, 'You already have a reservation that overlaps with this time slot');
    }
    if (active.any((r) => r.overlaps(start.subtract(_minGap), end.add(_minGap)))) {
      throw _DemoError(400, 'You must have at least 30 minutes between reservations');
    }
    if (active.where((r) => isSameDay(r.start, start)).length >= _maxPerDay) {
      throw _DemoError(400, 'You can only make two reservations per day');
    }

    return _adminJson(_insert(_me, body, start, end));
  }

  Map<String, dynamic> _adminCreate(Map<String, dynamic> body) => _adminJson(
    _insert(
      _userFor(body),
      body,
      parseWallClock(body['startTime'] as String),
      parseWallClock(body['endTime'] as String),
    ),
  );

  _DemoReservation _insert(_DemoUser user, Map<String, dynamic> body, DateTime start, DateTime end) {
    final id = _nextId++;
    final reservation = _DemoReservation(
      id,
      'demo-$id',
      user,
      body['inventory'] as String,
      body['controllers'] as int? ?? 0,
      start,
      end,
      'RESERVED',
    );
    _reservations.add(reservation);
    return reservation;
  }

  _DemoUser _userFor(Map<String, dynamic> body) {
    final email = body['email'] as String;
    final sNumber = body['sNumber'] as String? ?? 'N/A';
    final known = _users.where((u) => u.email == email).firstOrNull;
    if (known != null) return known;
    final user = _DemoUser(1100 + _users.length, null, email, sNumber);
    _users.add(user);
    return user;
  }

  Map<String, dynamic> _adminUpdate(String id, Map<String, dynamic> body) {
    final reservation = _byId(id)
      ..user = _userFor(body)
      ..inventory = body['inventory'] as String
      ..controllers = body['controllers'] as int? ?? 0
      ..start = parseWallClock(body['startTime'] as String)
      ..end = parseWallClock(body['endTime'] as String);
    return _adminJson(reservation);
  }

  Map<String, dynamic> _cancel(String cuid) {
    final reservation = _byCuid(cuid);
    if (reservation.status == 'CANCELLED') throw _DemoError(400, 'Reservation is already cancelled');
    if (!reservation.start.isAfter(wallClockNow())) {
      throw _DemoError(400, 'You cannot cancel a reservation that has already started or passed');
    }
    reservation.status = 'CANCELLED';
    return {'success': true};
  }

  Map<String, dynamic> _verify(String cuid) {
    final reservation = _reservations.where((r) => r.cuid == cuid).firstOrNull;
    if (reservation == null || reservation.status == 'CANCELLED' || reservation.status == 'NO_SHOW') {
      throw _DemoError(404, 'Reservation not found');
    }
    if (reservation.status == 'RESERVED') reservation.status = 'PRESENT';
    return {
      'cuid': reservation.cuid,
      'email': reservation.user.email,
      'sNumber': reservation.user.sNumber,
      'inventory': reservation.inventory,
      'controllers': reservation.controllers,
      'startTime': reservation.start.toIso8601String(),
      'endTime': reservation.end.toIso8601String(),
      'status': reservation.status,
    };
  }

  Map<String, dynamic> _setStatus(String id, Map<String, dynamic> body) {
    final reservation = _byId(id)..status = body['status'] as String;
    return _adminJson(reservation);
  }

  Map<String, dynamic> _clearNoShows({int? userId}) {
    final noShows = _reservations.where((r) => r.status == 'NO_SHOW' && (userId == null || r.user.id == userId));
    final count = noShows.length;
    for (final r in noShows.toList()) {
      r.status = 'CANCELLED';
    }
    return {'count': count};
  }

  Map<String, dynamic> _delete(String id) {
    _reservations.remove(_byId(id));
    return {'success': true};
  }

  _DemoReservation _byId(String id) => _reservations.firstWhere(
    (r) => r.id == int.tryParse(id),
    orElse: () => throw _DemoError(404, 'Reservation not found'),
  );

  _DemoReservation _byCuid(String cuid) =>
      _reservations.firstWhere((r) => r.cuid == cuid, orElse: () => throw _DemoError(404, 'Reservation not found'));
}

class _DemoUser {
  _DemoUser(this.id, this.name, this.email, this.sNumber);

  final int id;
  final String? name;
  final String email;
  final String sNumber;
}

class _DemoReservation {
  _DemoReservation(this.id, this.cuid, this.user, this.inventory, this.controllers, this.start, this.end, this.status);

  final int id;
  final String cuid;
  _DemoUser user;
  String inventory;
  int controllers;
  DateTime start;
  DateTime end;
  String status;

  bool get isActive => status == 'RESERVED' || status == 'PRESENT';

  bool overlaps(DateTime otherStart, DateTime otherEnd) => start.isBefore(otherEnd) && end.isAfter(otherStart);
}

class _DemoError implements Exception {
  _DemoError(this.status, this.message);

  final int status;
  final String message;
}
