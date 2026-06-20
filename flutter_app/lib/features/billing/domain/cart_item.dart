class CartItem {
  final String productId;
  final String name;
  final String barcode;
  final double sellPrice;
  final String sku;
  final int quantity;
  final int stockQuantity;
  final int knownVersion;
  final double taxRate;

  const CartItem({
    required this.productId,
    required this.name,
    required this.barcode,
    required this.sellPrice,
    required this.sku,
    required this.quantity,
    required this.stockQuantity,
    required this.knownVersion,
    this.taxRate = 18.0,
  });

  double get subtotal => sellPrice * quantity;
  double get taxAmount => subtotal * (taxRate / 100.0);
  double get lineTotal => subtotal + taxAmount;

  CartItem copyWith({
    String? productId,
    String? name,
    String? barcode,
    double? sellPrice,
    String? sku,
    int? quantity,
    int? stockQuantity,
    int? knownVersion,
    double? taxRate,
  }) {
    return CartItem(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      sellPrice: sellPrice ?? this.sellPrice,
      sku: sku ?? this.sku,
      quantity: quantity ?? this.quantity,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      knownVersion: knownVersion ?? this.knownVersion,
      taxRate: taxRate ?? this.taxRate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'quantity': quantity,
      'known_version': knownVersion,
    };
  }
}
