import '../api/models.dart';
import '../util/wall_clock.dart';

/// Members can book today and up to this many days ahead (enforced by the backend too).
const maxAdvanceDays = 3;
const slotStepMinutes = 30;
const durationOptions = [60, 90, 120];

/// Same availability rules as the website's reservation flow.
class Availability {
  Availability({
    required this.timetable,
    required this.inventory,
    this.occupied = const [],
    this.adjustments = const [],
  });

  final List<TimetableEntry> timetable;
  final Map<String, int> inventory;
  final List<InventoryWindow> occupied;
  final List<InventoryWindow> adjustments;

  Availability forDay({required List<InventoryWindow> occupied, required List<InventoryWindow> adjustments}) =>
      Availability(timetable: timetable, inventory: inventory, occupied: occupied, adjustments: adjustments);

  bool offers(Hardware hardware) => (inventory[hardware.key] ?? 0) > 0;

  int maxControllers(Hardware hardware) => inventory[hardware.controllerInventoryKey] ?? 0;

  bool isOpenOn(DateTime day) => _openingHours(day).isNotEmpty;

  /// Today plus the next [maxAdvanceDays] days, limited to days the hub opens.
  List<DateTime> bookableDays({DateTime? now}) {
    final today = now ?? wallClockNow();
    return [for (var i = 0; i <= maxAdvanceDays; i++) DateTime.utc(today.year, today.month, today.day + i)]
        .where(isOpenOn)
        .toList();
  }

  /// Start times (minutes after midnight) for [day] where [hardware] is still free for [duration] minutes.
  List<int> startTimes(DateTime day, int duration, Hardware hardware, {DateTime? now}) {
    final current = now ?? wallClockNow();
    final isToday = isSameDay(day, current);
    final nowMinutes = minutesOfDay(current);

    final times = <int>[];
    for (final window in _openingHours(day)) {
      for (var start = window.startMinutes; start + duration <= window.endMinutes; start += slotStepMinutes) {
        if (isToday && start <= nowMinutes) continue;
        if (_isFree(hardware, start, start + duration)) times.add(start);
      }
    }
    return times;
  }

  List<TimetableEntry> _openingHours(DateTime day) {
    final dayOfWeek = day.weekday % 7; // Dart: Monday = 1 … Sunday = 7
    return timetable.where((e) => e.isOpen && e.dayOfWeek == dayOfWeek).toList();
  }

  bool _isFree(Hardware hardware, int start, int end) {
    final adjustment = adjustments
        .where((a) => a.inventory == hardware.key && a.overlaps(start, end))
        .fold<int>(0, (sum, a) => sum + a.quantity);
    final capacity = ((inventory[hardware.key] ?? 0) + adjustment).clamp(0, 1 << 30);
    final taken = occupied.where((r) => r.inventory == hardware.key && r.overlaps(start, end)).length;
    return taken < capacity;
  }
}
