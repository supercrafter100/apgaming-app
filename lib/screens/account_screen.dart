import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../util/futures.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  LinkedProviders? _links;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = AppScope.readAuth(context);
    try {
      final (links, _) = await both(auth.api.linkedProviders(), auth.refreshProfile());
      if (mounted) setState(() => _links = links);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _unlink(String provider, String label) async {
    final ok = await confirm(
      context,
      title: '$label ontkoppelen?',
      message: 'Je kan daarna niet meer inloggen met je $label-account.',
      confirmLabel: 'Ontkoppelen',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.apiOf(context).unlinkProvider(provider);
      if (mounted) showMessage(context, '$label is ontkoppeld.');
      _load();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _signOut() async {
    final ok = await confirm(
      context,
      title: 'Uitloggen?',
      message: 'Je moet daarna opnieuw inloggen via de website.',
      confirmLabel: 'Uitloggen',
      destructive: true,
    );
    if (ok && mounted) AppScope.readAuth(context).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final profile = AppScope.authOf(context).profile!;
    final text = Theme.of(context).textTheme;
    final links = _links;

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
                    const _SectionTitle('Inloggen met'),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: links == null
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(child: CircularProgressIndicator.adaptive()),
                            )
                          : Column(
                              children: [
                                _ProviderTile(
                                  label: 'Microsoft',
                                  linked: links.microsoft > 0,
                                  canUnlink: links.total > 1,
                                  onUnlink: () => _unlink('microsoft', 'Microsoft'),
                                ),
                                const Divider(indent: 16, endIndent: 16),
                                _ProviderTile(
                                  label: 'Google',
                                  linked: links.google > 0,
                                  canUnlink: links.total > 1,
                                  onUnlink: () => _unlink('google', 'Google'),
                                ),
                              ],
                            ),
                    ),
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
                      label: const Text('Uitloggen'),
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

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({required this.label, required this.linked, required this.canUnlink, required this.onUnlink});

  final String label;
  final bool linked;
  final bool canUnlink;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        linked ? Icons.link_rounded : Icons.link_off_rounded,
        color: linked ? HubColors.green : HubColors.textMuted,
      ),
      title: Text(label),
      subtitle: Text(linked ? 'Gekoppeld' : 'Niet gekoppeld', style: const TextStyle(color: HubColors.textSecondary)),
      trailing: linked && canUnlink ? TextButton(onPressed: onUnlink, child: const Text('Ontkoppel')) : null,
    );
  }
}
