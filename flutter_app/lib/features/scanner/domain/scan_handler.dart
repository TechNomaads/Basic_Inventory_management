import 'package:flutter/widgets.dart';

/// Result of processing a scanned barcode, returned by [ScanHandler].
class ScanResult {
  /// Whether the barcode was successfully processed.
  final bool success;

  /// User-facing message for snackbar display (e.g. "Added: Widget X ₹120").
  final String? message;

  /// Optional widget to present as a modal bottom sheet
  /// (e.g. StockEditModal, QuickAddProductModal).
  final Widget? promptWidget;

  /// If true, the camera continues scanning after this result.
  /// If false, scanning pauses (e.g. waiting for user modal interaction).
  final bool keepScanning;

  const ScanResult({
    required this.success,
    this.message,
    this.promptWidget,
    this.keepScanning = true,
  });
}

/// Abstract strategy interface for mode-specific barcode processing.
///
/// Implementations:
///   - [BillingScanHandler] — looks up product, adds to cart
///   - [InventoryScanHandler] — shows stock-edit or quick-add modal
abstract class ScanHandler {
  /// Process a raw barcode string detected by the camera.
  ///
  /// Returns a [ScanResult] that the unified scanner widget uses to
  /// decide what UI feedback to show (snackbar, modal, audio).
  Future<ScanResult> handleBarcode(String rawValue);

  /// Release any resources held by this handler.
  void dispose() {}
}
