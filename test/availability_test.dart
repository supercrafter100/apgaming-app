import 'package:ap_gaming_app/api/models.dart';
import 'package:ap_gaming_app/reservations/availability.dart';
import 'package:flutter_test/flutter_test.dart';

// Thursday 22 October 2026, wall-clock
final thursday = DateTime.utc(2026, 10, 22);

TimetableEntry open(int dayOfWeek, int from, int to) =>
    TimetableEntry(dayOfWeek: dayOfWeek, startMinutes: from * 60, endMinutes: to * 60, isOpen: true);

void main() {
  final base = Availability(
    timetable: [open(4, 12, 15), open(5, 10, 12)], // Thursday and Friday
    inventory: {'pc': 1, 'ps5': 1, 'switch': 0, 'controller': 8, 'Nintendo Controllers': 4},
  );

  test('offers start times every 30 minutes that fit in the opening hours', () {
    final times = base.startTimes(thursday, 60, Hardware.pc, now: DateTime.utc(2026, 10, 21, 9));

    expect(times, [12 * 60, 12 * 60 + 30, 13 * 60, 13 * 60 + 30, 14 * 60]);
  });

  test('skips start times that already passed today', () {
    final times = base.startTimes(thursday, 60, Hardware.pc, now: DateTime.utc(2026, 10, 22, 13, 0));

    expect(times, [13 * 60 + 30, 14 * 60]);
  });

  test('hides start times where all hardware of that type is taken', () {
    final day = base.forDay(
      occupied: [InventoryWindow(inventory: 'pc', startMinutes: 13 * 60, endMinutes: 14 * 60)],
      adjustments: const [],
    );

    final times = day.startTimes(thursday, 60, Hardware.pc, now: DateTime.utc(2026, 10, 21));

    expect(times, [12 * 60, 14 * 60]);
  });

  test('applies inventory adjustments', () {
    final day = base.forDay(
      occupied: [InventoryWindow(inventory: 'pc', startMinutes: 13 * 60, endMinutes: 14 * 60)],
      adjustments: [InventoryWindow(inventory: 'pc', startMinutes: 12 * 60, endMinutes: 15 * 60, quantity: 1)],
    );

    expect(day.startTimes(thursday, 60, Hardware.pc, now: DateTime.utc(2026, 10, 21)), hasLength(5));
  });

  test('bookable days are today (if open) plus the first next open day', () {
    // Wednesday — not open, so only the first upcoming open day (Thursday)
    final days = base.bookableDays(now: DateTime.utc(2026, 10, 21, 18));
    expect(days, [thursday]);

    // Thursday — open today, so today + first next open day (Friday)
    final daysFromThursday = base.bookableDays(now: DateTime.utc(2026, 10, 22, 9));
    expect(daysFromThursday, [thursday, DateTime.utc(2026, 10, 23)]);
  });

  test('knows which hardware is offered and how many controllers it has', () {
    expect(base.offers(Hardware.ps5), isTrue);
    expect(base.offers(Hardware.nintendoSwitch), isFalse);
    expect(base.maxControllers(Hardware.ps5), 8);
    expect(base.maxControllers(Hardware.nintendoSwitch), 4);
  });
}
