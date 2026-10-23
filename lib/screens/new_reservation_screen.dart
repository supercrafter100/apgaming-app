import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app_scope.dart';
import '../reservations/availability.dart';
import '../theme.dart';
import '../util/futures.dart';
import '../util/wall_clock.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';

// Used by the website as well when a setting is missing.
const _defaultInventory = {'pc': 5, 'ps5': 1, 'switch': 1, 'controller': 8, 'Nintendo Controllers': 4};

const _stepTitles = ['Kies je hardware', 'Wanneer wil je komen?', 'Bevestigen'];

class NewReservationScreen extends StatefulWidget {
  const NewReservationScreen({super.key});

  @override
  State<NewReservationScreen> createState() => _NewReservationScreenState();
}

class _NewReservationScreenState extends State<NewReservationScreen> {
  Availability? _base;
  Availability? _day;
  String? _loadError;
  bool _dayLoading = false;

  int _step = 0;
  bool _forward = true;
  Hardware? _hardware;
  int _players = 0;
  bool _extraController = false;
  DateTime? _date;
  int _duration = durationOptions.first;
  int? _start;
  bool _acceptedTerms = false;

  bool _submitting = false;
  String? _submitError;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _loadBase();
  }

  Future<void> _loadBase() async {
    setState(() => _loadError = null);
    final api = AppScope.apiOf(context);
    try {
      final (timetable, inventory) = await both(api.timetable(), api.inventory());
      if (!mounted) return;
      setState(() => _base = Availability(timetable: timetable, inventory: {..._defaultInventory, ...inventory}));
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  Future<void> _selectDate(DateTime date) async {
    HapticFeedback.selectionClick();
    setState(() {
      _date = date;
      _start = null;
      _dayLoading = true;
    });
    final api = AppScope.apiOf(context);
    try {
      final (occupied, adjustments) = await both(api.occupiedSlots(date), api.adjustments(date));
      if (!mounted || _date != date) return;
      setState(() => _day = _base!.forDay(occupied: occupied, adjustments: adjustments));
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted && _date == date) setState(() => _dayLoading = false);
    }
  }

  void _selectHardware(Hardware hardware) {
    HapticFeedback.selectionClick();
    setState(() {
      if (hardware != _hardware) {
        _date = null;
        _start = null;
        _day = null;
      }
      _hardware = hardware;
      _players = 0;
      _extraController = false;
    });
  }

  bool get _canContinue => switch (_step) {
    0 => _hardware != null && (!_hardware!.isConsole || _players > 0),
    1 => _date != null && _start != null,
    _ => _acceptedTerms && !_submitting,
  };

  void _goTo(int step) {
    HapticFeedback.lightImpact();
    setState(() {
      _forward = step > _step;
      _step = step;
      _submitError = null;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await AppScope.apiOf(context).createReservation(
        hardware: _hardware!,
        controllers: _hardware!.isConsole ? _players : (_extraController ? 1 : 0),
        day: _date!,
        startMinutes: _start!,
        endMinutes: _start! + _duration,
      );
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _done = true);
    } on ApiException catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _submitError = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _SuccessView(onDone: () => Navigator.pop(context, true));

    final base = _base;
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(_step - 1);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
          title: const Text('Nieuwe reservatie'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: (_step + 1) / _stepTitles.length),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOut,
              builder: (_, value, _) => LinearProgressIndicator(value: value, minHeight: 3),
            ),
          ),
        ),
        body: base == null
            ? (_loadError == null
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : ErrorState(message: _loadError!, onRetry: _loadBase))
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  // Incoming step slides in from the direction we're heading, the old one leaves the other way.
                  final incoming = (child.key as ValueKey<int>).value == _step;
                  final dx = (incoming == _forward) ? 0.12 : -0.12;
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: ListView(
                  key: ValueKey(_step),
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  children: [
                    _StepHeader(step: _step),
                    const SizedBox(height: 20),
                    ...switch (_step) {
                      0 => _hardwareStep(base),
                      1 => _dateTimeStep(base),
                      _ => _confirmStep(),
                    },
                  ],
                ),
              ),
        bottomNavigationBar: base == null
            ? null
            : Frosted(
                color: const Color(0xCC020618),
                border: const Border(top: BorderSide(color: HubColors.border)),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        if (_step > 0) ...[
                          Expanded(
                            child: OutlinedButton(onPressed: () => _goTo(_step - 1), child: const Text('Vorige')),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: _canContinue ? (_step < 2 ? () => _goTo(_step + 1) : _submit) : null,
                            child: _submitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                  )
                                : Text(_step < 2 ? 'Volgende' : 'Reserveren'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  // --------------- Step 1: hardware ---------------

  List<Widget> _hardwareStep(Availability base) {
    final text = Theme.of(context).textTheme;
    final hardware = _hardware;
    final maxControllers = hardware == null ? 0 : base.maxControllers(hardware);
    const descriptions = {
      Hardware.pc: 'High-end gaming PC',
      Hardware.ps5: 'Next-gen console',
      Hardware.nintendoSwitch: 'Fun voor iedereen',
    };

    return [
      for (final h in Hardware.values) ...[
        _SelectableTile(
          icon: hardwareIcon(h),
          title: h.label,
          subtitle: base.offers(h) ? descriptions[h]! : 'Niet beschikbaar',
          selected: hardware == h,
          enabled: base.offers(h),
          onTap: () => _selectHardware(h),
        ),
        const SizedBox(height: 10),
      ],
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: switch (hardware) {
          null => const SizedBox(width: double.infinity),
          Hardware.pc => Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Card(
              child: SwitchListTile.adaptive(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                secondary: const Icon(Icons.gamepad_outlined),
                title: const Text('Extra controller'),
                subtitle: Text(
                  maxControllers < 1
                      ? 'Geen controllers meer beschikbaar'
                      : 'Ik wil een controller gebruiken aan de PC',
                  style: const TextStyle(color: HubColors.textSecondary),
                ),
                value: _extraController,
                onChanged: maxControllers < 1 && !_extraController
                    ? null
                    : (v) {
                        HapticFeedback.selectionClick();
                        setState(() => _extraController = v);
                      },
              ),
            ),
          ),
          _ => Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.group_outlined, size: 18, color: HubColors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Aantal spelers', style: text.titleSmall)),
                    Text('$maxControllers beschikbaar', style: text.labelSmall?.copyWith(color: HubColors.textMuted)),
                  ],
                ),
                const SizedBox(height: 10),
                HubSegmentedControl<int>(
                  segments: [for (var n = 1; n <= 4; n++) (n, '$n')],
                  selected: _players,
                  isEnabled: (n) => n <= maxControllers,
                  onChanged: (n) => setState(() => _players = n),
                ),
                if (maxControllers == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Geen controllers beschikbaar op dit moment.',
                      style: text.bodySmall?.copyWith(color: HubColors.danger),
                    ),
                  ),
              ],
            ),
          ),
        },
      ),
    ];
  }

  // --------------- Step 2: date & time ---------------

  List<Widget> _dateTimeStep(Availability base) {
    final text = Theme.of(context).textTheme;
    final days = base.bookableDays();
    final date = _date;
    final day = _day;
    final times = date != null && day != null && !_dayLoading
        ? day.startTimes(date, _duration, _hardware!)
        : const <int>[];

    return [
      _Label(icon: Icons.calendar_today_rounded, text: 'Datum'),
      if (days.isEmpty)
        Text(
          'De Gaming Hub is de komende dagen gesloten.',
          style: text.bodyMedium?.copyWith(color: HubColors.textSecondary),
        )
      else
        Row(
          children: [
            for (final (i, d) in days.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _DayCard(day: d, selected: date != null && isSameDay(d, date), onTap: () => _selectDate(d)),
              ),
            ],
            // Keep cards phone-sized when the hub is only open on a few of the days.
            for (var i = days.length; i < maxAdvanceDays + 1; i++) ...[const SizedBox(width: 8), const Spacer()],
          ],
        ),
      const SizedBox(height: 24),
      _Label(icon: Icons.timelapse_rounded, text: 'Duur'),
      HubSegmentedControl<int>(
        segments: [
          for (final d in durationOptions)
            (d, '${(d / 60).toStringAsFixed(d % 60 == 0 ? 0 : 1).replaceAll('.', ',')} uur'),
        ],
        selected: _duration,
        onChanged: (d) => setState(() {
          _duration = d;
          _start = null;
        }),
      ),
      const SizedBox(height: 24),
      if (date != null) ...[
        _Label(icon: Icons.schedule_rounded, text: 'Beschikbare tijdsloten'),
        if (_dayLoading)
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.7,
            children: [for (var i = 0; i < 8; i++) const Skeleton(radius: 12)],
          )
        else if (times.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              color: HubColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: HubColors.border),
            ),
            child: Text(
              'Geen momenten beschikbaar op deze dag met de gekozen duur.',
              style: text.bodyMedium?.copyWith(color: HubColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          )
        else
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.7,
            children: [
              for (final (i, t) in times.indexed)
                FadeSlideIn(
                  key: ValueKey('${dateKey(date)}-$_duration-$t'),
                  index: i ~/ 2,
                  offset: 8,
                  child: _TimeButton(
                    label: formatMinutes(t),
                    selected: _start == t,
                    onTap: () => setState(() => _start = t),
                  ),
                ),
            ],
          ),
      ],
    ];
  }

  // --------------- Step 3: confirm ---------------

  List<Widget> _confirmStep() {
    final text = Theme.of(context).textTheme;
    final hardware = _hardware!;
    final controllers = hardware.isConsole ? _players : (_extraController ? 1 : 0);

    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('OVERZICHT', style: text.labelSmall?.copyWith(color: HubColors.textMuted, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              DetailRow(icon: hardwareIcon(hardware), label: 'Hardware', value: hardware.label),
              DetailRow(icon: Icons.calendar_today_rounded, label: 'Datum', value: formatLongDate(_date!)),
              DetailRow(
                icon: Icons.schedule_rounded,
                label: 'Tijd',
                value: '${formatMinutes(_start!)} – ${formatMinutes(_start! + _duration)}',
              ),
              if (controllers > 0) DetailRow(icon: Icons.gamepad_outlined, label: 'Controllers', value: '$controllers'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: CheckboxListTile.adaptive(
          value: _acceptedTerms,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          onChanged: (v) {
            HapticFeedback.selectionClick();
            setState(() => _acceptedTerms = v ?? false);
          },
          title: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Ik ga akkoord met de '),
                TextSpan(
                  text: 'huisregels',
                  style: const TextStyle(
                    color: HubColors.red,
                    decoration: TextDecoration.underline,
                    decorationColor: HubColors.red,
                  ),
                  recognizer: TapGestureRecognizer()..onTap = () => openWebPage('/info'),
                ),
                const TextSpan(text: '. Ik draag zorg voor het materiaal en laat de plek netjes achter.'),
              ],
            ),
            style: text.bodyMedium?.copyWith(color: Colors.white70, height: 1.4),
          ),
        ),
      ),
      if (_submitError != null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: HubColors.red.withValues(alpha: 0.1),
            border: Border.all(color: HubColors.red.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: HubColors.danger, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_submitError!, style: text.bodyMedium?.copyWith(color: HubColors.danger)),
              ),
            ],
          ),
        ),
      ],
    ];
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(_stepTitles[step], style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: HubColors.border),
          ),
          child: Text(
            'STAP ${step + 1} / ${_stepTitles.length}',
            style: text.labelSmall?.copyWith(
              color: HubColors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: HubColors.textSecondary),
          const SizedBox(width: 8),
          Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: HubColors.textSecondary)),
        ],
      ),
    );
  }
}

class _SelectableTile extends StatelessWidget {
  const _SelectableTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Pressable(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected ? HubColors.red : HubColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? HubColors.red : HubColors.border),
            boxShadow: selected ? [BoxShadow(color: HubColors.red.withValues(alpha: 0.3), blurRadius: 20)] : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Row(
              children: [
                Icon(icon, size: 34, color: selected ? Colors.white : HubColors.textSecondary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        subtitle,
                        style: text.bodySmall?.copyWith(color: selected ? Colors.white70 : HubColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                AnimatedScale(
                  scale: selected ? 1 : 0.4,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  child: AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.check_circle_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.92,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? HubColors.red : HubColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? HubColors.red : HubColors.border),
          boxShadow: selected ? [BoxShadow(color: HubColors.red.withValues(alpha: 0.4), blurRadius: 14)] : null,
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : Colors.white70,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: HubColors.green.withValues(alpha: 0.1),
                    border: Border.all(color: HubColors.green.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.check_rounded, size: 52, color: HubColors.green),
                ),
              ),
              const SizedBox(height: 28),
              Text('Reservatie ontvangen!', style: text.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'Je krijgt een bevestiging met QR-code in je mailbox. Je vindt de code ook hier in de app bij je reservaties.',
                style: text.bodyLarge?.copyWith(color: HubColors.textSecondary, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              FilledButton(onPressed: onDone, child: const Text('Klaar')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Calendar-style day picker card: weekday, day number and "Vandaag"/"Morgen"/month.
class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.selected, required this.onTap});

  final DateTime day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final relative = formatRelativeDay(day);
    final caption = relative == 'Vandaag' || relative == 'Morgen' ? relative : DateFormat('MMM', 'nl_BE').format(day);
    final muted = selected ? Colors.white70 : HubColors.textSecondary;

    return Pressable(
      onTap: onTap,
      scale: 0.94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? HubColors.red : HubColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? HubColors.red : HubColors.border),
          boxShadow: selected ? [BoxShadow(color: HubColors.red.withValues(alpha: 0.35), blurRadius: 18)] : null,
        ),
        child: Column(
          children: [
            Text(
              DateFormat('EEE', 'nl_BE').format(day).toUpperCase().replaceAll('.', ''),
              style: text.labelSmall?.copyWith(color: muted, fontWeight: FontWeight.w700, letterSpacing: 1),
            ),
            const SizedBox(height: 2),
            Text('${day.day}', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text(
              caption,
              style: text.labelSmall?.copyWith(color: muted),
              maxLines: 1,
              overflow: TextOverflow.fade,
            ),
          ],
        ),
      ),
    );
  }
}
