import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/wall_clock.dart';
import '../../widgets/common.dart';
import '../../widgets/pickers.dart';

/// Create a reservation for someone on the spot, or edit an existing one.
/// Staff reservations skip the member restrictions (advance days, daily limit).
class ReservationFormScreen extends StatefulWidget {
  const ReservationFormScreen({super.key, this.reservation, required this.initialDay});

  final AdminReservation? reservation;
  final DateTime initialDay;

  @override
  State<ReservationFormScreen> createState() => _ReservationFormScreenState();
}

class _ReservationFormScreenState extends State<ReservationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  late final TextEditingController _sNumber;
  late Hardware _hardware;
  late int _controllers;
  late DateTime _day;
  late int _start;
  late int _end;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.reservation != null;

  @override
  void initState() {
    super.initState();
    final r = widget.reservation;
    _email = TextEditingController(text: r?.email ?? '');
    _sNumber = TextEditingController(text: r?.hasSNumber ?? false ? r!.sNumber : '');
    _hardware = r?.hardware ?? Hardware.pc;
    _controllers = r?.controllers ?? 0;
    _day = r == null ? widget.initialDay : DateTime.utc(r.start.year, r.start.month, r.start.day);
    _start = r == null ? _nextHalfHour() : minutesOfDay(r.start);
    _end = r == null ? (_start + 60).clamp(0, 24 * 60 - 1) : minutesOfDay(r.end);
  }

  static int _nextHalfHour() {
    final m = minutesOfDay(wallClockNow());
    return ((m ~/ 30) + 1) * 30 % (24 * 60);
  }

  @override
  void dispose() {
    _email.dispose();
    _sNumber.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_end <= _start) {
      setState(() => _error = 'De eindtijd moet na de starttijd liggen.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final body = <String, dynamic>{
      'email': _email.text.trim(),
      if (_sNumber.text.trim().isNotEmpty) 'sNumber': _sNumber.text.trim(),
      'inventory': _hardware.key,
      'controllers': _controllers,
      'startTime': wallClockIso(_day, _start),
      'endTime': wallClockIso(_day, _end),
    };

    final api = AppScope.apiOf(context);
    try {
      if (_isEdit) {
        await api.adminUpdateReservation(widget.reservation!.id, body);
      } else {
        await api.adminCreateReservation(body);
      }
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      showMessage(context, _isEdit ? 'Reservatie bijgewerkt.' : 'Reservatie aangemaakt.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        title: Text(_isEdit ? 'Reservatie bewerken' : 'Nieuwe reservatie'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text(
                      'Opslaan',
                      style: TextStyle(fontWeight: FontWeight.w700, color: HubColors.red),
                    ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: HubColors.red.withValues(alpha: 0.1),
                  border: Border.all(color: HubColors.red.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(_error!, style: text.bodyMedium?.copyWith(color: HubColors.danger)),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(
                labelText: 'E-mailadres',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              validator: (v) => (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()))
                  ? 'Vul een geldig e-mailadres in'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _sNumber,
              decoration: const InputDecoration(
                labelText: 'S-nummer (optioneel)',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              autocorrect: false,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 24),
            _FieldLabel('Hardware'),
            SegmentedButton<Hardware>(
              showSelectedIcon: false,
              segments: [
                for (final h in Hardware.values)
                  ButtonSegment(value: h, label: Text(h.shortLabel), icon: Icon(hardwareIcon(h))),
              ],
              selected: {_hardware},
              onSelectionChanged: (s) => setState(() => _hardware = s.first),
            ),
            const SizedBox(height: 20),
            _FieldLabel('Controllers'),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [for (var n = 0; n <= 4; n++) ButtonSegment(value: n, label: Text('$n'))],
              selected: {_controllers},
              onSelectionChanged: (s) => setState(() => _controllers = s.first),
            ),
            const SizedBox(height: 20),
            _FieldLabel('Moment'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.calendar_today_rounded),
                    title: const Text('Datum'),
                    trailing: Text(formatShortDate(_day), style: text.titleSmall),
                    onTap: () async {
                      final picked = await pickDate(context, initial: _day);
                      if (picked != null) setState(() => _day = picked);
                    },
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.login_rounded),
                    title: const Text('Starttijd'),
                    trailing: Text(formatMinutes(_start), style: text.titleSmall),
                    onTap: () async {
                      final picked = await pickTime(context, initialMinutes: _start);
                      if (picked == null) return;
                      setState(() {
                        final length = _end - _start;
                        _start = picked;
                        // Keep the same length when the start moves past the end.
                        if (_end <= _start) _end = (_start + (length > 0 ? length : 60)).clamp(0, 24 * 60 - 1);
                      });
                    },
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded),
                    title: const Text('Eindtijd'),
                    trailing: Text(formatMinutes(_end), style: text.titleSmall),
                    onTap: () async {
                      final picked = await pickTime(context, initialMinutes: _end);
                      if (picked != null) setState(() => _end = picked);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: HubColors.textMuted, letterSpacing: 1.2),
      ),
    );
  }
}
