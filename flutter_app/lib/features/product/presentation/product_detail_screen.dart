/// [ProductDetailScreen] — Post-scan product view with stock actions.
///
/// Responsibilities:
///   - Show product info (name, SKU, barcode, category, location)
///   - Stock quantity with colour indicator (green/amber/red)
///   - Quantity stepper for stock in/out
///   - Last 5 transactions for this product
///
/// Dependencies: Riverpod, AppColors

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String barcode;

  const ProductDetailScreen({super.key, required this.barcode});

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  int _quantity = 1;
  bool _isStockIn = true;
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text(AppStrings.productDetail),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Product info card ──────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Loading product...',
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${AppStrings.barcode}: ${widget.barcode}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: AppColors.divider),
                const SizedBox(height: 12),

                // Stock quantity display
                Row(
                  children: [
                    Text(
                      AppStrings.quantity,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.stockGreen.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.stockGreen.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        '—',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.stockGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Mode toggle ───────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surfaceBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildModeButton(
                    AppStrings.stockIn,
                    _isStockIn,
                    AppColors.stockGreen,
                    () => setState(() => _isStockIn = true),
                  ),
                ),
                Expanded(
                  child: _buildModeButton(
                    AppStrings.stockOut,
                    !_isStockIn,
                    AppColors.stockRed,
                    () => setState(() => _isStockIn = false),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Quantity stepper ───────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StepperButton(
                  icon: Icons.remove,
                  onTap: () {
                    if (_quantity > 1) setState(() => _quantity--);
                  },
                ),
                const SizedBox(width: 24),
                Text(
                  '$_quantity',
                  style: GoogleFonts.outfit(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 24),
                _StepperButton(
                  icon: Icons.add,
                  onTap: () {
                    if (_quantity < 999) setState(() => _quantity++);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Notes field ───────────────────────────────────────
          TextField(
            controller: _notesController,
            maxLines: 2,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: AppStrings.adjustmentNotes,
              hintStyle: const TextStyle(color: AppColors.textHint),
              filled: true,
              fillColor: AppColors.cardBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Confirm button ────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                // Submit transaction
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _isStockIn
                          ? 'Stock in: +$_quantity'
                          : 'Stock out: -$_quantity',
                    ),
                    backgroundColor: _isStockIn
                        ? AppColors.stockGreen
                        : AppColors.stockRed,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isStockIn ? AppColors.stockGreen : AppColors.stockRed,
              ),
              child: Text(
                '${AppStrings.confirm} ${_isStockIn ? AppStrings.stockIn : AppStrings.stockOut}',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Recent transactions ───────────────────────────────
          Text(
            AppStrings.recentTransactions,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                AppStrings.noTransactions,
                style: GoogleFonts.inter(
                  color: AppColors.textHint,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(
    String label,
    bool isActive,
    Color color,
    VoidCallback onTap,
  ) {
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

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.surfaceBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 24),
      ),
    );
  }
}
