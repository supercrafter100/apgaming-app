import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_scope.dart';
import '../notifications/push_notifications.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await AppScope.readAuth(context).refreshProfile();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _signOut() async {
    final auth = AppScope.readAuth(context);
    if (auth.isDemo) return auth.signOut();

    final ok = await confirm(
      context,
      title: 'Uitloggen?',
      message: 'Je moet daarna opnieuw inloggen met Microsoft.',
      confirmLabel: 'Uitloggen',
      destructive: true,
    );
    if (ok && mounted) auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.authOf(context);
    final profile = auth.profile!;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: GlowBackground(
        child: RefreshIndicator.adaptive(
          onRefresh: _load,
          color: HubColors.red,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              const HubSliverAppBar(title: 'Account'),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 32 + MediaQuery.paddingOf(context).bottom),
                sliver: SliverList.list(
                  children: staggered([
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: HubColors.red,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [BoxShadow(color: HubColors.red.withValues(alpha: 0.4), blurRadius: 24)],
                              ),
                              child: Text(
                                profile.displayName.characters.first.toUpperCase(),
                                style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(profile.displayName, style: text.titleLarge, overflow: TextOverflow.ellipsis),
                                  Text(
                                    profile.email,
                                    style: text.bodyMedium?.copyWith(color: HubColors.textSecondary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (profile.hasSNumber)
                                    Text(profile.sNumber, style: text.bodySmall?.copyWith(color: HubColors.textMuted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (profile.roles.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final role in profile.roles)
                            Chip(
                              avatar: const Icon(Icons.verified_user_outlined, size: 16, color: HubColors.red),
                              label: Text(role),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                    const _SectionTitle('Meldingen'),
                    const Card(clipBehavior: Clip.antiAlias, child: _ReminderSetting()),
                    const _SectionTitle('Hulp'),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.help_outline_rounded),
                            title: const Text('Annuleren en no-shows'),
                            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                            onTap: () => openWebPage('/reservations/how-to-cancel'),
                          ),
                          const Divider(indent: 16, endIndent: 16),
                          ListTile(
                            leading: const Icon(Icons.gavel_rounded),
                            title: const Text('Huisregels & info'),
                            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                            onTap: () => openWebPage('/info'),
                          ),
                          const Divider(indent: 16, endIndent: 16),
                          ListTile(
                            leading: const Icon(Icons.privacy_tip_outlined),
                            title: const Text('Privacy'),
                            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                            onTap: () => openWebPage('/privacy'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout_rounded),
                      label: Text(auth.isDemo ? 'Demo afsluiten' : 'Uitloggen'),
                      style: OutlinedButton.styleFrom(foregroundColor: HubColors.danger),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReminderSetting extends StatelessWidget {
  const _ReminderSetting();

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.authOf(context);
    final push = auth.push;
    return ListenableBuilder(
      listenable: push,
      builder: (context, _) {
        const title = Text('Herinnering voor je sessie');
        const icon = Icon(Icons.notifications_active_outlined);
        final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: HubColors.textSecondary);

        if (push.status != PushStatus.enabled) {
          return ListTile(
            leading: icon,
            title: title,
            enabled: false,
            subtitle: Text(switch (push.status) {
              _ when auth.isDemo => 'Niet beschikbaar in de demo.',
              PushStatus.denied =>'Meldingen staan uit voor deze app. Zet ze aan in de instellingen van je telefoon.',
              _ when !push.isConfigured => 'Nog niet beschikbaar in deze versie van de app.',
              _ => 'Meldingen worden ingesteld…',
            }, style: subtitleStyle),
          );
        }

        return SwitchListTile.adaptive(
          secondary: icon,
          title: title,
          subtitle: Text(
            '15 minuten voor je reservatie begint, ook als je via de website reserveerde.',
            style: subtitleStyle,
          ),
          value: push.reservationReminders,
          onChanged: (enabled) async {
            try {
              await push.setReservationReminders(enabled);
            } on ApiException catch (e) {
              if (context.mounted) showMessage(context, e.message, error: true);
            }
          },
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: HubColors.textMuted, letterSpacing: 1.2),
      ),
    );
  }
}
