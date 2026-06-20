import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/features/billing/domain/cart_item.dart';
import 'package:inventory_app/features/billing/domain/cart_state.dart';

void main() {
  group('CartItem Unit Tests', () {
    test('line totals and tax calculations', () {
      const item = CartItem(
        productId: 'prod-123',
        name: 'Test Product',
        barcode: '12345678',
        sellPrice: 100.0,
        sku: 'TEST-SKU',
        quantity: 2,
        stockQuantity: 10,
        knownVersion: 1,
        taxRate: 18.0,
      );

      expect(item.subtotal, 200.0);
      expect(item.taxAmount, 36.0); // 18% of 200
      expect(item.lineTotal, 236.0);
    });

    test('copyWith updates fields correctly', () {
      const item = CartItem(
        productId: 'prod-123',
        name: 'Test Product',
        barcode: '12345678',
        sellPrice: 100.0,
        sku: 'TEST-SKU',
        quantity: 2,
        stockQuantity: 10,
        knownVersion: 1,
      );

      final updated = item.copyWith(quantity: 5, knownVersion: 2);
      expect(updated.quantity, 5);
      expect(updated.knownVersion, 2);
      expect(updated.sellPrice, 100.0);
    });
  });

  group('CartState Unit Tests', () {
    test('running totals calculations with discount', () {
      const item1 = CartItem(
        productId: 'prod-1',
        name: 'Item 1',
        barcode: '111',
        sellPrice: 100.0,
        sku: 'SKU-1',
        quantity: 2,
        stockQuantity: 10,
        knownVersion: 1,
        taxRate: 10.0, // Subtotal: 200, Tax: 20, Total: 220
      );

      const item2 = CartItem(
        productId: 'prod-2',
        name: 'Item 2',
        barcode: '222',
        sellPrice: 50.0,
        sku: 'SKU-2',
        quantity: 1,
        stockQuantity: 5,
        knownVersion: 1,
        taxRate: 20.0, // Subtotal: 50, Tax: 10, Total: 60
      );

      final state = const CartState(items: [item1, item2], discountAmount: 15.0);

      expect(state.subtotal, 250.0);
      expect(state.taxAmount, 30.0);
      expect(state.totalAmount, 265.0); // 250 + 30 - 15 = 265
    });

    test('total amount is never negative', () {
      const item = CartItem(
        productId: 'prod-1',
        name: 'Item 1',
        barcode: '111',
        sellPrice: 10.0,
        sku: 'SKU-1',
        quantity: 1,
        stockQuantity: 5,
        knownVersion: 1,
        taxRate: 10.0, // Subtotal: 10, Tax: 1, Total: 11
      );

      final state = const CartState(items: [item], discountAmount: 50.0); // Discount exceeds total
      expect(state.totalAmount, 0.0);
    });
  });
}
