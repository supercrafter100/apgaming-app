import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

bool _isIos(BuildContext context) => Theme.of(context).platform == TargetPlatform.iOS;

/// Date picker that looks native on both platforms. Returns a wall-clock (UTC) date.
Future<DateTime?> pickDate(BuildContext context, {required DateTime initial, DateTime? first, DateTime? last}) async {
  final firstDate = first ?? DateTime(2020);
  final lastDate = last ?? DateTime(2100);
  final local = DateTime(initial.year, initial.month, initial.day);

  final DateTime? picked;
  if (_isIos(context)) {
    picked = await _cupertinoPicker(
      context,
      initial: local,
      mode: CupertinoDatePickerMode.date,
      minimumDate: firstDate,
      maximumDate: lastDate,
    );
  } else {
    picked = await showDatePicker(context: context, initialDate: local, firstDate: firstDate, lastDate: lastDate);
  }
  return picked == null ? null : DateTime.utc(picked.year, picked.month, picked.day);
}

/// Time picker (24h) that looks native on both platforms. Works in minutes after midnight.
Future<int?> pickTime(BuildContext context, {required int initialMinutes}) async {
  if (_isIos(context)) {
    final now = DateTime.now();
    final picked = await _cupertinoPicker(
      context,
      initial: DateTime(now.year, now.month, now.day, initialMinutes ~/ 60, (initialMinutes % 60) ~/ 5 * 5),
      mode: CupertinoDatePickerMode.time,
      minuteInterval: 5,
    );
    return picked == null ? null : picked.hour * 60 + picked.minute;
  }

  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initialMinutes ~/ 60, minute: initialMinutes % 60),
    builder: (context, child) =>
        MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
  );
  return picked == null ? null : picked.hour * 60 + picked.minute;
}

Future<DateTime?> _cupertinoPicker(
  BuildContext context, {
  required DateTime initial,
  required CupertinoDatePickerMode mode,
  DateTime? minimumDate,
  DateTime? maximumDate,
  int minuteInterval = 1,
}) {
  var value = initial;
  return showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (context) => Container(
      height: 300,
      color: HubColors.surfaceRaised,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(child: const Text('Annuleren'), onPressed: () => Navigator.pop(context)),
                CupertinoButton(
                  child: const Text('Gereed', style: TextStyle(fontWeight: FontWeight.w600)),
                  onPressed: () => Navigator.pop(context, value),
                ),
              ],
            ),
            Expanded(
              child: CupertinoTheme(
                data: const CupertinoThemeData(brightness: Brightness.dark),
                child: CupertinoDatePicker(
                  mode: mode,
                  initialDateTime: initial,
                  minimumDate: minimumDate,
                  maximumDate: maximumDate,
                  minuteInterval: minuteInterval,
                  use24hFormat: true,
                  onDateTimeChanged: (v) => value = v,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
