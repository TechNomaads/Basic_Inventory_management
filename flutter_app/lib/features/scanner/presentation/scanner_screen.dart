/// [ScannerScreen] — Full-screen barcode scanner with camera viewfinder.
///
/// Responsibilities:
///   - Camera viewfinder via mobile_scanner
///   - Corner-guide overlay for aiming
///   - Scan mode toggle: STOCK IN / STOCK OUT
///   - Manual barcode entry fallback
///   - Torch toggle and vibration feedback
///
/// Dependencies: mobile_scanner, vibration, go_router

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _isStockIn = true;
  bool _torchEnabled = false;
  bool _processing = false;
  final _manualController = TextEditingController();

  @override
  void dispose() {
    _scannerController.dispose();
    _manualController.dispose();
    super.dispose();
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_processing) return;
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null || barcode.isEmpty) return;

    _processing = true;

    // Haptic feedback
    HapticFeedback.heavyImpact();

    // Navigate to product detail
    context.push('/product/$barcode');

    // Reset processing after navigation
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _processing = false;
    });
  }

  void _submitManualBarcode() {
    final barcode = _manualController.text.trim();
    if (barcode.isNotEmpty) {
      context.push('/product/$barcode');
      _manualController.clear();
      Navigator.pop(context);
    }
  }

  void _showManualEntry() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppStrings.manualEntry,
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
                hintText: AppStrings.manualEntryHint,
                hintStyle: const TextStyle(color: AppColors.textHint),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send, color: AppColors.primary),
                  onPressed: _submitManualBarcode,
                ),
              ),
              onSubmitted: (_) => _submitManualBarcode(),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Camera viewfinder ──────────────────────────────────
          MobileScanner(
            controller: _scannerController,
            onDetect: _onBarcodeDetected,
          ),

          // ── Scan overlay with corner guides ───────────────────
          CustomPaint(
            painter: _ScanOverlayPainter(),
            child: const SizedBox.expand(),
          ),

          // ── Top bar ───────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Back button
                  _CircleButton(
                    icon: Icons.arrow_back,
                    onTap: () => context.pop(),
                  ),
                  const Spacer(),
                  // Torch toggle
                  _CircleButton(
                    icon: _torchEnabled
                        ? Icons.flash_on
                        : Icons.flash_off,
                    onTap: () {
                      _scannerController.toggleTorch();
                      setState(() => _torchEnabled = !_torchEnabled);
                    },
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom controls ───────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Column(
                children: [
                  // Mode toggle
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ModeTab(
                            label: AppStrings.stockIn,
                            isActive: _isStockIn,
                            color: AppColors.stockGreen,
                            onTap: () => setState(() => _isStockIn = true),
                          ),
                        ),
                        Expanded(
                          child: _ModeTab(
                            label: AppStrings.stockOut,
                            isActive: !_isStockIn,
                            color: AppColors.stockRed,
                            onTap: () => setState(() => _isStockIn = false),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Manual entry button
                  TextButton.icon(
                    onPressed: _showManualEntry,
                    icon: const Icon(
                      Icons.keyboard,
                      color: AppColors.textSecondary,
                    ),
                    label: Text(
                      AppStrings.manualEntry,
                      style: GoogleFonts.inter(color: AppColors.textSecondary),
                    ),
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

/// Circular glassmorphism button for the scanner overlay
class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

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

/// Scan mode tab (STOCK IN / STOCK OUT)
class _ModeTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color color;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label,
    required this.isActive,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive ? Border.all(color: color, width: 1) : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isActive ? color : AppColors.textHint,
          ),
        ),
      ),
    );
  }
}

/// Custom painter for the scan overlay with corner guides
class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scanAreaSize = size.width * 0.7;
    final left = (size.width - scanAreaSize) / 2;
    final top = (size.height - scanAreaSize) / 2;
    final right = left + scanAreaSize;
    final bottom = top + scanAreaSize;

    // Dim overlay outside scan area
    final bgPaint = Paint()..color = AppColors.scanOverlay;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, top), bgPaint);
    canvas.drawRect(Rect.fromLTWH(0, bottom, size.width, size.height - bottom), bgPaint);
    canvas.drawRect(Rect.fromLTWH(0, top, left, scanAreaSize), bgPaint);
    canvas.drawRect(Rect.fromLTWH(right, top, size.width - right, scanAreaSize), bgPaint);

    // Corner guides
    const cornerLength = 30.0;
    const cornerWidth = 3.0;
    final cornerPaint = Paint()
      ..color = AppColors.scanCorner
      ..strokeWidth = cornerWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawLine(Offset(left, top), Offset(left + cornerLength, top), cornerPaint);
    canvas.drawLine(Offset(left, top), Offset(left, top + cornerLength), cornerPaint);

    // Top-right
    canvas.drawLine(Offset(right, top), Offset(right - cornerLength, top), cornerPaint);
    canvas.drawLine(Offset(right, top), Offset(right, top + cornerLength), cornerPaint);

    // Bottom-left
    canvas.drawLine(Offset(left, bottom), Offset(left + cornerLength, bottom), cornerPaint);
    canvas.drawLine(Offset(left, bottom), Offset(left, bottom - cornerLength), cornerPaint);

    // Bottom-right
    canvas.drawLine(Offset(right, bottom), Offset(right - cornerLength, bottom), cornerPaint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - cornerLength), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
