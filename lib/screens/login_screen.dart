import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.authOf(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: Stack(
        children: [
          // Same soft red glow the website puts behind its hero.
          Positioned(
            top: -120,
            left: -80,
            right: -80,
            child: Container(
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [HubColors.red.withValues(alpha: 0.22), Colors.transparent]),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  FadeSlideIn(
                    offset: 24,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: HubColors.red,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: HubColors.red.withValues(alpha: 0.45), blurRadius: 32)],
                      ),
                      child: const Icon(Icons.sports_esports_rounded, color: Colors.white, size: 44),
                    ),
                  ),
                  const SizedBox(height: 28),
                  FadeSlideIn(
                    index: 1,
                    child: BrandTitle(
                      prefix: 'AP ',
                      style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeSlideIn(
                    index: 2,
                    child: Text(
                      'Reserveer een high-end PC of console en beheer je reservaties.',
                      style: text.bodyLarge?.copyWith(color: HubColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const Spacer(flex: 4),
                  if (auth.error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: HubColors.yellow.withValues(alpha: 0.08),
                        border: Border.all(color: HubColors.yellow.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: HubColors.yellow, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(auth.error!, style: text.bodyMedium?.copyWith(color: HubColors.yellow)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FadeSlideIn(
                    index: 4,
                    child: FilledButton(
                      onPressed: auth.signingIn ? null : auth.signIn,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: Colors.white70,
                      ),
                      child: auth.signingIn
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _MicrosoftLogo(),
                                SizedBox(width: 10),
                                Flexible(child: Text('Inloggen met Microsoft', overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Gebruik je AP Microsoft-account.',
                    style: text.bodySmall?.copyWith(color: HubColors.textMuted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: auth.signingIn ? null : auth.startDemo,
                    child: const Text('Demo bekijken zonder account'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MicrosoftLogo extends StatelessWidget {
  const _MicrosoftLogo();

  @override
  Widget build(BuildContext context) {
    Widget square(int color) => Container(width: 8.5, height: 8.5, color: Color(color));
    return SizedBox(
      width: 18,
      height: 18,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [square(0xFFF25022), square(0xFF7FBA00)]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [square(0xFF00A4EF), square(0xFFFFB900)]),
        ],
      ),
    );
  }
}
