import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/models.dart';
import '../config.dart';
import '../theme.dart';
import 'motion.dart';

IconData hardwareIcon(Hardware hardware) => switch (hardware) {
  Hardware.pc => Icons.desktop_windows_outlined,
  Hardware.ps5 => Icons.sports_esports_outlined,
  Hardware.nintendoSwitch => Icons.videogame_asset_outlined,
};

/// Member-facing and staff-facing labels differ on the website; keep both.
String statusLabel(ReservationStatus status, {bool staff = false}) => switch (status) {
  ReservationStatus.reserved => staff ? 'Geboekt' : 'Gereserveerd',
  ReservationStatus.present => 'Aanwezig',
  ReservationStatus.cancelled => 'Geannuleerd',
  ReservationStatus.noShow => staff ? 'Afwezig' : 'No-show',
};

Color statusColor(ReservationStatus status) => switch (status) {
  ReservationStatus.reserved => HubColors.blue,
  ReservationStatus.present => HubColors.green,
  ReservationStatus.cancelled => HubColors.textSecondary,
  ReservationStatus.noShow => HubColors.danger,
};

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key, this.staff = false});

  final ReservationStatus status;
  final bool staff;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        statusLabel(status, staff: staff),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class HardwareAvatar extends StatelessWidget {
  const HardwareAvatar(this.hardware, {super.key, this.size = 48});

  final Hardware hardware;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(size / 4),
        border: Border.all(color: HubColors.border),
      ),
      child: Icon(hardwareIcon(hardware), color: HubColors.red, size: size / 2),
    );
  }
}

/// "AP Gaming Hub" with the red accent the website uses in its headings.
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key, this.prefix = '', this.accent = 'Gaming Hub', this.style});

  final String prefix;
  final String accent;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.headlineMedium;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: accent,
            style: const TextStyle(color: HubColors.red),
          ),
        ],
      ),
      style: base,
      textAlign: TextAlign.center,
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: HubColors.textMuted),
          const SizedBox(height: 12),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              style: text.bodyMedium?.copyWith(color: HubColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.wifi_off_rounded,
      title: 'Er ging iets mis',
      message: message,
      action: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Opnieuw proberen'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
      ),
    );
  }
}

class NoShowTracker extends StatelessWidget {
  const NoShowTracker({super.key, required this.count, required this.limit, this.size = 14});

  final int count;
  final int limit;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < limit; i++)
          Container(
            width: size,
            height: size,
            margin: EdgeInsets.only(right: i == limit - 1 ? 0 : size / 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < count ? HubColors.red : Colors.transparent,
              border: Border.all(color: i < count ? HubColors.red : HubColors.textMuted, width: 1.5),
            ),
          ),
      ],
    );
  }
}

/// Native-looking confirm dialog (Cupertino on iOS, Material on Android).
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Annuleren',
  bool destructive = false,
}) async {
  final isIos = Theme.of(context).platform == TargetPlatform.iOS;
  final result = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text(title),
      content: Text(message),
      actions: [
        _adaptiveAction(context, isIos, label: cancelLabel, onPressed: () => Navigator.pop(context, false)),
        _adaptiveAction(
          context,
          isIos,
          label: confirmLabel,
          destructive: destructive,
          isDefault: !destructive,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  return result ?? false;
}

Widget _adaptiveAction(
  BuildContext context,
  bool isIos, {
  required String label,
  required VoidCallback onPressed,
  bool destructive = false,
  bool isDefault = false,
}) {
  if (isIos) {
    return CupertinoDialogAction(
      onPressed: onPressed,
      isDestructiveAction: destructive,
      isDefaultAction: isDefault,
      child: Text(label),
    );
  }
  return TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(foregroundColor: destructive ? HubColors.danger : Colors.white),
    child: Text(label),
  );
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  if (error) HapticFeedback.heavyImpact();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: error ? HubColors.danger : HubColors.green,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

Future<void> openWebPage(String path) => launchUrl(Uri.parse('$webUrl$path'), mode: LaunchMode.inAppBrowserView);

/// Label + value pair used in detail sheets.
class DetailRow extends StatelessWidget {
  const DetailRow({super.key, required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: HubColors.textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label, style: text.bodyMedium?.copyWith(color: HubColors.textSecondary)),
          ),
          Flexible(
            child: Text(
              value,
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact pinned header for the main screens, bold like the website's headings.
class HubSliverAppBar extends StatelessWidget {
  const HubSliverAppBar({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      centerTitle: false,
      toolbarHeight: 64,
      backgroundColor: Colors.transparent,
      // Content blurs underneath once scrolled, like native large-title bars.
      flexibleSpace: const Frosted(color: Color(0x99020618), child: SizedBox.expand()),
      title: Text(
        title,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      ),
      actions: actions,
    );
  }
}

/// Lifts a floating action button above the translucent tab bar, which the body extends behind.
/// [context] must be the screen's own context: a nested Scaffold hides the inset from its FAB slot,
/// and already keeps the FAB clear of the device's safe area itself.
Widget aboveTabBar(BuildContext context, Widget fab) {
  final inset = MediaQuery.paddingOf(context).bottom - MediaQuery.viewPaddingOf(context).bottom;
  return Padding(
    padding: EdgeInsets.only(bottom: inset.clamp(0, double.infinity)),
    child: fab,
  );
}
