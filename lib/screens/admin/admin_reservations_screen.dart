import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/wall_clock.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import '../../widgets/pickers.dart';
import 'no_shows_screen.dart';
import 'qr_scan_screen.dart';
import 'reservation_form_screen.dart';

/// Day overview for the people keeping the hub open: who's coming, check-ins and no-shows.
class AdminReservationsScreen extends StatefulWidget {
  const AdminReservationsScreen({super.key});

  @override
  State<AdminReservationsScreen> createState() => _AdminReservationsScreenState();
}

class _AdminReservationsScreenState extends State<AdminReservationsScreen> {
  DateTime _day = _today();
  List<AdminReservation>? _reservations;
  String? _error;
  String _query = '';
  bool _showCancelled = false;

  static DateTime _today() {
    final now = wallClockNow();
    return DateTime.utc(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final day = _day;
    try {
      final reservations = await AppScope.apiOf(context).reservationsOn(day);
      if (!mounted || day != _day) return;
      setState(() {
        _reservations = reservations;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _changeDay(DateTime day) {
    HapticFeedback.selectionClick();
    setState(() {
      _day = day;
      _reservations = null;
      _error = null;
    });
    _load();
  }

  Future<void> _setStatus(AdminReservation r, ReservationStatus status) async {
    if (status == ReservationStatus.cancelled &&
        !await confirm(
          context,
          title: 'Reservatie annuleren?',
          message: 'De reservatie van ${r.displayName} wordt geannuleerd.',
          confirmLabel: 'Annuleer reservatie',
          cancelLabel: 'Terug',
          destructive: true,
        )) {
      return;
    }
    if (!mounted) return;
    try {
      await AppScope.apiOf(context).updateStatus(r.id, status);
      HapticFeedback.mediumImpact();
      if (mounted) showMessage(context, '${r.displayName}: ${statusLabel(status, staff: true).toLowerCase()}');
      _load();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _openForm([AdminReservation? reservation]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ReservationFormScreen(reservation: reservation, initialDay: _day),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openDetails(AdminReservation r) async {
    final action = await showModalBottomSheet<_SheetAction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AdminReservationSheet(reservation: r),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _SetStatus(:final status):
        await _setStatus(r, status);
      case _Edit():
        await _openForm(r);
      case _Delete():
        final ok = await confirm(
          context,
          title: 'Reservatie verwijderen?',
          message: 'Dit kan niet ongedaan worden. Gebruik "Geannuleerd" als je de geschiedenis wilt bewaren.',
          confirmLabel: 'Verwijderen',
          destructive: true,
        );
        if (!ok || !mounted) return;
        try {
          await AppScope.apiOf(context).deleteReservation(r.id);
          if (mounted) showMessage(context, 'Reservatie verwijderd.');
          _load();
        } on ApiException catch (e) {
          if (mounted) showMessage(context, e.message, error: true);
        }
    }
  }

  Future<void> _scan() async {
    await Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const QrScanScreen()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final profile = AppScope.authOf(context).profile!;
    final all = _reservations;
    final visible = all
        ?.where((r) => _showCancelled || r.status != ReservationStatus.cancelled)
        .where((r) => _query.isEmpty || r.matches(_query))
        .toList();

    return Scaffold(
      floatingActionButton: aboveTabBar(
        context,
        FloatingActionButton.extended(
          heroTag: null, // tabs live side by side in an IndexedStack
          onPressed: _scan,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Scan QR'),
        ),
      ),
      body: GlowBackground(
        intensity: 0.1,
        child: RefreshIndicator.adaptive(
          onRefresh: _load,
          color: HubColors.red,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              HubSliverAppBar(
                title: 'Beheer',
                actions: [
                  if (profile.canManageNoShows)
                    IconButton(
                      tooltip: 'No-shows',
                      icon: const Icon(Icons.person_off_outlined),
                      onPressed: () =>
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NoShowsScreen())),
                    ),
                  IconButton(tooltip: 'Nieuwe reservatie', icon: const Icon(Icons.add_rounded), onPressed: _openForm),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                sliver: SliverList.list(
                  children: [
                    _DaySwitcher(day: _day, onChanged: _changeDay),
                    const SizedBox(height: 12),
                    SearchBar(
                      hintText: 'Zoek op naam, e-mail of s-nummer',
                      leading: const Icon(Icons.search_rounded, color: HubColors.textSecondary),
                      elevation: const WidgetStatePropertyAll(0),
                      backgroundColor: const WidgetStatePropertyAll(HubColors.surface),
                      side: const WidgetStatePropertyAll(BorderSide(color: HubColors.border)),
                      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
                      onChanged: (v) => setState(() => _query = v.trim()),
                    ),
                    const SizedBox(height: 12),
                    if (all != null) _DaySummary(reservations: all),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilterChip(
                        label: const Text('Geannuleerd tonen'),
                        selected: _showCancelled,
                        onSelected: (v) => setState(() => _showCancelled = v),
                      ),
                    ),
                  ],
                ),
              ),
              if (visible == null && _error == null)
                SkeletonList(count: 4)
              else if (visible == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorState(message: _error!, onRetry: _load),
                )
              else if (visible.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.event_busy_outlined,
                    title: 'Geen reservaties',
                    message: 'Er zijn geen reservaties voor deze dag en filters.',
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      'Veeg naar rechts voor aanwezig, naar links voor afwezig',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: HubColors.textMuted),
                    ),
                  ),
                ),
                SliverPadding(
                  // Clear the FAB and the translucent tab bar.
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 96 + MediaQuery.paddingOf(context).bottom),
                  sliver: SliverList.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => FadeSlideIn(
                      key: ValueKey('${dateKey(_day)}-${visible[i].id}'),
                      index: i,
                      child: _SwipeableReservation(
                        reservation: visible[i],
                        onTap: () => _openDetails(visible[i]),
                        onStatus: (s) => _setStatus(visible[i], s),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DaySwitcher extends StatelessWidget {
  const _DaySwitcher({required this.day, required this.onChanged});

  final DateTime day;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Row(
        children: [
          IconButton(
            tooltip: 'Vorige dag',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => onChanged(day.subtract(const Duration(days: 1))),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final picked = await pickDate(context, initial: day);
                if (picked != null) onChanged(picked);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(animation), child: child),
                  ),
                  child: Column(
                    key: ValueKey(day),
                    children: [
                      Text(formatRelativeDay(day), style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(formatShortDate(day), style: text.bodySmall?.copyWith(color: HubColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Volgende dag',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => onChanged(day.add(const Duration(days: 1))),
          ),
        ],
      ),
    );
  }
}

class _DaySummary extends StatelessWidget {
  const _DaySummary({required this.reservations});

  final List<AdminReservation> reservations;

  @override
  Widget build(BuildContext context) {
    int count(ReservationStatus s) => reservations.where((r) => r.status == s).length;
    return Row(
      children: [
        _StatTile(label: 'Verwacht', value: count(ReservationStatus.reserved), color: HubColors.blue),
        const SizedBox(width: 8),
        _StatTile(label: 'Aanwezig', value: count(ReservationStatus.present), color: HubColors.green),
        const SizedBox(width: 8),
        _StatTile(label: 'Afwezig', value: count(ReservationStatus.noShow), color: HubColors.danger),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: HubColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: HubColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedCount(
              value,
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: color),
            ),
            Text(label.toUpperCase(), style: text.labelSmall?.copyWith(color: HubColors.textMuted, letterSpacing: 0.6)),
          ],
        ),
      ),
    );
  }
}

class _SwipeableReservation extends StatelessWidget {
  const _SwipeableReservation({required this.reservation, required this.onTap, required this.onStatus});

  final AdminReservation reservation;
  final VoidCallback onTap;
  final ValueChanged<ReservationStatus> onStatus;

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final canMarkPresent = r.status != ReservationStatus.present && r.status != ReservationStatus.cancelled;
    final canMarkNoShow = r.status != ReservationStatus.noShow && r.status != ReservationStatus.cancelled;

    return Dismissible(
      key: ValueKey('${r.id}-${r.status.key}'),
      direction: switch ((canMarkPresent, canMarkNoShow)) {
        (true, true) => DismissDirection.horizontal,
        (true, false) => DismissDirection.startToEnd,
        (false, true) => DismissDirection.endToStart,
        _ => DismissDirection.none,
      },
      // Tick when the swipe passes the point where releasing triggers the action.
      onUpdate: (details) {
        if (details.reached != details.previousReached) HapticFeedback.mediumImpact();
      },
      dismissThresholds: const {DismissDirection.startToEnd: 0.3, DismissDirection.endToStart: 0.3},
      // The row stays; the list reloads with the new status.
      confirmDismiss: (direction) async {
        onStatus(direction == DismissDirection.startToEnd ? ReservationStatus.present : ReservationStatus.noShow);
        return false;
      },
      background: const _SwipeBackground(
        color: HubColors.green,
        icon: Icons.how_to_reg_rounded,
        label: 'Aanwezig',
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: const _SwipeBackground(
        color: HubColors.danger,
        icon: Icons.person_off_rounded,
        label: 'Afwezig',
        alignment: Alignment.centerRight,
      ),
      child: _AdminReservationCard(reservation: r, onTap: onTap),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({required this.color, required this.icon, required this.label, required this.alignment});

  final Color color;
  final IconData icon;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final content = [
      Icon(icon, color: color),
      const SizedBox(width: 8),
      Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    ];
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignment == Alignment.centerLeft ? content : content.reversed.toList(),
      ),
    );
  }
}

class _AdminReservationCard extends StatelessWidget {
  const _AdminReservationCard({required this.reservation, required this.onTap});

  final AdminReservation reservation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final text = Theme.of(context).textTheme;
    final now = wallClockNow();
    final inProgress = r.status != ReservationStatus.cancelled && !now.isBefore(r.start) && now.isBefore(r.end);

    return Pressable(
      onTap: onTap,
      child: Card(
        shape: inProgress
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: HubColors.red.withValues(alpha: 0.5)),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(
                width: 54,
                child: Column(
                  children: [
                    Text(formatTime(r.start), style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(formatTime(r.end), style: text.bodySmall?.copyWith(color: HubColors.textMuted)),
                    if (inProgress) ...[const SizedBox(height: 4), const _LiveBadge()],
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: HubColors.border,
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            r.displayName,
                            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (r.isFirstVisit) ...[
                          const SizedBox(width: 6),
                          const Tooltip(
                            message: 'Nieuwe bezoeker',
                            child: Icon(Icons.fiber_new_rounded, size: 18, color: Color(0xFF34D399)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        r.hardware.shortLabel,
                        if (r.controllers > 0) '${r.controllers} ctrl',
                        if (r.hasSNumber) r.sNumber!,
                      ].join(' · '),
                      style: text.bodySmall?.copyWith(color: HubColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(r.status, staff: true),
            ],
          ),
        ),
      ),
    );
  }
}

sealed class _SheetAction {
  const _SheetAction();
}

class _SetStatus extends _SheetAction {
  const _SetStatus(this.status);
  final ReservationStatus status;
}

class _Edit extends _SheetAction {
  const _Edit();
}

class _Delete extends _SheetAction {
  const _Delete();
}

class _AdminReservationSheet extends StatelessWidget {
  const _AdminReservationSheet({required this.reservation});

  final AdminReservation reservation;

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final text = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              HardwareAvatar(r.hardware, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.displayName, style: text.titleLarge, overflow: TextOverflow.ellipsis),
                    Text(
                      r.email,
                      style: text.bodyMedium?.copyWith(color: HubColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (r.hasSNumber) DetailRow(icon: Icons.badge_outlined, label: 'S-nummer', value: r.sNumber!),
          DetailRow(icon: Icons.calendar_today_rounded, label: 'Datum', value: formatLongDate(r.start)),
          DetailRow(icon: Icons.schedule_rounded, label: 'Tijd', value: formatTimeRange(r.start, r.end)),
          DetailRow(icon: hardwareIcon(r.hardware), label: 'Hardware', value: r.hardware.label),
          DetailRow(icon: Icons.gamepad_outlined, label: 'Controllers', value: '${r.controllers}'),
          DetailRow(
            icon: r.isFirstVisit ? Icons.fiber_new_rounded : Icons.repeat_rounded,
            label: 'Bezoeker',
            value: r.isFirstVisit ? 'Nieuw' : 'Terugkerend',
          ),
          const SizedBox(height: 16),
          Text('STATUS', style: text.labelSmall?.copyWith(color: HubColors.textMuted, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in ReservationStatus.values)
                ChoiceChip(
                  label: Text(statusLabel(s, staff: true)),
                  selected: r.status == s,
                  showCheckmark: false,
                  avatar: Icon(Icons.circle, size: 10, color: r.status == s ? Colors.white : statusColor(s)),
                  onSelected: r.status == s ? null : (_) => Navigator.pop(context, _SetStatus(s)),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, const _Edit()),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Bewerken'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, const _Delete()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: HubColors.danger,
                    side: BorderSide(color: HubColors.danger.withValues(alpha: 0.4)),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Verwijderen'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pulsing "NU" marker for sessions that are running right now.
class _LiveBadge extends StatefulWidget {
  const _LiveBadge();

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(color: HubColors.red, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          'NU',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: HubColors.red, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
