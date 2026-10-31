import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../util/wall_clock.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import 'new_reservation_screen.dart';

class MyReservationsScreen extends StatefulWidget {
  const MyReservationsScreen({super.key});

  @override
  State<MyReservationsScreen> createState() => _MyReservationsScreenState();
}

class _MyReservationsScreenState extends State<MyReservationsScreen> with WidgetsBindingObserver {
  MyReservations? _data;
  String? _error;
  bool _showHistory = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final data = await AppScope.apiOf(context).myReservations();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _newReservation() async {
    final created = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const NewReservationScreen()));
    if (created == true) _load();
  }

  Future<void> _openDetails(MyReservation reservation) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReservationSheet(reservation: reservation),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final canReserve = AppScope.authOf(context).canReserve;
    final data = _data;
    final visible = data == null ? const <MyReservation>[] : (_showHistory ? data.history : data.upcoming);

    return Scaffold(
      floatingActionButton: data == null || data.isBlocked || !canReserve
          ? null
          : aboveTabBar(
              context,
              FloatingActionButton.extended(
                heroTag: null, // tabs live side by side in an IndexedStack
                onPressed: _newReservation,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nieuwe reservatie'),
              ),
            ),
      body: GlowBackground(
        child: RefreshIndicator.adaptive(
          onRefresh: _load,
          color: HubColors.red,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              const HubSliverAppBar(title: 'Reservaties'),
              if (data == null && _error == null)
                SkeletonList()
              else if (data == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorState(message: _error!, onRetry: _load),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  sliver: SliverList.list(
                    children: [
                      if (data.upcoming.isNotEmpty) ...[
                        FadeSlideIn(
                          child: _NextUpCard(
                            reservation: data.upcoming.first,
                            onTap: () => _openDetails(data.upcoming.first),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      FadeSlideIn(index: 1, child: _NoShowCard(data: data)),
                      const SizedBox(height: 24),
                      HubSegmentedControl<bool>(
                        segments: [
                          (false, 'Komende (${data.upcoming.length})'),
                          (true, 'Geschiedenis (${data.history.length})'),
                        ],
                        selected: _showHistory,
                        onChanged: (v) => setState(() => _showHistory = v),
                      ),
                    ],
                  ),
                ),
                if (visible.isEmpty)
                  SliverToBoxAdapter(
                    child: EmptyState(
                      icon: Icons.sports_esports_outlined,
                      title: _showHistory ? 'Nog geen eerdere reservaties' : 'Geen komende reservaties',
                      message: !canReserve
                          ? 'Reserveren kan alleen met je AP Microsoft-account.'
                          : _showHistory || data.isBlocked
                          ? null
                          : 'Boek een PC of console met de knop hieronder.',
                    ),
                  )
                else
                  SliverPadding(
                    // Clear the FAB and the translucent tab bar.
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 96 + MediaQuery.paddingOf(context).bottom),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => FadeSlideIn(
                        // Re-animate when switching between upcoming and history.
                        key: ValueKey('$_showHistory-${visible[i].cuid}'),
                        index: i,
                        child: _ReservationCard(reservation: visible[i], onTap: () => _openDetails(visible[i])),
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

class _NoShowCard extends StatelessWidget {
  const _NoShowCard({required this.data});

  final MyReservations data;

  @override
  Widget build(BuildContext context) {
    final count = data.noShowCount;
    final remaining = (data.noShowLimit - count).clamp(0, data.noShowLimit);
    final text = Theme.of(context).textTheme;

    final (IconData icon, Color color, String title, String body) = data.isBlocked
        ? (
            Icons.block_rounded,
            HubColors.danger,
            'Je kan momenteel niet reserveren',
            'Je hebt $count no-shows dit semester. Spreek een medewerker aan in de Gaming Hub of contacteer ons via Discord. '
                'Bij een nieuw semester worden je no-shows gereset.',
          )
        : count == 0
        ? (
            Icons.sentiment_satisfied_alt_rounded,
            HubColors.green,
            'Geen no-shows, top!',
            'Kan je toch niet komen? Annuleer dan op tijd, dan telt het niet mee.',
          )
        : (
            Icons.warning_amber_rounded,
            count == 1 ? HubColors.yellow : HubColors.orange,
            'Nog $remaining no-show${remaining == 1 ? '' : 's'} tot je niet meer kan reserveren',
            'Annuleer altijd op voorhand als je niet kan komen. Annuleren telt niet als no-show.',
          );

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: count == 0 && !data.isBlocked ? HubColors.border : color.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: text.bodyMedium?.copyWith(color: HubColors.textSecondary, height: 1.4)),
            const SizedBox(height: 14),
            Row(
              children: [
                NoShowTracker(count: count, limit: data.noShowLimit),
                const SizedBox(width: 12),
                Text(
                  'No-shows dit semester',
                  style: text.labelSmall?.copyWith(color: HubColors.textMuted, letterSpacing: 0.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({required this.reservation, required this.onTap});

  final MyReservation reservation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = reservation;

    return Pressable(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              HardwareAvatar(r.hardware),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(r.hardware.label, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        StatusPill(r.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(formatRelativeDay(r.start), style: text.bodyMedium?.copyWith(color: Colors.white70)),
                    Text(
                      '${formatTimeRange(r.start, r.end)}'
                      '${r.controllers > 0 ? ' · ${r.controllers} controller${r.controllers == 1 ? '' : 's'}' : ''}',
                      style: text.bodyMedium?.copyWith(color: HubColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(r.isActive ? Icons.qr_code_2_rounded : Icons.chevron_right_rounded, color: HubColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReservationSheet extends StatefulWidget {
  const _ReservationSheet({required this.reservation});

  final MyReservation reservation;

  @override
  State<_ReservationSheet> createState() => _ReservationSheetState();
}

class _ReservationSheetState extends State<_ReservationSheet> {
  bool _cancelling = false;

  Future<void> _cancel() async {
    final ok = await confirm(
      context,
      title: 'Reservatie annuleren?',
      message: 'Je plek gaat dan naar iemand anders. Op tijd annuleren telt niet als no-show.',
      confirmLabel: 'Ja, annuleer',
      cancelLabel: 'Behouden',
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await AppScope.apiOf(context).cancelMyReservation(widget.reservation.cuid);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showMessage(context, 'Je reservatie is geannuleerd.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reservation;
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
                    Text(r.hardware.label, style: text.titleLarge),
                    const SizedBox(height: 4),
                    StatusPill(r.status),
                  ],
                ),
              ),
            ],
          ),
          if (r.isActive) ...[
            const SizedBox(height: 24),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: QrImageView(data: r.cuid, size: 200, padding: EdgeInsets.zero),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Laat deze code scannen door de Gaming Hub manager wanneer je aankomt.',
              style: text.bodyMedium?.copyWith(color: HubColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          DetailRow(icon: Icons.calendar_today_rounded, label: 'Datum', value: formatLongDate(r.start)),
          DetailRow(icon: Icons.schedule_rounded, label: 'Tijd', value: formatTimeRange(r.start, r.end)),
          if (r.controllers > 0 || r.hardware.isConsole)
            DetailRow(icon: Icons.gamepad_outlined, label: 'Controllers', value: '${r.controllers}'),
          if (r.canCancel) ...[
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _cancelling ? null : _cancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: HubColors.danger,
                side: BorderSide(color: HubColors.danger.withValues(alpha: 0.4)),
              ),
              icon: _cancelling
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.close_rounded),
              label: const Text('Reservatie annuleren'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Prominent card for the next session, with a live countdown.
class _NextUpCard extends StatefulWidget {
  const _NextUpCard({required this.reservation, required this.onTap});

  final MyReservation reservation;
  final VoidCallback onTap;

  @override
  State<_NextUpCard> createState() => _NextUpCardState();
}

class _NextUpCardState extends State<_NextUpCard> {
  // Re-evaluated every 30 seconds so the countdown stays current.
  late final Timer _ticker = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _ticker;
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  String _countdown(DateTime now) {
    final r = widget.reservation;
    if (!now.isBefore(r.start)) return 'Nu bezig · tot ${formatTime(r.end)}';
    final left = r.start.difference(now);
    if (left.inMinutes < 60) return 'Begint over ${left.inMinutes + 1} min';
    if (left.inHours < 24 && isSameDay(now, r.start)) {
      final minutes = left.inMinutes % 60;
      return 'Begint over ${left.inHours} u${minutes > 0 ? ' $minutes min' : ''}';
    }
    return formatRelativeDay(r.start);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reservation;
    final text = Theme.of(context).textTheme;

    return Pressable(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: HubColors.red.withValues(alpha: 0.45)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [HubColors.red.withValues(alpha: 0.28), HubColors.surface],
          ),
          boxShadow: [
            BoxShadow(color: HubColors.red.withValues(alpha: 0.18), blurRadius: 30, offset: const Offset(0, 10)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'VOLGENDE SESSIE',
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(
                      color: Colors.white70,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                StatusPill(r.status),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatTime(r.start),
                  style: text.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 6),
                  child: Text('– ${formatTime(r.end)}', style: text.titleMedium?.copyWith(color: Colors.white60)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_countdown(wallClockNow())} · ${r.hardware.label}',
              style: text.bodyMedium?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.qr_code_2_rounded, size: 20, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Toon je QR-code aan de Gaming Hub manager',
                    style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white70),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
