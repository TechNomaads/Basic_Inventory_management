import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/constants/app_colors.dart';
import '../domain/barcode_debouncer.dart';
import '../domain/scan_audio_feedback.dart';
import '../domain/scan_handler.dart';
import '../domain/scan_mode.dart';

/// Unified camera scanner widget shared between Billing and Inventory modes.
///
/// Composes:
///   - MobileScanner camera viewfinder
///   - Adaptive overlay with corner guides
///   - Top bar: back button, mode badge, torch toggle
///   - Bottom bar: manual entry button + mode-specific controls slot
///   - Debounce + dedup via [BarcodeDebouncer]
///   - Audio + haptic feedback per scan result
class UnifiedScannerWidget extends ConsumerStatefulWidget {
  /// The active scanner mode — drives the overlay style and badge label.
  final ScanMode mode;

  /// Strategy handler that processes each accepted barcode.
  final ScanHandler handler;

  /// Optional widget rendered at the bottom of the scanner
  /// (e.g. cart bar in billing mode, STOCK IN/OUT toggle in inventory mode).
  final Widget? bottomControls;

  /// Callback when the back button is pressed.
  final VoidCallback? onBack;

  const UnifiedScannerWidget({
    super.key,
    required this.mode,
    required this.handler,
    this.bottomControls,
    this.onBack,
  });

  @override
  ConsumerState<UnifiedScannerWidget> createState() =>
      _UnifiedScannerWidgetState();
}

class _UnifiedScannerWidgetState extends ConsumerState<UnifiedScannerWidget> {
  final MobileScannerController _cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  final BarcodeDebouncer _debouncer = BarcodeDebouncer();
  final TextEditingController _manualController = TextEditingController();

  bool _torchEnabled = false;
  bool _processing = false;

  @override
  void dispose() {
    _cameraController.dispose();
    _manualController.dispose();
    widget.handler.dispose();
    super.dispose();
  }

  // ── Barcode detection callback ──────────────────────────────────

  void _onBarcodeDetected(BarcodeCapture capture) async {
    if (_processing) return;
    final rawValue = capture.barcodes.firstOrNull?.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;
    if (!_debouncer.shouldAccept(rawValue)) return;

    setState(() => _processing = true);
    HapticFeedback.mediumImpact();

    try {
      final result = await widget.handler.handleBarcode(rawValue);
      if (!mounted) return;

      // Audio feedback
      if (result.success) {
        if (widget.mode == ScanMode.billing) {
          ScanAudioFeedback.playBillingBeep();
        } else {
          ScanAudioFeedback.playInventoryChime();
        }
      } else {
        ScanAudioFeedback.playErrorBuzz();
      }

      // Snackbar message
      if (result.message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message!),
            backgroundColor:
                result.success ? AppColors.success : AppColors.error,
            duration: Duration(milliseconds: result.success ? 800 : 2000),
          ),
        );
      }

      // Modal prompt (stock edit, quick-add, etc.)
      if (result.promptWidget != null && mounted) {
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          isDismissible: true,
          builder: (_) => result.promptWidget!,
        );
      }
    } catch (e) {
      if (mounted) {
        ScanAudioFeedback.playErrorBuzz();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  // ── Manual barcode entry ────────────────────────────────────────

  void _showManualEntryDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter Barcode Manually',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _manualController,
              autofocus: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Type barcode or SKU...',
                hintStyle: const TextStyle(color: AppColors.textHint),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send, color: AppColors.primary),
                  onPressed: () => _submitManualBarcode(ctx),
                ),
              ),
              onSubmitted: (_) => _submitManualBarcode(ctx),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _submitManualBarcode(BuildContext sheetContext) {
    final barcode = _manualController.text.trim();
    if (barcode.isEmpty) return;
    Navigator.pop(sheetContext);
    _manualController.clear();
    // Simulate a barcode detection
    _onBarcodeDetected(BarcodeCapture(
      barcodes: [Barcode(rawValue: barcode)],
    ));
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Camera viewfinder ──────────────────────────────────
        Positioned.fill(
          child: MobileScanner(
            controller: _cameraController,
            onDetect: _onBarcodeDetected,
          ),
        ),

        // ── Scan overlay with corner guides ────────────────────
        CustomPaint(
          painter: _ScanOverlayPainter(mode: widget.mode),
          child: const SizedBox.expand(),
        ),

        // ── Top bar ────────────────────────────────────────────
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Back button
                if (widget.onBack != null)
                  _GlassCircleButton(
                    icon: Icons.arrow_back,
                    onTap: widget.onBack!,
                  ),
                const SizedBox(width: 12),
                // Mode badge
                _ModeBadge(mode: widget.mode),
                const Spacer(),
                // Torch toggle
                _GlassCircleButton(
                  icon: _torchEnabled ? Icons.flash_on : Icons.flash_off,
                  onTap: () {
                    _cameraController.toggleTorch();
                    setState(() => _torchEnabled = !_torchEnabled);
                  },
                ),
              ],
            ),
          ),
        ),

        // ── Processing indicator ───────────────────────────────
        if (_processing)
          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black87.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accent.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Processing scan...',
                    style: GoogleFonts.inter(
                      color: AppColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Bottom controls ────────────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Mode-specific controls slot
                  if (widget.bottomControls != null) widget.bottomControls!,
                  if (widget.bottomControls != null) const SizedBox(height: 12),
                  // Manual entry button
                  TextButton.icon(
                    onPressed: _showManualEntryDialog,
                    icon: const Icon(
                      Icons.keyboard_outlined,
                      color: AppColors.textSecondary,
                      size: 18,
                    ),
                    label: Text(
                      'Enter barcode manually',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Helper Widgets ─────────────────────────────────────────────────

/// Glassmorphism circle button for the scanner overlay.
class _GlassCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

/// Mode indicator badge shown at the top of the scanner.
class _ModeBadge extends StatelessWidget {
  final ScanMode mode;

  const _ModeBadge({required this.mode});

  @override
  Widget build(BuildContext context) {
    final bool isBilling = mode == ScanMode.billing;
    final color = isBilling ? AppColors.accent : AppColors.primary;
    final label = isBilling ? '🛒 BILLING' : '📦 INVENTORY';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Scan Overlay Painter ───────────────────────────────────────────

/// Custom painter for the scan overlay with corner guides.
///
/// Adapts shape based on [ScanMode]:
///   - Billing: wider rectangular target (optimized for 1D barcodes)
///   - Inventory: squarish target (works for both 1D and 2D codes)
class _ScanOverlayPainter extends CustomPainter {
  final ScanMode mode;

  _ScanOverlayPainter({required this.mode});

  @override
  void paint(Canvas canvas, Size size) {
    // Billing: wider rectangle for 1D barcodes; Inventory: squarish
    final double scanWidth;
    final double scanHeight;
    if (mode == ScanMode.billing) {
      scanWidth = size.width * 0.75;
      scanHeight = size.height * 0.25;
    } else {
      scanWidth = size.width * 0.70;
      scanHeight = size.width * 0.70; // square
    }

    final left = (size.width - scanWidth) / 2;
    final top = (size.height - scanHeight) / 2.3;
    final right = left + scanWidth;
    final bottom = top + scanHeight;

    // Dim overlay outside target area
    final bgPaint = Paint()..color = AppColors.scanOverlay;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, top), bgPaint);
    canvas.drawRect(
      Rect.fromLTWH(0, bottom, size.width, size.height - bottom),
      bgPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, top, left, scanHeight),
      bgPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(right, top, size.width - right, scanHeight),
      bgPaint,
    );

    // Corner guides
    const cornerLength = 28.0;
    const strokeWidth = 3.5;
    final cornerPaint = Paint()
      ..color = AppColors.scanCorner
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawLine(
        Offset(left, top), Offset(left + cornerLength, top), cornerPaint);
    canvas.drawLine(
        Offset(left, top), Offset(left, top + cornerLength), cornerPaint);

    // Top-right
    canvas.drawLine(
        Offset(right, top), Offset(right - cornerLength, top), cornerPaint);
    canvas.drawLine(
        Offset(right, top), Offset(right, top + cornerLength), cornerPaint);

    // Bottom-left
    canvas.drawLine(Offset(left, bottom), Offset(left + cornerLength, bottom),
        cornerPaint);
    canvas.drawLine(Offset(left, bottom), Offset(left, bottom - cornerLength),
        cornerPaint);

    // Bottom-right
    canvas.drawLine(Offset(right, bottom),
        Offset(right - cornerLength, bottom), cornerPaint);
    canvas.drawLine(Offset(right, bottom),
        Offset(right, bottom - cornerLength), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter oldDelegate) =>
      oldDelegate.mode != mode;
}
