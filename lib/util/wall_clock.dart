import 'package:intl/intl.dart';

// The backend stores reservation times as local wall-clock time tagged as UTC
// ("14:00 in Antwerp" is sent and stored as 14:00Z). Every DateTime in this app
// that represents a reservation time is therefore a UTC DateTime whose fields are
// read as-is, never converted with toLocal().

/// "Now" in the same convention as stored reservation times.
DateTime wallClockNow() {
  final now = DateTime.now();
  return DateTime.utc(now.year, now.month, now.day, now.hour, now.minute, now.second);
}

DateTime parseWallClock(String iso) => DateTime.parse(iso).toUtc();

/// Wall-clock date + minutes after midnight, serialized the way the web app does.
String wallClockIso(DateTime day, int minutes) =>
    DateTime.utc(day.year, day.month, day.day, minutes ~/ 60, minutes % 60).toIso8601String();

int minutesOfDay(DateTime t) => t.hour * 60 + t.minute;

String formatMinutes(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

String dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

final _longDate = DateFormat('EEEE d MMMM', 'nl_BE');
final _shortDate = DateFormat('EEE d MMM', 'nl_BE');
final _time = DateFormat('HH:mm', 'nl_BE');

String formatLongDate(DateTime d) => capitalize(_longDate.format(d));
String formatShortDate(DateTime d) => capitalize(_shortDate.format(d));
String formatTime(DateTime d) => _time.format(d);
String formatTimeRange(DateTime start, DateTime end) => '${formatTime(start)} – ${formatTime(end)}';

/// "Vandaag", "Morgen" or the long date, relative to the wall-clock today.
String formatRelativeDay(DateTime d) {
  final today = wallClockNow();
  if (isSameDay(d, today)) return 'Vandaag';
  if (isSameDay(d, today.add(const Duration(days: 1)))) return 'Morgen';
  if (isSameDay(d, today.subtract(const Duration(days: 1)))) return 'Gisteren';
  return formatLongDate(d);
}
