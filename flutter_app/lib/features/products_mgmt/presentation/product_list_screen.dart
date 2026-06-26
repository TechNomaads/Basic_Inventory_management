import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../auth/domain/auth_notifier.dart';
import '../../billing/domain/billing_notifier.dart';
import '../../product/data/product_repository.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  final String? initialFilter;

  const ProductListScreen({super.key, this.initialFilter});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  final _searchController = TextEditingController();
  int _currentPage = 1;
  bool _isLoading = false;
  List<Map<String, dynamic>> _products = [];
  int _totalPages = 1;
  int _totalProductsCount = 0;
  String? _errorMessage;
  bool _lowStockOnly = false;

  @override
  void initState() {
    super.initState();
    _lowStockOnly = widget.initialFilter == 'low_stock';
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(productRepositoryProvider);
      final result = await repo.fetchProducts(
        search: _searchController.text.trim(),
        page: _currentPage,
      );

      setState(() {
        _products = List<Map<String, dynamic>>.from(result['items']);
        _totalPages = result['pages'] as int;
        _totalProductsCount = result['total'] as int;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load products: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _triggerSearch() {
    setState(() {
      _currentPage = 1;
    });
    _loadProducts();
  }

  void _confirmDelete(String id, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: Text(
          'Delete Product',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        content: Text(
          'Are you sure you want to delete "$name"? This action will deactivate the product.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final repo = ref.read(productRepositoryProvider);
                await repo.deleteProduct(id);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Product deactivated.'), backgroundColor: AppColors.success),
                );
                _loadProducts();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete: $e'), backgroundColor: AppColors.error),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.stockRed),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isAdmin = authState is AuthAuthenticated && authState.user.canManage;
    
    // Watch inventory cache map to display local stock quantities
    final inventoryMap = ref.watch(locationInventoryProvider);
    final locationId = ref.watch(selectedLocationProvider);

    // Apply client-side low-stock filtering if active
    var displayedProducts = _products;
    if (_lowStockOnly && locationId != null) {
      displayedProducts = _products.where((p) {
        final productId = p['id'] as String;
        final inv = inventoryMap[productId];
        if (inv == null) return false; // Or treat as 0
        final qty = inv['quantity'] as int;
        // In this mock, let's treat low stock threshold dynamically (e.g. < 10)
        return qty < 10;
      }).toList();
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(
          'Products Directory',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.accent, size: 28),
              tooltip: 'Add Product',
              onPressed: () async {
                await context.push('/products-mgmt/add');
                _loadProducts();
              },
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Search & Filter Controls ───────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: AppStrings.searchHint,
                      hintStyle: const TextStyle(color: AppColors.textHint),
                      prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
                      filled: true,
                      fillColor: AppColors.cardBg,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.divider),
                      ),
                    ),
                    onSubmitted: (_) => _triggerSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _triggerSearch,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  child: const Icon(Icons.arrow_forward),
                ),
              ],
            ),
          ),

          // Low stock filter chip
          if (locationId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  label: const Text('Low Stock Alerts'),
                  selected: _lowStockOnly,
                  selectedColor: AppColors.stockRed.withOpacity(0.2),
                  checkmarkColor: AppColors.stockRed,
                  labelStyle: TextStyle(
                    color: _lowStockOnly ? AppColors.stockRed : AppColors.textSecondary,
                    fontWeight: _lowStockOnly ? FontWeight.bold : FontWeight.normal,
                  ),
                  backgroundColor: AppColors.cardBg,
                  onSelected: (selected) {
                    setState(() {
                      _lowStockOnly = selected;
                    });
                  },
                ),
              ),
            ),

          // ── Products List View ─────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Text(_errorMessage!, style: const TextStyle(color: AppColors.stockRed)),
                      )
                    : displayedProducts.isEmpty
                        ? const Center(
                            child: Text(
                              'No products found.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: displayedProducts.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final p = displayedProducts[index];
                              final id = p['id'] as String;
                              final name = p['name'] as String;
                              final barcode = p['barcode'] as String;
                              final sku = p['sku'] as String;
                              final sellPrice = (p['sell_price'] as num? ?? 0.0).toDouble();
                              final costPrice = (p['cost_price'] as num? ?? 0.0).toDouble();
                              final categoryName = p['category_name'] as String? ?? 'N/A';
                              
                              // Local location inventory stock lookup
                              int stock = 0;
                              if (locationId != null && inventoryMap.containsKey(id)) {
                                stock = inventoryMap[id]!['quantity'] as int;
                              }

                              final isLow = stock < 10;

                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppColors.cardBg,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppColors.divider),
                                ),
                                child: InkWell(
                                  onTap: () async {
                                    await context.push('/product/$barcode');
                                    // Refresh listing and cache
                                    if (locationId != null) {
                                      ref.read(locationInventoryProvider.notifier).refreshInventory(locationId);
                                    }
                                    _loadProducts();
                                  },
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: GoogleFonts.outfit(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'SKU: $sku | Barcode: $barcode',
                                              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textHint),
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.surfaceBg,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    categoryName,
                                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Text(
                                                  'Sell: ₹${sellPrice.toStringAsFixed(2)}',
                                                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.accent, fontWeight: FontWeight.w600),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'Cost: ₹${costPrice.toStringAsFixed(2)}',
                                                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.textHint),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: (isLow ? AppColors.stockRed : AppColors.stockGreen).withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: (isLow ? AppColors.stockRed : AppColors.stockGreen).withOpacity(0.3)),
                                            ),
                                            child: Text(
                                              '$stock pcs',
                                              style: GoogleFonts.outfit(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: isLow ? AppColors.stockRed : AppColors.stockGreen,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          if (isAdmin)
                                            Row(
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
                                                  constraints: const BoxConstraints(),
                                                  padding: EdgeInsets.zero,
                                                  onPressed: () async {
                                                    await context.push('/products-mgmt/edit/$id');
                                                    _loadProducts();
                                                  },
                                                ),
                                                const SizedBox(width: 12),
                                                IconButton(
                                                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.stockRed, size: 20),
                                                  constraints: const BoxConstraints(),
                                                  padding: EdgeInsets.zero,
                                                  onPressed: () => _confirmDelete(id, name),
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),

          // ── Pagination Controls ───────────────────────────────
          if (_totalPages > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    color: AppColors.textPrimary,
                    onPressed: _currentPage > 1
                        ? () {
                            setState(() => _currentPage--);
                            _loadProducts();
                          }
                        : null,
                  ),
                  Text(
                    'Page $_currentPage of $_totalPages',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    color: AppColors.textPrimary,
                    onPressed: _currentPage < _totalPages
                        ? () {
                            setState(() => _currentPage++);
                            _loadProducts();
                          }
                        : null,
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: (isAdmin && displayedProducts.isNotEmpty)
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              onPressed: () async {
                await context.push('/products-mgmt/add');
                _loadProducts();
              },
              icon: const Icon(Icons.add),
              label: const Text(AppStrings.addProduct),
            )
          : null,
    );
  }
}
