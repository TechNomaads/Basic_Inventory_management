import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import '../network/dio_client.dart';
import '../constants/api_endpoints.dart';
import 'app_database.dart';
import 'product_cache_dao.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

/// Riverpod provider for the [ProductCacheDao].
final productCacheDaoProvider = Provider<ProductCacheDao>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return ProductCacheDao(db);
});

/// Background sync service that refreshes the local Drift cache
/// from the backend API.
///
/// Runs on app startup if the last sync is older than 4 hours,
/// and on location change to refresh inventory data.
final cacheSyncServiceProvider = Provider<CacheSyncService>((ref) {
  return CacheSyncService(ref);
});

class CacheSyncService {
  final Ref _ref;
  DateTime? _lastProductSync;
  DateTime? _lastInventorySync;

  CacheSyncService(this._ref);

  /// Sync the full product catalog if stale (> 4 hours since last sync).
  Future<void> syncProductsIfNeeded() async {
    if (_lastProductSync != null &&
        DateTime.now().difference(_lastProductSync!) <
            ProductCacheDao.maxStaleness) {
      return; // Still fresh
    }

    try {
      _log.i('🔄 Syncing product catalog to local cache...');
      final dio = _ref.read(dioProvider);
      final response = await dio.get(ApiEndpoints.products);
      final List<dynamic> products = response.data is List
          ? response.data
          : (response.data['items'] as List<dynamic>? ?? []);

      final dao = _ref.read(productCacheDaoProvider);
      await dao.bulkSync(
        products.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      );

      _lastProductSync = DateTime.now();
      _log.i('✅ Product catalog synced: ${products.length} items');
    } catch (e) {
      _log.w('⚠️ Product sync failed (offline?): $e');
      // Non-fatal — stale cache will be used as fallback
    }
  }

  /// Sync inventory for a specific location.
  Future<void> syncInventoryForLocation(String locationId) async {
    try {
      _log.i('🔄 Syncing inventory for location $locationId...');
      final dio = _ref.read(dioProvider);
      final response = await dio.get(
        ApiEndpoints.inventoryByLocation(locationId),
      );
      final List<dynamic> items = response.data as List<dynamic>;

      final dao = _ref.read(productCacheDaoProvider);
      await dao.bulkSyncInventory(
        locationId,
        items.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      );

      _lastInventorySync = DateTime.now();
      _log.i('✅ Inventory synced: ${items.length} items');
    } catch (e) {
      _log.w('⚠️ Inventory sync failed (offline?): $e');
    }
  }
}
