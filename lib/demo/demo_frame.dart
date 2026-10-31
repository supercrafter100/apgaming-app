import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';

/// Shows a permanent strip above every screen during the demo, so sample data is
/// never mistaken for real reservations.
class DemoFrame extends StatelessWidget {
  const DemoFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!AppScope.authOf(context).isDemo) return child;

    return Column(
      children: [
        Material(
          color: Color.alphaBlend(HubColors.yellow.withValues(alpha: 0.16), Colors.black),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_outline_rounded, color: HubColors.yellow, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Demo: voorbeeldgegevens, niets wordt echt gereserveerd',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: HubColors.yellow),
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // The strip already clears the status bar.
        Expanded(
          child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
        ),
      ],
    );
  }
}
