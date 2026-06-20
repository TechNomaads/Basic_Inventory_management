import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Cached product records synced from the backend API.
///
/// Used for offline-first barcode lookups during billing and inventory scans.
class CachedProducts extends Table {
  TextColumn get id => text()();
  TextColumn get barcode => text().unique()();
  TextColumn get name => text()();
  TextColumn get sku => text()();
  RealColumn get sellPrice => real()();
  RealColumn get costPrice => real().nullable()();
  RealColumn get taxRate => real().withDefault(const Constant(18.0))();
  TextColumn get categoryName => text().nullable()();
  TextColumn get unit => text().withDefault(const Constant('pcs'))();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached inventory snapshots per product per location.
///
/// Provides fast stock-level lookups without hitting the backend,
/// used by the billing scan handler to validate stock before adding to cart.
class CachedInventory extends Table {
  TextColumn get productId => text()();
  TextColumn get locationId => text()();
  IntColumn get quantity => integer()();
  IntColumn get version => integer()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {productId, locationId};
}

@DriftDatabase(tables: [CachedProducts, CachedInventory])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Named constructor for testing with an in-memory database.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'inventory_cache.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

/// Global Riverpod provider for the Drift database singleton.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});
