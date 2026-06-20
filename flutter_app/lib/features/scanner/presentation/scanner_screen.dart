/// [ScannerScreen] — Full-screen barcode scanner for Inventory mode.
///
/// Responsibilities:
///   - Delegates camera and overlay to [UnifiedScannerWidget]
///   - Provides STOCK IN / STOCK OUT toggle as bottom controls
///   - Uses [InventoryScanHandler] for barcode processing
///
/// Dependencies: UnifiedScannerWidget, InventoryScanHandler, go_router

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../domain/scan_mode.dart';
import '../domain/handlers/inventory_scan_handler.dart';
import 'unified_scanner_widget.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  final ScanMode initialMode;

  const ScannerScreen({super.key, this.initialMode = ScanMode.inventory});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  bool _isStockIn = true;
  late final InventoryScanHandler _handler;

  @override
  void initState() {
    super.initState();
    _handler = InventoryScanHandler(ref);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: UnifiedScannerWidget(
        mode: widget.initialMode,
        handler: _handler,
        onBack: () => context.pop(),
        bottomControls: _buildModeToggle(),
      ),
    );
  }

  /// STOCK IN / STOCK OUT toggle — inventory-specific control.
  Widget _buildModeToggle() {
    return Container(
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
