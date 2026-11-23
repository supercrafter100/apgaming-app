import '../util/wall_clock.dart';

enum Hardware {
  pc('pc', 'PC', 'Gaming PC'),
  ps5('ps5', 'PS5', 'PlayStation 5'),
  nintendoSwitch('switch', 'Switch', 'Nintendo Switch');

  const Hardware(this.key, this.shortLabel, this.label);

  final String key;
  final String shortLabel;
  final String label;

  bool get isConsole => this != pc;

  /// Settings key holding how many controllers can be handed out with this hardware.
  String get controllerInventoryKey => this == nintendoSwitch ? 'Nintendo Controllers' : 'controller';

  static Hardware fromKey(String key) => values.firstWhere((h) => h.key == key, orElse: () => pc);
}

enum ReservationStatus {
  reserved('RESERVED'),
  present('PRESENT'),
  cancelled('CANCELLED'),
  noShow('NO_SHOW');

  const ReservationStatus(this.key);

  final String key;

  static ReservationStatus fromKey(String key) => values.firstWhere((s) => s.key == key, orElse: () => reserved);
}

/// The kinds of notes staff keep about someone, most serious last.
enum NoteType {
  note('NOTE'),
  warning('WARNING'),
  block('BLOCK');

  const NoteType(this.key);

  final String key;

  /// Higher is more serious.
  int get severity => index;

  static NoteType fromKey(String key) => values.firstWhere((t) => t.key == key, orElse: () => note);
}

/// A note about someone that still counts: a plain note, a warning, or a block that keeps them off the site.
class ActiveNote {
  ActiveNote({
    required this.id,
    required this.type,
    required this.content,
    required this.authorName,
    required this.createdAt,
    required this.expiresAt,
  });

  factory ActiveNote.fromJson(Map<String, dynamic> json) => ActiveNote(
    id: json['id'] as int,
    type: NoteType.fromKey(json['type'] as String),
    content: json['content'] as String,
    authorName: json['authorName'] as String?,
    // Real moments, unlike reservation times: shown in the phone's own time zone.
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    expiresAt: json['expiresAt'] == null ? null : DateTime.parse(json['expiresAt'] as String).toLocal(),
  );

  final int id;
  final NoteType type;
  final String content;
  final String? authorName;
  final DateTime createdAt;

  /// When the note stops counting; null keeps it active until staff end it.
  final DateTime? expiresAt;
}

List<ActiveNote> _activeNotes(Object? json) =>
    (json as List? ?? const []).map((n) => ActiveNote.fromJson(n as Map<String, dynamic>)).toList()
      ..sort((a, b) => b.type.severity.compareTo(a.type.severity));

/// Shared by everything that carries someone's active notes.
mixin HasActiveNotes {
  List<ActiveNote> get activeNotes;

  /// The most serious note type, which decides how someone is flagged; null without notes.
  NoteType? get worstNote => activeNotes.isEmpty ? null : activeNotes.first.type;
  bool get isBlocked => worstNote == NoteType.block;
}

class Profile {
  Profile({
    required this.id,
    required this.name,
    required this.email,
    required this.sNumber,
    required this.isAdmin,
    required this.roles,
    required this.permissions,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as int,
    name: json['name'] as String?,
    email: json['email'] as String,
    sNumber: json['sNumber'] as String? ?? '',
    isAdmin: json['isAdmin'] as bool? ?? false,
    roles: List<String>.from(json['roles'] as List? ?? const []),
    permissions: Set<String>.from(json['permissions'] as List? ?? const []),
  );

  final int id;
  final String? name;
  final String email;
  final String sNumber;
  final bool isAdmin;
  final List<String> roles;
  final Set<String> permissions;

  String get displayName => (name?.isNotEmpty ?? false) ? name! : email;
  bool get hasSNumber => sNumber.isNotEmpty && sNumber != 'N/A';

  bool can(String permission) => permissions.contains(permission);
  bool get canManageReservations => can('reservations.manage');
  bool get canManageNoShows => canManageReservations || can('reservations.noshows.manage');
}

class MyReservation {
  MyReservation({
    required this.cuid,
    required this.hardware,
    required this.controllers,
    required this.start,
    required this.end,
    required this.status,
  });

  factory MyReservation.fromJson(Map<String, dynamic> json) => MyReservation(
    cuid: json['cuid'] as String,
    hardware: Hardware.fromKey(json['inventory'] as String),
    controllers: json['controllers'] as int? ?? 0,
    start: parseWallClock(json['startTime'] as String),
    end: parseWallClock(json['endTime'] as String),
    status: ReservationStatus.fromKey(json['status'] as String),
  );

  final String cuid;
  final Hardware hardware;
  final int controllers;
  final DateTime start;
  final DateTime end;
  final ReservationStatus status;

  bool get isActive =>
      (status == ReservationStatus.reserved || status == ReservationStatus.present) && end.isAfter(wallClockNow());
  bool get canCancel => status == ReservationStatus.reserved && start.isAfter(wallClockNow());
}

class MyReservations {
  MyReservations({
    required this.reservations,
    required this.noShowCount,
    required this.noShowLimit,
    required this.isBlocked,
  });

  factory MyReservations.fromJson(Map<String, dynamic> json) => MyReservations(
    reservations: (json['reservations'] as List).map((r) => MyReservation.fromJson(r as Map<String, dynamic>)).toList(),
    noShowCount: json['noShowCount'] as int? ?? 0,
    noShowLimit: json['noShowLimit'] as int? ?? 3,
    isBlocked: json['isBlocked'] as bool? ?? false,
  );

  final List<MyReservation> reservations;
  final int noShowCount;
  final int noShowLimit;
  final bool isBlocked;

  /// Soonest first.
  List<MyReservation> get upcoming =>
      reservations.where((r) => r.isActive).toList()..sort((a, b) => a.start.compareTo(b.start));

  /// Most recent first (the API already returns newest first).
  List<MyReservation> get history => reservations.where((r) => !r.isActive).toList();
}

/// A reservation as seen by staff, including who made it.
/// Someone staff can book a reservation for, found through the person search.
class ReservationPerson {
  ReservationPerson({
    required this.id,
    required this.name,
    required this.email,
    required this.sNumber,
    this.reservationCount = 0,
  });

  factory ReservationPerson.fromJson(Map<String, dynamic> json) => ReservationPerson(
    id: json['id'] as int,
    name: json['name'] as String?,
    email: json['email'] as String,
    sNumber: json['sNumber'] as String? ?? '',
    reservationCount: json['reservationCount'] as int? ?? 0,
  );

  final int id;
  final String? name;
  final String email;
  final String sNumber;
  final int reservationCount;

  bool get hasName => name?.trim().isNotEmpty ?? false;
  bool get hasSNumber => sNumber.isNotEmpty && sNumber != 'N/A';

  /// The name when known, else the email address.
  String get displayName => hasName ? name! : email;

  /// Email and student number, without repeating what [displayName] shows.
  String get details => [if (hasName) email, if (hasSNumber) sNumber].join(' · ');
}

class AdminReservation with HasActiveNotes {
  AdminReservation({
    required this.id,
    required this.cuid,
    required this.userId,
    required this.email,
    required this.userName,
    required this.sNumber,
    required this.reservationCount,
    required this.hardware,
    required this.controllers,
    required this.start,
    required this.end,
    required this.status,
    this.activeNotes = const [],
  });

  factory AdminReservation.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return AdminReservation(
      id: json['id'] as int,
      cuid: json['cuid'] as String,
      userId: json['userId'] as int,
      email: json['email'] as String,
      userName: user?['name'] as String?,
      sNumber: user?['sNumber'] as String?,
      reservationCount: user?['reservationCount'] as int?,
      hardware: Hardware.fromKey(json['inventory'] as String),
      controllers: json['controllers'] as int? ?? 0,
      start: parseWallClock(json['startTime'] as String),
      end: parseWallClock(json['endTime'] as String),
      status: ReservationStatus.fromKey(json['status'] as String),
      activeNotes: _activeNotes(user?['activeNotes']),
    );
  }

  final int id;
  final String cuid;
  final int userId;
  final String email;
  final String? userName;
  final String? sNumber;
  final int? reservationCount;
  final Hardware hardware;
  final int controllers;
  final DateTime start;
  final DateTime end;
  final ReservationStatus status;
  @override
  final List<ActiveNote> activeNotes;

  String get displayName => (userName?.isNotEmpty ?? false) ? userName! : email;
  bool get hasSNumber => (sNumber?.isNotEmpty ?? false) && sNumber != 'N/A';
  bool get isFirstVisit => (reservationCount ?? 0) <= 1;

  bool matches(String query) {
    final q = query.toLowerCase();
    return email.toLowerCase().contains(q) ||
        (userName?.toLowerCase().contains(q) ?? false) ||
        (sNumber?.toLowerCase().contains(q) ?? false);
  }
}

class VerifiedReservation with HasActiveNotes {
  VerifiedReservation({
    required this.email,
    required this.sNumber,
    required this.hardware,
    required this.controllers,
    required this.start,
    required this.end,
    required this.status,
    this.activeNotes = const [],
  });

  factory VerifiedReservation.fromJson(Map<String, dynamic> json) => VerifiedReservation(
    email: json['email'] as String,
    sNumber: json['sNumber'] as String? ?? '',
    hardware: Hardware.fromKey(json['inventory'] as String),
    controllers: json['controllers'] as int? ?? 0,
    start: parseWallClock(json['startTime'] as String),
    end: parseWallClock(json['endTime'] as String),
    status: ReservationStatus.fromKey(json['status'] as String),
    activeNotes: _activeNotes(json['activeNotes']),
  );

  final String email;
  final String sNumber;
  final Hardware hardware;
  final int controllers;
  final DateTime start;
  final DateTime end;
  final ReservationStatus status;
  @override
  final List<ActiveNote> activeNotes;
}

class TimetableEntry {
  TimetableEntry({required this.dayOfWeek, required this.startMinutes, required this.endMinutes, required this.isOpen});

  factory TimetableEntry.fromJson(Map<String, dynamic> json) => TimetableEntry(
    dayOfWeek: json['dayOfWeek'] as int,
    startMinutes: minutesOfDay(parseWallClock(json['startTime'] as String)),
    endMinutes: minutesOfDay(parseWallClock(json['endTime'] as String)),
    isOpen: json['type'] == 'OPEN',
  );

  /// 0 = Sunday … 6 = Saturday, like JavaScript's Date.getDay().
  final int dayOfWeek;
  final int startMinutes;
  final int endMinutes;
  final bool isOpen;
}

/// An occupied (or adjusted) piece of inventory during a time window on one day.
class InventoryWindow {
  InventoryWindow({required this.inventory, required this.startMinutes, required this.endMinutes, this.quantity = 1});

  factory InventoryWindow.slot(Map<String, dynamic> json) => InventoryWindow(
    inventory: json['inventory'] as String,
    startMinutes: minutesOfDay(parseWallClock(json['startTime'] as String)),
    endMinutes: minutesOfDay(parseWallClock(json['endTime'] as String)),
  );

  factory InventoryWindow.adjustment(Map<String, dynamic> json) => InventoryWindow(
    inventory: json['inventory'] as String,
    startMinutes: minutesOfDay(parseWallClock(json['startTime'] as String)),
    endMinutes: minutesOfDay(parseWallClock(json['endTime'] as String)),
    quantity: json['quantity'] as int? ?? 0,
  );

  final String inventory;
  final int startMinutes;
  final int endMinutes;
  final int quantity;

  bool overlaps(int start, int end) => startMinutes < end && endMinutes > start;
}

class LinkedProviders {
  LinkedProviders({required this.microsoft});

  factory LinkedProviders.fromJson(Map<String, dynamic> json) =>
      LinkedProviders(microsoft: (json['microsoft'] as List? ?? const []).length);

  final int microsoft;
}
