import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/wall_clock.dart';
import '../../widgets/common.dart';

/// Accepts a plain CUID or a URL ending in one, like the website's scanner.
String extractCuid(String scanned) {
  final raw = scanned.trim();
  final uri = Uri.tryParse(raw);
  if (uri != null && uri.hasScheme) {
    final fromQuery = uri.queryParameters['reservation'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery.trim();
    final segments = uri.pathSegments.where((s) => s.isNotEmpty);
    if (segments.isNotEmpty) return segments.last.trim();
  }
  return raw;
}

/// Check-in by the Gaming Hub manager: scanning a member's QR code marks the reservation as present.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final value = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (value == null || _busy) return;
    await _verify(value);
  }

  Future<void> _verify(String scanned) async {
    final cuid = extractCuid(scanned);
    if (cuid.isEmpty || _busy) return;

    final api = AppScope.apiOf(context);
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    await _controller.stop();

    VerifiedReservation? result;
    String? error;
    try {
      result = await api.verify(cuid);
      HapticFeedback.heavyImpact();
    } on ApiException catch (e) {
      error = e.isNotFound ? null : e.message;
      HapticFeedback.vibrate();
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (_) => _ResultSheet(reservation: result, error: error),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _controller.start();
  }

  Future<void> _manualEntry() async {
    final controller = TextEditingController();
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Code invoeren', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Reservatiecode', prefixIcon: Icon(Icons.keyboard_outlined)),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Verifiëren')),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value != null && value.trim().isNotEmpty) await _verify(value);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final size = MediaQuery.sizeOf(context);
    final windowSize = size.width * 0.7;
    final window = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: windowSize,
      height: windowSize,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        title: const Text('QR verificatie'),
        actions: [
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (_, state, _) => state.torchState == TorchState.unavailable
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Zaklamp',
                    icon: Icon(state.torchState == TorchState.on ? Icons.flash_on_rounded : Icons.flash_off_rounded),
                    onPressed: _controller.toggleTorch,
                  ),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            scanWindow: window,
            errorBuilder: (context, error) => Center(
              child: EmptyState(
                icon: Icons.no_photography_outlined,
                title: 'Camera niet beschikbaar',
                message: error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? 'Geef de app toegang tot je camera in de instellingen, of voer de code handmatig in.'
                    : 'Voer de code handmatig in.',
              ),
            ),
          ),
          CustomPaint(size: size, painter: _ScanWindowPainter(window)),
          if (_busy)
            Positioned.fromRect(
              rect: window,
              child: const Center(child: CircularProgressIndicator()),
            ),
          Positioned(
            left: 24,
            right: 24,
            top: window.bottom + 24,
            child: Text(
              'Richt de camera op de QR-code van de reservatie',
              style: text.bodyLarge?.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _manualEntry,
                  icon: const Icon(Icons.keyboard_outlined),
                  label: const Text('Code handmatig invoeren'),
                  style: OutlinedButton.styleFrom(backgroundColor: Colors.black54),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanWindowPainter extends CustomPainter {
  _ScanWindowPainter(this.window);

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final rounded = RRect.fromRectAndRadius(window, const Radius.circular(24));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(rounded)),
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );
    canvas.drawRRect(
      rounded,
      Paint()
        ..color = HubColors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_ScanWindowPainter oldDelegate) => oldDelegate.window != window;
}

class _ResultSheet extends StatelessWidget {
  const _ResultSheet({required this.reservation, required this.error});

  final VerifiedReservation? reservation;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = reservation;
    final ok = r != null;
    final color = ok ? HubColors.green : HubColors.danger;
    final isToday = ok && isSameDay(r.start, wallClockNow());

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Icon(ok ? Icons.how_to_reg_rounded : Icons.close_rounded, color: color, size: 36),
            ),
          ),
          const SizedBox(height: 16),
          Text(ok ? 'Ingecheckt' : 'Reservatie niet gevonden', style: text.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            ok ? r.email : (error ?? 'Deze code is ongeldig, geannuleerd of al als afwezig gemarkeerd.'),
            style: text.bodyMedium?.copyWith(color: HubColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          if (ok) ...[
            const SizedBox(height: 16),
            if (!isToday)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: HubColors.yellow.withValues(alpha: 0.08),
                  border: Border.all(color: HubColors.yellow.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Let op: deze reservatie is niet voor vandaag.',
                  style: text.bodyMedium?.copyWith(color: HubColors.yellow),
                ),
              ),
            if (r.sNumber.isNotEmpty && r.sNumber != 'N/A')
              DetailRow(icon: Icons.badge_outlined, label: 'S-nummer', value: r.sNumber),
            DetailRow(icon: hardwareIcon(r.hardware), label: 'Hardware', value: r.hardware.label),
            DetailRow(
              icon: Icons.schedule_rounded,
              label: isToday ? 'Tijd' : formatShortDate(r.start),
              value: formatTimeRange(r.start, r.end),
            ),
            if (r.controllers > 0)
              DetailRow(icon: Icons.gamepad_outlined, label: 'Controllers', value: '${r.controllers}'),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Volgende scannen')),
        ],
      ),
    );
  }
}
