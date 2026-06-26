import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../data/product_repository.dart';
import '../../billing/domain/billing_notifier.dart';
import '../../reports/data/reports_repository.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String barcode;

  const ProductDetailScreen({super.key, required this.barcode});

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _product;
  List<dynamic> _transactions = [];

  int _quantity = 1;
  bool _isStockIn = true;
  final _notesController = TextEditingController();

  int _currentStock = 0;
  int _currentVersion = 1;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _loadData());
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(productRepositoryProvider);
      final product = await repo.fetchProductByBarcode(widget.barcode);
      _product = product;

      // Ensure location is selected
      var locationId = ref.read(selectedLocationProvider);
      if (locationId == null) {
        final locations = await ref.read(locationsProvider.future);
        if (locations.isNotEmpty) {
          locationId = locations.first['id'] as String;
          ref.read(selectedLocationProvider.notifier).state = locationId;
        }
      }

      if (locationId != null) {
        // Refresh local inventory cache
        await ref.read(locationInventoryProvider.notifier).refreshInventory(locationId);
        final inventoryMap = ref.read(locationInventoryProvider);
        final productId = product['id'] as String;
        final inv = inventoryMap[productId];
        
        if (inv != null) {
          _currentStock = inv['quantity'] as int;
          _currentVersion = inv['version'] as int;
        } else {
          _currentStock = 0;
          _currentVersion = 1;
        }

        // Fetch recent transactions for this product
        final reportsRepo = ref.read(reportsRepositoryProvider);
        final txData = await reportsRepo.fetchTransactions(
          page: 1,
          size: 5,
          productId: productId,
        );
        _transactions = txData['items'] as List<dynamic>? ?? [];
      }

      setState(() {
        _isLoading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _errorMessage = e.response?.data?['detail']?.toString() ?? 'Product not found.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _submitTransaction() async {
    final locationId = ref.read(selectedLocationProvider);
    if (locationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a store location first.')),
      );
      return;
    }

    if (_product == null) return;

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(productRepositoryProvider);
      final productId = _product!['id'] as String;
      final type = _isStockIn ? 'receive' : 'dispatch';
      final change = _isStockIn ? _quantity : -_quantity;

      await repo.recordStockTransaction(
        productId: productId,
        locationId: locationId,
        type: type,
        quantityChange: change,
        knownVersion: _currentVersion,
        notes: _notesController.text.trim(),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isStockIn
              ? 'Stock successfully added: +$_quantity'
              : 'Stock successfully dispatched: -$_quantity'),
          backgroundColor: AppColors.stockGreen,
        ),
      );

      _notesController.clear();
      _quantity = 1;

      // Reload all details and update inventory
      await _loadData();
    } on DioException catch (e) {
      final msg = e.response?.data?['detail']?.toString() ?? 'Stock adjustment transaction failed.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _isLoading = false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationsAsync = ref.watch(locationsProvider);
    final selectedLocation = ref.watch(selectedLocationProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.productDetail,
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
            ),
            if (selectedLocation != null)
              locationsAsync.when(
                data: (locs) {
                  final currentLoc = locs.firstWhere(
                    (l) => l['id'] == selectedLocation,
                    orElse: () => {'name': 'Unknown Location'},
                  );
                  return Text(
                    currentLoc['name'] as String,
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.primaryLight),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          // Store Location Selector
          locationsAsync.when(
            data: (locs) => PopupMenuButton<String>(
              icon: const Icon(Icons.storefront, color: AppColors.textPrimary),
              tooltip: 'Change Store Location',
              onSelected: (locId) {
                ref.read(selectedLocationProvider.notifier).state = locId;
                _loadData();
              },
              itemBuilder: (context) => locs.map((loc) {
                return PopupMenuItem<String>(
                  value: loc['id'] as String,
                  child: Text(loc['name'] as String),
                );
              }).toList(),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: _isLoading && _product == null
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: AppColors.error),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 16),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _loadData,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // ── Product info card ──────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _product?['name'] ?? 'Unknown Product',
                              style: GoogleFonts.outfit(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  'SKU: ${_product?['sku'] ?? 'N/A'}',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${AppStrings.barcode}: ${widget.barcode}',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Divider(color: AppColors.divider),
                            const SizedBox(height: 12),
                            _buildInfoRow('Category', _product?['category_name'] ?? 'Uncategorized'),
                            _buildInfoRow('Supplier', _product?['supplier_name'] ?? 'N/A'),
                            _buildInfoRow('Selling Price', '₹${(_product?['sell_price'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
                            _buildInfoRow('Unit', _product?['unit'] ?? 'pcs'),
                            const SizedBox(height: 12),
                            const Divider(color: AppColors.divider),
                            const SizedBox(height: 12),

                            // Stock quantity display
                            Row(
                              children: [
                                Text(
                                  'Current Location Stock',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
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
                                    color: _currentStock <= 0
                                        ? AppColors.stockRed.withOpacity(0.12)
                                        : (_currentStock <= 5
                                            ? Colors.orange.withOpacity(0.12)
                                            : AppColors.stockGreen.withOpacity(0.12)),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _currentStock <= 0
                                          ? AppColors.stockRed.withOpacity(0.3)
                                          : (_currentStock <= 5
                                              ? Colors.orange.withOpacity(0.3)
                                              : AppColors.stockGreen.withOpacity(0.3)),
                                    ),
                                  ),
                                  child: Text(
                                    '$_currentStock',
                                    style: GoogleFonts.outfit(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: _currentStock <= 0
                                          ? AppColors.stockRed
                                          : (_currentStock <= 5 ? Colors.orange : AppColors.stockGreen),
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
                          border: Border.all(color: AppColors.divider),
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
                          border: Border.all(color: AppColors.divider),
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
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: AppColors.divider),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: AppColors.primary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Confirm button ────────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submitTransaction,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _isStockIn ? AppColors.stockGreen : AppColors.stockRed,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text(
                                  '${AppStrings.confirm} ${_isStockIn ? AppStrings.stockIn : AppStrings.stockOut}',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 32),

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
                      _transactions.isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.cardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.divider),
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
                            )
                          : Column(
                              children: _transactions.map((tx) {
                                final isPositive = (tx['quantity_change'] as num) > 0;
                                final dateStr = tx['created_at'] != null
                                    ? DateTime.parse(tx['created_at'] as String)
                                        .toLocal()
                                        .toString()
                                        .substring(0, 16)
                                    : 'N/A';
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.cardBg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.divider),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: (isPositive ? AppColors.stockGreen : AppColors.stockRed)
                                              .withOpacity(0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isPositive ? Icons.add : Icons.remove,
                                          color: isPositive ? AppColors.stockGreen : AppColors.stockRed,
                                          size: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              tx['type']?.toString().toUpperCase() ?? 'TRANSACTION',
                                              style: GoogleFonts.outfit(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'By: ${tx['user_name'] ?? 'System'} | $dateStr',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        '${isPositive ? '+' : ''}${tx['quantity_change']}',
                                        style: GoogleFonts.outfit(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isPositive ? AppColors.stockGreen : AppColors.stockRed,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
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
