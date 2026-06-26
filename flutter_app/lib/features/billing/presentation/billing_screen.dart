import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../domain/billing_notifier.dart';
import '../domain/cart_state.dart';
import '../../scanner/domain/scan_mode.dart';
import '../../scanner/domain/handlers/billing_scan_handler.dart';
import '../../scanner/presentation/unified_scanner_widget.dart';
import 'cart_sheet.dart';
import '../../../core/storage/cache_sync_service.dart';
import '../../../core/storage/app_database.dart';
import '../../scanner/domain/scan_audio_feedback.dart';

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  late final BillingScanHandler _handler;

  @override
  void initState() {
    super.initState();
    _handler = BillingScanHandler(ref);

    // Fetch locations and set default if not set yet
    Future.microtask(() async {
      final locationsAsync = await ref.read(locationsProvider.future);
      if (locationsAsync.isNotEmpty && ref.read(selectedLocationProvider) == null) {
        final firstLocId = locationsAsync.first['id'] as String;
        ref.read(selectedLocationProvider.notifier).state = firstLocId;
        ref.read(locationInventoryProvider.notifier).refreshInventory(firstLocId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final locationsAsync = ref.watch(locationsProvider);
    final selectedLocation = ref.watch(selectedLocationProvider);
    final cart = ref.watch(cartProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'POS Billing',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
            ),
            locationsAsync.when(
              data: (locs) {
                final currentLoc = locs.firstWhere(
                  (l) => l['id'] == selectedLocation,
                  orElse: () => {'name': 'Select Location'},
                );
                return Text(
                  currentLoc['name'] as String,
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.primaryLight),
                );
              },
              loading: () => const Text('Loading locations...', style: TextStyle(fontSize: 12)),
              error: (_, __) => const Text('Error loading locations', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ref.read(cartProvider.notifier).clearCart();
            context.pop();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: AppColors.textPrimary),
            tooltip: 'Search Products Manually',
            onPressed: selectedLocation == null
                ? null
                : () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => const _ManualSearchSheet(),
                    );
                  },
          ),
          // Store Location Selector Dropdown
          locationsAsync.when(
            data: (locs) => PopupMenuButton<String>(
              icon: const Icon(Icons.storefront, color: AppColors.textPrimary),
              tooltip: 'Change Store Location',
              onSelected: (locId) {
                ref.read(selectedLocationProvider.notifier).state = locId;
                ref.read(locationInventoryProvider.notifier).refreshInventory(locId);
                ref.read(cartProvider.notifier).clearCart();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Switched store location and cleared cart.'),
                    backgroundColor: AppColors.primary,
                  ),
                );
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
          if (cart.items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.error),
              tooltip: 'Clear Cart',
              onPressed: () {
                ref.read(cartProvider.notifier).clearCart();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cart cleared.')),
                );
              },
            ),
        ],
      ),
      body: selectedLocation == null
          ? _buildLocationSelectorPlaceholder(locationsAsync)
          : Stack(
              children: [
                // ── Unified Scanner (camera + overlay + debounce) ──
                Positioned.fill(
                  child: UnifiedScannerWidget(
                    mode: ScanMode.billing,
                    handler: _handler,
                    // No back button — AppBar handles it
                    onBack: null,
                  ),
                ),

                // ── Interactive Sliding Bottom Cart Sheet ──────────
                if (cart.items.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildBottomCartBar(cart),
                  ),
              ],
            ),
    );
  }

  Widget _buildLocationSelectorPlaceholder(AsyncValue<List<Map<String, dynamic>>> locationsAsync) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary.withOpacity(0.2), width: 3),
              ),
              child: const Icon(Icons.storefront_outlined, size: 72, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'Select Store Location',
              style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'A location selection is required to fetch correct stock levels and versions for optimistic locking.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 32),
            locationsAsync.when(
              data: (locs) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: AppColors.cardBg,
                    hint: const Text('Choose store location...', style: TextStyle(color: AppColors.textHint)),
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
                    icon: const Icon(Icons.arrow_drop_down, color: AppColors.primary),
                    isExpanded: true,
                    onChanged: (locId) {
                      if (locId != null) {
                        ref.read(selectedLocationProvider.notifier).state = locId;
                        ref.read(locationInventoryProvider.notifier).refreshInventory(locId);
                      }
                    },
                    items: locs.map((loc) {
                      return DropdownMenuItem<String>(
                        value: loc['id'] as String,
                        child: Text(loc['name'] as String),
                      );
                    }).toList(),
                  ),
                ),
              ),
              loading: () => const CircularProgressIndicator(),
              error: (err, _) => Text('Error loading locations: $err', style: const TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomCartBar(CartState cart) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => const CartSheet(),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: const Border(top: BorderSide(color: AppColors.divider)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.shopping_bag_outlined, color: AppColors.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${cart.items.length} Item${cart.items.length > 1 ? 's' : ''}',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Tap to view cart details',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '₹${cart.totalAmount.toStringAsFixed(2)}',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                  Text(
                    'Subtotal: ₹${cart.subtotal.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              const Icon(Icons.keyboard_arrow_up, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualSearchSheet extends ConsumerStatefulWidget {
  const _ManualSearchSheet();

  @override
  ConsumerState<_ManualSearchSheet> createState() => _ManualSearchSheetState();
}

class _ManualSearchSheetState extends ConsumerState<_ManualSearchSheet> {
  final _searchController = TextEditingController();
  List<CachedProduct> _searchResults = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _performSearch('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isLoading = true);
    try {
      final dao = ref.read(productCacheDaoProvider);
      final results = await dao.searchProducts(query);
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventoryMap = ref.watch(locationInventoryProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: 20 + bottomInset,
      ),
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Manual Product Search',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(color: AppColors.textPrimary),
            onChanged: _performSearch,
            decoration: InputDecoration(
              hintText: 'Search by name, SKU or barcode...',
              hintStyle: const TextStyle(color: AppColors.textHint),
              prefixIcon: const Icon(Icons.search, color: AppColors.primary),
              filled: true,
              fillColor: AppColors.surfaceBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                    ? Center(
                        child: Text(
                          'No products found',
                          style: GoogleFonts.inter(color: AppColors.textHint),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final product = _searchResults[index];
                          final inv = inventoryMap[product.id];
                          final stockQty = inv?['quantity'] as int? ?? 0;
                          final isOutOfStock = stockQty <= 0;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.name,
                                        style: GoogleFonts.outfit(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Text(
                                            'SKU: ${product.sku}',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            'Price: ₹${product.sellPrice.toStringAsFixed(2)}',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.accent,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isOutOfStock
                                              ? AppColors.stockRed.withOpacity(0.1)
                                              : (stockQty <= 5
                                                  ? Colors.orange.withOpacity(0.1)
                                                  : AppColors.stockGreen.withOpacity(0.1)),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          isOutOfStock
                                              ? 'Out of Stock'
                                              : '$stockQty available',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: isOutOfStock
                                                ? AppColors.stockRed
                                                : (stockQty <= 5
                                                    ? Colors.orange
                                                    : AppColors.stockGreen),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_shopping_cart),
                                  color: isOutOfStock ? AppColors.textHint : AppColors.primary,
                                  onPressed: isOutOfStock
                                      ? null
                                      : () async {
                                          final success = await ref
                                              .read(cartProvider.notifier)
                                              .addProductDirectly(product.id);
                                          if (success) {
                                            ScanAudioFeedback.playBillingBeep();
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Added ${product.name} to cart'),
                                                duration: const Duration(seconds: 1),
                                                backgroundColor: AppColors.stockGreen,
                                              ),
                                            );
                                          } else {
                                            ScanAudioFeedback.playErrorBuzz();
                                            final errMsg = ref.read(cartProvider).errorMessage ?? 'Failed to add item';
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(errMsg),
                                                backgroundColor: AppColors.error,
                                              ),
                                            );
                                          }
                                        },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
