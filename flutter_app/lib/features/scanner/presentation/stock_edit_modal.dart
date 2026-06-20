import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/cache_sync_service.dart';
import '../../billing/domain/billing_notifier.dart';

/// Quick-edit bottom sheet for adjusting stock on an existing product.
///
/// Shown by [InventoryScanHandler] when a known barcode is scanned
/// in Inventory mode. Allows rapid +/- stock adjustments without
/// leaving the scanner flow.
class StockEditModal extends ConsumerStatefulWidget {
  final String productId;
  final String productName;
  final String barcode;
  final String sku;
  final int currentStock;
  final int currentVersion;
  final String? locationId;

  const StockEditModal({
    super.key,
    required this.productId,
    required this.productName,
    required this.barcode,
    required this.sku,
    required this.currentStock,
    required this.currentVersion,
    required this.locationId,
  });

  @override
  ConsumerState<StockEditModal> createState() => _StockEditModalState();
}

class _StockEditModalState extends ConsumerState<StockEditModal> {
  final _qtyController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _isAdding = true; // true = add stock, false = remove stock
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _qtyController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submitAdjustment() async {
    final qtyText = _qtyController.text.trim();
    if (qtyText.isEmpty) {
      setState(() => _error = 'Please enter a quantity.');
      return;
    }

    final qty = int.tryParse(qtyText);
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Enter a valid positive number.');
      return;
    }

    if (widget.locationId == null) {
      setState(() => _error = 'No store location selected.');
      return;
    }

    // Validate removal doesn't go negative
    if (!_isAdding && qty > widget.currentStock) {
      setState(() =>
          _error = 'Cannot remove $qty. Only ${widget.currentStock} in stock.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final adjustment = _isAdding ? qty : -qty;
      final reason = _reasonController.text.trim().isEmpty
          ? 'Scanner quick-adjust'
          : _reasonController.text.trim();

      final response = await dio.post(
        ApiEndpoints.quickAdjust,
        data: {
          'barcode': widget.barcode,
          'location_id': widget.locationId,
          'adjustment': adjustment,
          'reason': reason,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final newQty = data['new_quantity'] as int;
      final newVersion = data['new_version'] as int;

      // Update local inventory cache
      ref.read(locationInventoryProvider.notifier).updateProductStock(
            widget.productId,
            adjustment,
            newVersion,
          );

      // Update Drift cache
      final dao = ref.read(productCacheDaoProvider);
      await dao.upsertInventory(
        widget.productId,
        widget.locationId!,
        newQty,
        newVersion,
      );

      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Stock updated: ${widget.productName} → $newQty units',
            ),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['detail']?.toString() ??
          'Failed to update stock.';
      setState(() {
        _isLoading = false;
        _error = msg;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textHint.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Product info header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.inventory_2_rounded,
                      color: AppColors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.productName,
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'SKU: ${widget.sku}  •  ${widget.barcode}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Current stock badge
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warehouse_outlined,
                      color: AppColors.textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Current Stock: ',
                    style: GoogleFonts.inter(
                        color: AppColors.textSecondary, fontSize: 14),
                  ),
                  Text(
                    '${widget.currentStock} units',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: widget.currentStock > 0
                          ? AppColors.stockGreen
                          : AppColors.stockRed,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Add / Remove segmented control
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surfaceBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _SegmentButton(
                      label: '+ Add Stock',
                      isActive: _isAdding,
                      activeColor: AppColors.stockGreen,
                      onTap: () => setState(() => _isAdding = true),
                    ),
                  ),
                  Expanded(
                    child: _SegmentButton(
                      label: '- Remove Stock',
                      isActive: !_isAdding,
                      activeColor: AppColors.stockRed,
                      onTap: () => setState(() => _isAdding = false),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Quantity input
            TextField(
              controller: _qtyController,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                labelText: 'Quantity',
                labelStyle: const TextStyle(color: AppColors.textHint),
                hintText: 'Enter quantity...',
                hintStyle: const TextStyle(color: AppColors.textHint),
                prefixIcon: Icon(
                  _isAdding ? Icons.add_circle_outline : Icons.remove_circle_outline,
                  color: _isAdding ? AppColors.stockGreen : AppColors.stockRed,
                ),
                filled: true,
                fillColor: AppColors.surfaceBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Reason (optional)
            TextField(
              controller: _reasonController,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Reason (optional)',
                labelStyle: const TextStyle(color: AppColors.textHint),
                hintText: 'e.g. New shipment received',
                hintStyle: const TextStyle(color: AppColors.textHint),
                filled: true,
                fillColor: AppColors.surfaceBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Error message
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _error!,
                  style: GoogleFonts.inter(color: AppColors.error, fontSize: 13),
                ),
              ),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.divider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.outfit(
                          color: AppColors.textSecondary, fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitAdjustment,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor:
                          _isAdding ? AppColors.stockGreen : AppColors.stockRed,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _isAdding ? 'Add Stock' : 'Remove Stock',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.isActive,
    required this.activeColor,
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
          color: isActive ? activeColor.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive ? Border.all(color: activeColor, width: 1) : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isActive ? activeColor : AppColors.textHint,
          ),
        ),
      ),
    );
  }
}
