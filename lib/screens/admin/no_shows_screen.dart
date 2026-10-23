import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/wall_clock.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';

/// Members with no-shows this semester; three blocks them from reserving.
class NoShowsScreen extends StatefulWidget {
  const NoShowsScreen({super.key});

  @override
  State<NoShowsScreen> createState() => _NoShowsScreenState();
}

class _NoShowsScreenState extends State<NoShowsScreen> {
  static const _limit = 3;

  List<List<AdminReservation>>? _groups;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final noShows = await AppScope.apiOf(context).noShows();
      final byUser = <int, List<AdminReservation>>{};
      for (final r in noShows) {
        byUser.putIfAbsent(r.userId, () => []).add(r);
      }
      if (!mounted) return;
      setState(() {
        _groups = byUser.values.toList()..sort((a, b) => b.length.compareTo(a.length));
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _unblock(AdminReservation user) async {
    final ok = await confirm(
      context,
      title: '${user.displayName} deblokkeren?',
      message: 'Alle no-shows van deze persoon worden gewist en ze kunnen opnieuw reserveren.',
      confirmLabel: 'Deblokkeren',
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.apiOf(context).unblockUser(user.userId);
      if (mounted) showMessage(context, '${user.displayName} is gedeblokkeerd.');
      _load();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _resetAll() async {
    final ok = await confirm(
      context,
      title: 'Alle no-shows resetten?',
      message: 'Dit is bedoeld voor een semesterwissel. Iedereen kan daarna opnieuw reserveren.',
      confirmLabel: 'Alles resetten',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.apiOf(context).resetAllNoShows();
      if (mounted) showMessage(context, 'Alle no-shows zijn gereset.');
      _load();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;

    return Scaffold(
      body: GlowBackground(
        intensity: 0.1,
        child: RefreshIndicator.adaptive(
          onRefresh: _load,
          color: HubColors.red,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              HubSliverAppBar(
                title: 'No-shows',
                actions: [
                  PopupMenuButton<void>(
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        onTap: _resetAll,
                        child: const ListTile(
                          leading: Icon(Icons.restart_alt_rounded, color: HubColors.danger),
                          title: Text('Alles resetten (semester)', style: TextStyle(color: HubColors.danger)),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (groups == null && _error == null)
                SkeletonList()
              else if (groups == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorState(message: _error!, onRetry: _load),
                )
              else if (groups.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.sentiment_satisfied_alt_rounded,
                    title: 'Geen no-shows',
                    message: 'Iedereen is netjes komen opdagen.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList.separated(
                    itemCount: groups.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => FadeSlideIn(
                      index: i,
                      child: _NoShowCard(reservations: groups[i], limit: _limit, onUnblock: _unblock),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoShowCard extends StatelessWidget {
  const _NoShowCard({required this.reservations, required this.limit, required this.onUnblock});

  final List<AdminReservation> reservations;
  final int limit;
  final ValueChanged<AdminReservation> onUnblock;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final user = reservations.first;
    final blocked = reservations.length >= limit;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: blocked ? HubColors.danger.withValues(alpha: 0.4) : HubColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.displayName, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        user.hasSNumber ? '${user.sNumber} · ${user.email}' : user.email,
                        style: text.bodySmall?.copyWith(color: HubColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (blocked)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: HubColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      'Geblokkeerd',
                      style: text.labelSmall?.copyWith(color: HubColors.danger, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            NoShowTracker(count: reservations.length, limit: limit),
            const SizedBox(height: 12),
            for (final r in reservations)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(hardwareIcon(r.hardware), size: 16, color: HubColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${formatShortDate(r.start)} · ${formatTimeRange(r.start, r.end)}',
                        style: text.bodySmall?.copyWith(color: HubColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => onUnblock(user),
                icon: const Icon(Icons.lock_open_rounded, size: 18),
                label: const Text('Deblokkeren'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
