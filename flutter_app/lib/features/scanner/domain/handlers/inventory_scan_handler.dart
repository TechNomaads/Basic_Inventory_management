import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/cache_sync_service.dart';
import '../../../../core/storage/app_database.dart';
import '../../billing/domain/billing_notifier.dart';
import '../scan_handler.dart';
import '../../scanner/presentation/stock_edit_modal.dart';
import '../../scanner/presentation/quick_add_product_modal.dart';

/// Inventory mode scan handler — stock edit or new product creation.
///
/// Flow:
///   1. Look up product by barcode (Drift cache → API fallback)
///   2. If FOUND → return StockEditModal as prompt
///   3. If NOT FOUND → return QuickAddProductModal as prompt
class InventoryScanHandler extends ScanHandler {
  final Ref _ref;

  InventoryScanHandler(this._ref);

  @override
  Future<ScanResult> handleBarcode(String rawValue) async {
    final locationId = _ref.read(selectedLocationProvider);

    try {
      // 1. Resolve product via offline-first lookup
      final productData = await _resolveProduct(rawValue);

      if (productData != null) {
        // Product found — get current stock info
        int currentStock = 0;
        int currentVersion = 0;

        if (locationId != null) {
          final inventoryMap = _ref.read(locationInventoryProvider);
          final inv = inventoryMap[productData['id'] as String];
          if (inv != null) {
            currentStock = inv['quantity'] as int;
            currentVersion = inv['version'] as int;
          }
        }

        return ScanResult(
          success: true,
          message: 'Found: ${productData['name']}',
          promptWidget: StockEditModal(
            productId: productData['id'] as String,
            productName: productData['name'] as String,
            barcode: rawValue,
            sku: productData['sku'] as String,
            currentStock: currentStock,
            currentVersion: currentVersion,
            locationId: locationId,
          ),
          keepScanning: true,
        );
      } else {
        // Product not found — prompt to add new product
        return ScanResult(
          success: true,
          message: 'New barcode detected',
          promptWidget: QuickAddProductModal(barcode: rawValue),
          keepScanning: true,
        );
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['detail']?.toString() ??
          'Failed to look up barcode.';
      return ScanResult(success: false, message: msg);
    } catch (e) {
      return ScanResult(success: false, message: 'Error: $e');
    }
  }

  /// Offline-first product resolution (same strategy as billing handler).
  Future<Map<String, dynamic>?> _resolveProduct(String barcode) async {
    final dao = _ref.read(productCacheDaoProvider);

    final cached = await dao.getByBarcode(barcode);
    if (cached != null && !dao.isStale(cached)) {
      return _cachedProductToMap(cached);
    }

    try {
      final dio = _ref.read(dioProvider);
      final response =
          await dio.get(ApiEndpoints.productByBarcode(barcode));
      final data = response.data as Map<String, dynamic>;
      await dao.upsertProduct(data);
      return data;
    } catch (_) {
      if (cached != null) return _cachedProductToMap(cached);
      return null;
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
