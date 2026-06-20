// GENERATED CODE - DO NOT MODIFY BY HAND
// Run `dart run build_runner build` to regenerate.

part of 'app_database.dart';

class $CachedProductsTable extends CachedProducts
    with TableInfo<$CachedProductsTable, CachedProduct> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedProductsTable(this.attachedDatabase, [this._alias]);

  static const VerificationMeta _idMeta = VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true);

  static const VerificationMeta _barcodeMeta = VerificationMeta('barcode');
  @override
  late final GeneratedColumn<String> barcode = GeneratedColumn<String>(
    'barcode', aliasedName, false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));

  static const VerificationMeta _nameMeta = VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true);

  static const VerificationMeta _skuMeta = VerificationMeta('sku');
  @override
  late final GeneratedColumn<String> sku = GeneratedColumn<String>(
    'sku', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true);

  static const VerificationMeta _sellPriceMeta = VerificationMeta('sellPrice');
  @override
  late final GeneratedColumn<double> sellPrice = GeneratedColumn<double>(
    'sell_price', aliasedName, false,
    type: DriftSqlType.double, requiredDuringInsert: true);

  static const VerificationMeta _costPriceMeta = VerificationMeta('costPrice');
  @override
  late final GeneratedColumn<double> costPrice = GeneratedColumn<double>(
    'cost_price', aliasedName, true,
    type: DriftSqlType.double, requiredDuringInsert: false);

  static const VerificationMeta _taxRateMeta = VerificationMeta('taxRate');
  @override
  late final GeneratedColumn<double> taxRate = GeneratedColumn<double>(
    'tax_rate', aliasedName, false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(18.0));

  static const VerificationMeta _categoryNameMeta = VerificationMeta('categoryName');
  @override
  late final GeneratedColumn<String> categoryName = GeneratedColumn<String>(
    'category_name', aliasedName, true,
    type: DriftSqlType.string, requiredDuringInsert: false);

  static const VerificationMeta _unitMeta = VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit', aliasedName, false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pcs'));

  static const VerificationMeta _cachedAtMeta = VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at', aliasedName, false,
    type: DriftSqlType.dateTime, requiredDuringInsert: true);

  @override
  List<GeneratedColumn> get $columns =>
      [id, barcode, name, sku, sellPrice, costPrice, taxRate, categoryName, unit, cachedAt];

  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_products';

  @override
  VerificationContext validateIntegrity(Insertable<CachedProduct> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('barcode')) {
      context.handle(_barcodeMeta, barcode.isAcceptableOrUnknown(data['barcode']!, _barcodeMeta));
    } else if (isInserting) {
      context.missing(_barcodeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(_nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sku')) {
      context.handle(_skuMeta, sku.isAcceptableOrUnknown(data['sku']!, _skuMeta));
    } else if (isInserting) {
      context.missing(_skuMeta);
    }
    if (data.containsKey('sell_price')) {
      context.handle(_sellPriceMeta, sellPrice.isAcceptableOrUnknown(data['sell_price']!, _sellPriceMeta));
    } else if (isInserting) {
      context.missing(_sellPriceMeta);
    }
    if (data.containsKey('cost_price')) {
      context.handle(_costPriceMeta, costPrice.isAcceptableOrUnknown(data['cost_price']!, _costPriceMeta));
    }
    if (data.containsKey('tax_rate')) {
      context.handle(_taxRateMeta, taxRate.isAcceptableOrUnknown(data['tax_rate']!, _taxRateMeta));
    }
    if (data.containsKey('category_name')) {
      context.handle(_categoryNameMeta, categoryName.isAcceptableOrUnknown(data['category_name']!, _categoryNameMeta));
    }
    if (data.containsKey('unit')) {
      context.handle(_unitMeta, unit.isAcceptableOrUnknown(data['unit']!, _unitMeta));
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta, cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedProduct map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedProduct(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      barcode: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}barcode'])!,
      name: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      sku: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}sku'])!,
      sellPrice: attachedDatabase.typeMapping.read(DriftSqlType.double, data['${effectivePrefix}sell_price'])!,
      costPrice: attachedDatabase.typeMapping.read(DriftSqlType.double, data['${effectivePrefix}cost_price']),
      taxRate: attachedDatabase.typeMapping.read(DriftSqlType.double, data['${effectivePrefix}tax_rate'])!,
      categoryName: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}category_name']),
      unit: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}unit'])!,
      cachedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $CachedProductsTable createAlias(String alias) {
    return $CachedProductsTable(attachedDatabase, alias);
  }
}

class CachedProduct extends DataClass implements Insertable<CachedProduct> {
  final String id;
  final String barcode;
  final String name;
  final String sku;
  final double sellPrice;
  final double? costPrice;
  final double taxRate;
  final String? categoryName;
  final String unit;
  final DateTime cachedAt;

  const CachedProduct({
    required this.id,
    required this.barcode,
    required this.name,
    required this.sku,
    required this.sellPrice,
    this.costPrice,
    required this.taxRate,
    this.categoryName,
    required this.unit,
    required this.cachedAt,
  });

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['barcode'] = Variable<String>(barcode);
    map['name'] = Variable<String>(name);
    map['sku'] = Variable<String>(sku);
    map['sell_price'] = Variable<double>(sellPrice);
    if (!nullToAbsent || costPrice != null) {
      map['cost_price'] = Variable<double>(costPrice);
    }
    map['tax_rate'] = Variable<double>(taxRate);
    if (!nullToAbsent || categoryName != null) {
      map['category_name'] = Variable<String>(categoryName);
    }
    map['unit'] = Variable<String>(unit);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedProductsCompanion toCompanion(bool nullToAbsent) {
    return CachedProductsCompanion(
      id: Value(id),
      barcode: Value(barcode),
      name: Value(name),
      sku: Value(sku),
      sellPrice: Value(sellPrice),
      costPrice: costPrice == null && nullToAbsent ? const Value.absent() : Value(costPrice),
      taxRate: Value(taxRate),
      categoryName: categoryName == null && nullToAbsent ? const Value.absent() : Value(categoryName),
      unit: Value(unit),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedProduct.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedProduct(
      id: serializer.fromJson<String>(json['id']),
      barcode: serializer.fromJson<String>(json['barcode']),
      name: serializer.fromJson<String>(json['name']),
      sku: serializer.fromJson<String>(json['sku']),
      sellPrice: serializer.fromJson<double>(json['sellPrice']),
      costPrice: serializer.fromJson<double?>(json['costPrice']),
      taxRate: serializer.fromJson<double>(json['taxRate']),
      categoryName: serializer.fromJson<String?>(json['categoryName']),
      unit: serializer.fromJson<String>(json['unit']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }

  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'barcode': serializer.toJson<String>(barcode),
      'name': serializer.toJson<String>(name),
      'sku': serializer.toJson<String>(sku),
      'sellPrice': serializer.toJson<double>(sellPrice),
      'costPrice': serializer.toJson<double?>(costPrice),
      'taxRate': serializer.toJson<double>(taxRate),
      'categoryName': serializer.toJson<String?>(categoryName),
      'unit': serializer.toJson<String>(unit),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedProduct copyWith({
    String? id, String? barcode, String? name, String? sku,
    double? sellPrice, Value<double?> costPrice = const Value.absent(),
    double? taxRate, Value<String?> categoryName = const Value.absent(),
    String? unit, DateTime? cachedAt,
  }) => CachedProduct(
    id: id ?? this.id, barcode: barcode ?? this.barcode,
    name: name ?? this.name, sku: sku ?? this.sku,
    sellPrice: sellPrice ?? this.sellPrice,
    costPrice: costPrice.present ? costPrice.value : this.costPrice,
    taxRate: taxRate ?? this.taxRate,
    categoryName: categoryName.present ? categoryName.value : this.categoryName,
    unit: unit ?? this.unit, cachedAt: cachedAt ?? this.cachedAt,
  );

  @override
  String toString() => 'CachedProduct(id: $id, barcode: $barcode, name: $name)';

  @override
  int get hashCode => Object.hash(id, barcode, name, sku, sellPrice, costPrice, taxRate, categoryName, unit, cachedAt);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is CachedProduct && other.id == id);
}

class CachedProductsCompanion extends UpdateCompanion<CachedProduct> {
  final Value<String> id;
  final Value<String> barcode;
  final Value<String> name;
  final Value<String> sku;
  final Value<double> sellPrice;
  final Value<double?> costPrice;
  final Value<double> taxRate;
  final Value<String?> categoryName;
  final Value<String> unit;
  final Value<DateTime> cachedAt;

  const CachedProductsCompanion({
    this.id = const Value.absent(),
    this.barcode = const Value.absent(),
    this.name = const Value.absent(),
    this.sku = const Value.absent(),
    this.sellPrice = const Value.absent(),
    this.costPrice = const Value.absent(),
    this.taxRate = const Value.absent(),
    this.categoryName = const Value.absent(),
    this.unit = const Value.absent(),
    this.cachedAt = const Value.absent(),
  });

  CachedProductsCompanion.insert({
    required String id,
    required String barcode,
    required String name,
    required String sku,
    required double sellPrice,
    this.costPrice = const Value.absent(),
    this.taxRate = const Value.absent(),
    this.categoryName = const Value.absent(),
    this.unit = const Value.absent(),
    required DateTime cachedAt,
  })  : id = Value(id),
        barcode = Value(barcode),
        name = Value(name),
        sku = Value(sku),
        sellPrice = Value(sellPrice),
        cachedAt = Value(cachedAt);

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) map['id'] = Variable<String>(id.value);
    if (barcode.present) map['barcode'] = Variable<String>(barcode.value);
    if (name.present) map['name'] = Variable<String>(name.value);
    if (sku.present) map['sku'] = Variable<String>(sku.value);
    if (sellPrice.present) map['sell_price'] = Variable<double>(sellPrice.value);
    if (costPrice.present) map['cost_price'] = Variable<double>(costPrice.value);
    if (taxRate.present) map['tax_rate'] = Variable<double>(taxRate.value);
    if (categoryName.present) map['category_name'] = Variable<String>(categoryName.value);
    if (unit.present) map['unit'] = Variable<String>(unit.value);
    if (cachedAt.present) map['cached_at'] = Variable<DateTime>(cachedAt.value);
    return map;
  }

  @override
  String toString() => 'CachedProductsCompanion(id: $id, barcode: $barcode, name: $name)';
}

// ── CachedInventory table ──────────────────────────────────────────

class $CachedInventoryTable extends CachedInventory
    with TableInfo<$CachedInventoryTable, CachedInventoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedInventoryTable(this.attachedDatabase, [this._alias]);

  static const VerificationMeta _productIdMeta = VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true);

  static const VerificationMeta _locationIdMeta = VerificationMeta('locationId');
  @override
  late final GeneratedColumn<String> locationId = GeneratedColumn<String>(
    'location_id', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true);

  static const VerificationMeta _quantityMeta = VerificationMeta('quantity');
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
    'quantity', aliasedName, false,
    type: DriftSqlType.int, requiredDuringInsert: true);

  static const VerificationMeta _versionMeta = VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version', aliasedName, false,
    type: DriftSqlType.int, requiredDuringInsert: true);

  static const VerificationMeta _cachedAtMeta = VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at', aliasedName, false,
    type: DriftSqlType.dateTime, requiredDuringInsert: true);

  @override
  List<GeneratedColumn> get $columns => [productId, locationId, quantity, version, cachedAt];

  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_inventory';

  @override
  VerificationContext validateIntegrity(Insertable<CachedInventoryData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta, productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('location_id')) {
      context.handle(_locationIdMeta, locationId.isAcceptableOrUnknown(data['location_id']!, _locationIdMeta));
    } else if (isInserting) {
      context.missing(_locationIdMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(_quantityMeta, quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta));
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta, version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta, cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {productId, locationId};
  @override
  CachedInventoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedInventoryData(
      productId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      locationId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}location_id'])!,
      quantity: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}quantity'])!,
      version: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      cachedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $CachedInventoryTable createAlias(String alias) {
    return $CachedInventoryTable(attachedDatabase, alias);
  }
}

class CachedInventoryData extends DataClass implements Insertable<CachedInventoryData> {
  final String productId;
  final String locationId;
  final int quantity;
  final int version;
  final DateTime cachedAt;

  const CachedInventoryData({
    required this.productId,
    required this.locationId,
    required this.quantity,
    required this.version,
    required this.cachedAt,
  });

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['product_id'] = Variable<String>(productId);
    map['location_id'] = Variable<String>(locationId);
    map['quantity'] = Variable<int>(quantity);
    map['version'] = Variable<int>(version);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedInventoryCompanion toCompanion(bool nullToAbsent) {
    return CachedInventoryCompanion(
      productId: Value(productId),
      locationId: Value(locationId),
      quantity: Value(quantity),
      version: Value(version),
      cachedAt: Value(cachedAt),
    );
  }

  CachedInventoryData copyWith({
    String? productId, String? locationId, int? quantity, int? version, DateTime? cachedAt,
  }) => CachedInventoryData(
    productId: productId ?? this.productId,
    locationId: locationId ?? this.locationId,
    quantity: quantity ?? this.quantity,
    version: version ?? this.version,
    cachedAt: cachedAt ?? this.cachedAt,
  );

  @override
  String toString() => 'CachedInventoryData(productId: $productId, locationId: $locationId, quantity: $quantity)';

  @override
  int get hashCode => Object.hash(productId, locationId, quantity, version, cachedAt);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is CachedInventoryData && other.productId == productId && other.locationId == locationId);
}

class CachedInventoryCompanion extends UpdateCompanion<CachedInventoryData> {
  final Value<String> productId;
  final Value<String> locationId;
  final Value<int> quantity;
  final Value<int> version;
  final Value<DateTime> cachedAt;

  const CachedInventoryCompanion({
    this.productId = const Value.absent(),
    this.locationId = const Value.absent(),
    this.quantity = const Value.absent(),
    this.version = const Value.absent(),
    this.cachedAt = const Value.absent(),
  });

  CachedInventoryCompanion.insert({
    required String productId,
    required String locationId,
    required int quantity,
    required int version,
    required DateTime cachedAt,
  })  : productId = Value(productId),
        locationId = Value(locationId),
        quantity = Value(quantity),
        version = Value(version),
        cachedAt = Value(cachedAt);

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (productId.present) map['product_id'] = Variable<String>(productId.value);
    if (locationId.present) map['location_id'] = Variable<String>(locationId.value);
    if (quantity.present) map['quantity'] = Variable<int>(quantity.value);
    if (version.present) map['version'] = Variable<int>(version.value);
    if (cachedAt.present) map['cached_at'] = Variable<DateTime>(cachedAt.value);
    return map;
  }

  @override
  String toString() => 'CachedInventoryCompanion(productId: $productId, locationId: $locationId)';
}

// ── Database class ─────────────────────────────────────────────────

class _$AppDatabase extends AppDatabase {
  _$AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  late final $CachedProductsTable cachedProducts = $CachedProductsTable(this);
  late final $CachedInventoryTable cachedInventory = $CachedInventoryTable(this);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [cachedProducts, cachedInventory];
}
