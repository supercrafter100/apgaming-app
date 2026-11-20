import 'dart:async';

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
/// Staff pick someone who booked before, or add a new person by name.
/// Staff reservations skip the member restrictions (bookable days, daily limit).
class ReservationFormScreen extends StatefulWidget {
  const ReservationFormScreen({super.key, this.reservation, required this.initialDay});

  final AdminReservation? reservation;
  final DateTime initialDay;

  @override
  State<ReservationFormScreen> createState() => _ReservationFormScreenState();
}

class _ReservationFormScreenState extends State<ReservationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _sNumber = TextEditingController();

  /// The existing person the reservation is for; null while searching or adding a new person.
  ReservationPerson? _person;
  bool _addingPerson = false;
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
    if (r != null) {
      _person = ReservationPerson(id: r.userId, name: r.userName, email: r.email, sNumber: r.sNumber ?? '');
    }
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
    _name.dispose();
    _email.dispose();
    _sNumber.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_person == null && !_addingPerson) {
      setState(() => _error = 'Kies voor wie de reservatie is, of voeg een nieuwe persoon toe.');
      return;
    }
    if (_end <= _start) {
      setState(() => _error = 'De eindtijd moet na de starttijd liggen.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final person = _person;
    final samePerson = _isEdit && person != null && person.id == widget.reservation!.userId;
    final body = <String, dynamic>{
      if (person != null && !samePerson) 'userId': person.id,
      if (person == null) ...{
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        if (_sNumber.text.trim().isNotEmpty) 'sNumber': _sNumber.text.trim(),
      },
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
            _FieldLabel('Persoon'),
            if (_person != null)
              _ChosenPerson(person: _person!, onChange: () => setState(() => _person = null))
            else if (_addingPerson)
              _NewPersonFields(
                name: _name,
                email: _email,
                sNumber: _sNumber,
                onSearchInstead: () => setState(() => _addingPerson = false),
              )
            else
              _PersonSearch(
                onPicked: (person) => setState(() {
                  _person = person;
                  _error = null;
                }),
                onAddNew: (query) => setState(() {
                  _addingPerson = true;
                  _error = null;
                  if (query.contains('@')) {
                    _email.text = query;
                  } else {
                    _name.text = query;
                  }
                }),
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

/// The person the reservation is for, with a way to pick someone else.
class _ChosenPerson extends StatelessWidget {
  const _ChosenPerson({required this.person, required this.onChange});

  final ReservationPerson person;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.person_rounded),
        title: Text(person.displayName),
        subtitle: person.details.isEmpty ? null : Text(person.details),
        trailing: TextButton(onPressed: onChange, child: const Text('Wijzigen')),
      ),
    );
  }
}

/// Name, email and optional student number for someone who hasn't booked before.
class _NewPersonFields extends StatelessWidget {
  const _NewPersonFields({
    required this.name,
    required this.email,
    required this.sNumber,
    required this.onSearchInstead,
  });

  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController sNumber;
  final VoidCallback onSearchInstead;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Naam', prefixIcon: Icon(Icons.person_outline_rounded)),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Vul een naam in' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: email,
          decoration: const InputDecoration(labelText: 'E-mailadres', prefixIcon: Icon(Icons.alternate_email_rounded)),
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
          controller: sNumber,
          decoration: const InputDecoration(labelText: 'S-nummer (optioneel)', prefixIcon: Icon(Icons.badge_outlined)),
          autocorrect: false,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 8),
        Text(
          'Bestaat er al iemand met dit e-mailadres, dan komt de reservatie op die persoon.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HubColors.textMuted),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onSearchInstead,
            icon: const Icon(Icons.search_rounded),
            label: const Text('Toch iemand zoeken'),
          ),
        ),
      ],
    );
  }
}

/// Searches people who have an account, as you type.
class _PersonSearch extends StatefulWidget {
  const _PersonSearch({required this.onPicked, required this.onAddNew});

  final ValueChanged<ReservationPerson> onPicked;

  /// Called with what was typed, to prefill the new person's name or email.
  final ValueChanged<String> onAddNew;

  @override
  State<_PersonSearch> createState() => _PersonSearchState();
}

class _PersonSearchState extends State<_PersonSearch> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<ReservationPerson> _results = const [];
  bool _searching = false;
  String? _error;

  String get _term => _query.text.trim();

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    if (_term.length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), _search);
  }

  Future<void> _search() async {
    final term = _term;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await AppScope.apiOf(context).searchPeople(term);
      if (mounted && term == _term) setState(() => _results = results);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: HubColors.textMuted);
    final hasTerm = _term.length >= 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _query,
          onChanged: _onChanged,
          autocorrect: false,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Zoek op naam, e-mail of s-nummer',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: muted),
          ),
        if (hasTerm) ...[
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final person in _results) ...[
                  ListTile(
                    title: Text(person.displayName),
                    subtitle: person.details.isEmpty ? null : Text(person.details),
                    trailing: Text(
                      '${person.reservationCount} ${person.reservationCount == 1 ? 'reservatie' : 'reservaties'}',
                      style: muted,
                    ),
                    onTap: () => widget.onPicked(person),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                ],
                if (!_searching && _results.isEmpty && _error == null)
                  ListTile(title: Text('Niemand gevonden.', style: muted)),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_rounded, color: HubColors.red),
                  title: const Text(
                    'Nieuwe persoon toevoegen',
                    style: TextStyle(color: HubColors.red, fontWeight: FontWeight.w600),
                  ),
                  onTap: () => widget.onAddNew(_term),
                ),
              ],
            ),
          ),
        ] else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => widget.onAddNew(''),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Nieuwe persoon toevoegen'),
            ),
          ),
      ],
    );
  }
}
