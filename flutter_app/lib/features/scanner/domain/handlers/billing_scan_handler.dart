import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../billing/domain/billing_notifier.dart';
import '../../../billing/domain/cart_item.dart';
import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/cache_sync_service.dart';
import '../../../../core/storage/app_database.dart';
import '../scan_handler.dart';

/// Billing mode scan handler — offline-first product lookup → add to cart.
///
/// Flow:
///   1. Look up product in local Drift cache (offline-first)
///   2. If cache miss or stale → try API fallback → cache result
///   3. Validate stock availability from local inventory cache
///   4. Add product to cart via [BillingNotifier]
///   5. Camera stays open (continuous scanning)
class BillingScanHandler extends ScanHandler {
  final WidgetRef _ref;

  BillingScanHandler(this._ref);

  @override
  Future<ScanResult> handleBarcode(String rawValue) async {
    final locationId = _ref.read(selectedLocationProvider);
    if (locationId == null) {
      return const ScanResult(
        success: false,
        message: 'Please select a store location first.',
      );
    }

    try {
      // 1. Attempt offline-first product lookup
      final productData = await _resolveProduct(rawValue);
      if (productData == null) {
        return ScanResult(
          success: false,
          message: 'Unknown barcode: $rawValue',
        );
      }

      final productId = productData['id'] as String;
      final productName = productData['name'] as String;
      final sellPrice = (productData['sell_price'] as num).toDouble();

      // 2. Check local inventory cache for stock availability
      var inventoryMap = _ref.read(locationInventoryProvider);
      if (inventoryMap.isEmpty) {
        await _ref
            .read(locationInventoryProvider.notifier)
            .refreshInventory(locationId);
        inventoryMap = _ref.read(locationInventoryProvider);
      }

      final inv = inventoryMap[productId];
      if (inv == null) {
        return ScanResult(
          success: false,
          message: "'$productName' has no stock at this location.",
        );
      }

      final int stockQty = inv['quantity'] as int;
      final int version = inv['version'] as int;

      if (stockQty <= 0) {
        return ScanResult(
          success: false,
          message: "'$productName' is out of stock.",
        );
      }

      // 3. Check if already in cart and at stock limit
      final cart = _ref.read(cartProvider);
      final existingItem = cart.items.cast<CartItem?>().firstWhere(
            (item) => item?.productId == productId,
            orElse: () => null,
          );

      if (existingItem != null && existingItem.quantity >= stockQty) {
        return ScanResult(
          success: false,
          message:
              "Cannot add more '$productName'. Only $stockQty in stock.",
        );
      }

      // 4. Add to cart
      if (existingItem != null) {
        _ref.read(cartProvider.notifier).updateQuantity(
              productId,
              existingItem.quantity + 1,
            );
      } else {
        final taxRate =
            (productData['tax_rate'] as num?)?.toDouble() ?? 18.0;
        final newItem = CartItem(
          productId: productId,
          name: productName,
          barcode: rawValue,
          sellPrice: sellPrice,
          sku: productData['sku'] as String,
          quantity: 1,
          stockQuantity: stockQty,
          knownVersion: version,
          taxRate: taxRate,
        );
        _ref.read(cartProvider.notifier).addCartItem(newItem);
      }

      return ScanResult(
        success: true,
        message: 'Added: $productName  ₹${sellPrice.toStringAsFixed(2)}',
        keepScanning: true,
      );
    } on DioException catch (e) {
      final msg = e.response?.data?['detail']?.toString() ??
          'Failed to look up product.';
      return ScanResult(success: false, message: msg);
    } catch (e) {
      return ScanResult(success: false, message: 'Error: $e');
    }
  }

  /// Offline-first product resolution:
  ///   1. Check Drift cache
  ///   2. If miss or stale → try API
  ///   3. If API fails + stale cache exists → use stale data (graceful degradation)
  Future<Map<String, dynamic>?> _resolveProduct(String barcode) async {
    final dao = _ref.read(productCacheDaoProvider);

    // Check local cache first
    final cached = await dao.getByBarcode(barcode);
    if (cached != null && !dao.isStale(cached)) {
      return _cachedProductToMap(cached);
    }

    // Cache miss or stale — try API
    try {
      final dio = _ref.read(dioProvider);
      final response =
          await dio.get(ApiEndpoints.productByBarcode(barcode));
      final data = response.data as Map<String, dynamic>;

      // Cache the fresh API response
      await dao.upsertProduct(data);
      return data;
    } catch (_) {
      // API failed — use stale cache if available (graceful degradation)
      if (cached != null) {
        return _cachedProductToMap(cached);
      }
      return null; // Truly unknown barcode
    }
  }

  Map<String, dynamic> _cachedProductToMap(CachedProduct p) => {
        'id': p.id,
        'barcode': p.barcode,
        'name': p.name,
        'sku': p.sku,
        'sell_price': p.sellPrice,
        'cost_price': p.costPrice,
        'tax_rate': p.taxRate,
        'unit': p.unit,
      };
}
