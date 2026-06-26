import 'package:drift/drift.dart';

import 'app_database.dart';

part 'product_cache_dao.g.dart';

/// Data access object for offline product and inventory cache operations.
///
/// Provides offline-first barcode lookups and bulk sync capabilities
/// used by scan handlers before falling back to the network API.
@DriftAccessor(tables: [CachedProducts, CachedInventory])
class ProductCacheDao extends DatabaseAccessor<AppDatabase>
    with _$ProductCacheDaoMixin {
  ProductCacheDao(super.db);

  /// Maximum age before a cached product is considered stale.
  static const Duration maxStaleness = Duration(hours: 4);

  // ── Product Cache ─────────────────────────────────────────────

  /// Look up a product by barcode in the local cache.
  Future<CachedProduct?> getByBarcode(String barcode) async {
    return (select(cachedProducts)
          ..where((t) => t.barcode.equals(barcode)))
        .getSingleOrNull();
  }

  /// Look up a product by its server-side ID.
  Future<CachedProduct?> getById(String productId) async {
    return (select(cachedProducts)
          ..where((t) => t.id.equals(productId)))
        .getSingleOrNull();
  }

  /// Search products in the local cache by name, SKU, or barcode.
  Future<List<CachedProduct>> searchProducts(String query) async {
    if (query.isEmpty) {
      return select(cachedProducts).get();
    }
    return (select(cachedProducts)
          ..where((t) =>
              t.name.like('%$query%') |
              t.sku.like('%$query%') |
              t.barcode.like('%$query%')))
        .get();
  }

  /// Insert or update a product from an API response map.
  Future<void> upsertProduct(Map<String, dynamic> data) async {
    await into(cachedProducts).insertOnConflictUpdate(
      CachedProductsCompanion.insert(
        id: data['id'] as String,
        barcode: data['barcode'] as String,
        name: data['name'] as String,
        sku: data['sku'] as String,
        sellPrice: (data['sell_price'] as num).toDouble(),
        costPrice: Value((data['cost_price'] as num?)?.toDouble()),
        taxRate: Value((data['tax_rate'] as num?)?.toDouble() ?? 18.0),
        categoryName: Value(data['category']?['name'] as String?),
        unit: Value(data['unit'] as String? ?? 'pcs'),
        cachedAt: DateTime.now(),
      ),
    );
  }

  /// Bulk sync a list of products (e.g. full catalog refresh).
  Future<void> bulkSync(List<Map<String, dynamic>> products) async {
    await batch((b) {
      for (final data in products) {
        b.insert(
          cachedProducts,
          CachedProductsCompanion.insert(
            id: data['id'] as String,
            barcode: data['barcode'] as String,
            name: data['name'] as String,
            sku: data['sku'] as String,
            sellPrice: (data['sell_price'] as num).toDouble(),
            costPrice: Value((data['cost_price'] as num?)?.toDouble()),
            taxRate: Value((data['tax_rate'] as num?)?.toDouble() ?? 18.0),
            categoryName: Value(data['category']?['name'] as String?),
            unit: Value(data['unit'] as String? ?? 'pcs'),
            cachedAt: DateTime.now(),
          ),
          onConflict: DoUpdate(
            (old) => CachedProductsCompanion(
              barcode: Value(data['barcode'] as String),
              name: Value(data['name'] as String),
              sku: Value(data['sku'] as String),
              sellPrice: Value((data['sell_price'] as num).toDouble()),
              costPrice: Value((data['cost_price'] as num?)?.toDouble()),
              taxRate:
                  Value((data['tax_rate'] as num?)?.toDouble() ?? 18.0),
              categoryName: Value(data['category']?['name'] as String?),
              unit: Value(data['unit'] as String? ?? 'pcs'),
              cachedAt: Value(DateTime.now()),
            ),
          ),
        );
      }
    });
  }

  /// Check whether a cached product is stale (older than [maxStaleness]).
  bool isStale(CachedProduct product) {
    return DateTime.now().difference(product.cachedAt) > maxStaleness;
  }

  // ── Inventory Cache ───────────────────────────────────────────

  /// Get cached inventory for a product at a specific location.
  Future<CachedInventoryData?> getInventory(
    String productId,
    String locationId,
  ) async {
    return (select(cachedInventory)
          ..where((t) =>
              t.productId.equals(productId) &
              t.locationId.equals(locationId)))
        .getSingleOrNull();
  }

  /// Insert or update an inventory cache entry.
  Future<void> upsertInventory(
    String productId,
    String locationId,
    int qty,
    int version,
  ) async {
    await into(cachedInventory).insertOnConflictUpdate(
      CachedInventoryCompanion.insert(
        productId: productId,
        locationId: locationId,
        quantity: qty,
        version: version,
        cachedAt: DateTime.now(),
      ),
    );
  }

  /// Bulk sync inventory for a location.
  Future<void> bulkSyncInventory(
    String locationId,
    List<Map<String, dynamic>> items,
  ) async {
    // Clear old entries for this location first
    await (delete(cachedInventory)
          ..where((t) => t.locationId.equals(locationId)))
        .go();

    await batch((b) {
      for (final item in items) {
        b.insert(
          cachedInventory,
          CachedInventoryCompanion.insert(
            productId: item['product_id'] as String,
            locationId: locationId,
            quantity: item['quantity'] as int,
            version: item['version'] as int,
            cachedAt: DateTime.now(),
          ),
        );
      }
    });
  }
}
