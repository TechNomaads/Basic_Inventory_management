import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../data/billing_repository.dart';
import 'cart_item.dart';
import 'cart_state.dart';
import '../../../core/storage/cache_sync_service.dart';

/// Provider for the store locations metadata list
final locationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(billingRepositoryProvider);
  return repo.fetchLocations();
});

/// Provider for the currently selected store location ID
final selectedLocationProvider = StateProvider<String?>((ref) {
  // Can be set manually by the user
  return null;
});

/// Cached inventory map provider: product_id -> { 'quantity': int, 'version': int }
/// Storing local inventory snapshot for the selected location to enable fast version lookups.
final locationInventoryProvider = StateNotifierProvider<LocationInventoryNotifier, Map<String, Map<String, dynamic>>>((ref) {
  return LocationInventoryNotifier(ref);
});

class LocationInventoryNotifier extends StateNotifier<Map<String, Map<String, dynamic>>> {
  final Ref _ref;
  LocationInventoryNotifier(this._ref) : super({});

  Future<void> refreshInventory(String locationId) async {
    try {
      final repo = _ref.read(billingRepositoryProvider);
      final list = await repo.fetchInventoryByLocation(locationId);
      final Map<String, Map<String, dynamic>> map = {};
      for (final item in list) {
        final productId = item['product_id'] as String;
        map[productId] = {
          'quantity': item['quantity'] as int,
          'version': item['version'] as int,
        };
      }
      state = map;
    } catch (_) {
      // Keep existing state or clear
    }
  }

  void updateProductStock(String productId, int quantityChange, int newVersion) {
    if (state.containsKey(productId)) {
      final current = state[productId]!;
      final newQuantity = (current['quantity'] as int) + quantityChange;
      state = {
        ...state,
        productId: {
          'quantity': newQuantity,
          'version': newVersion,
        }
      };
    }
  }
}

/// Provider for daily sales summary metrics
final dailySummaryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(billingRepositoryProvider);
  final locationId = ref.watch(selectedLocationProvider);
  return repo.fetchDailySummary(locationId: locationId);
});

/// Main cart notifier provider
final cartProvider = StateNotifierProvider<BillingNotifier, CartState>((ref) {
  return BillingNotifier(ref);
});

class BillingNotifier extends StateNotifier<CartState> {
  final Ref _ref;

  BillingNotifier(this._ref) : super(const CartState());

  /// Scan a barcode and add it to the cart
  Future<bool> scanAndAddProduct(String barcode) async {
    final locationId = _ref.read(selectedLocationProvider);
    if (locationId == null) {
      state = state.copyWith(errorMessage: 'Please select a store location first');
      return false;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final repo = _ref.read(billingRepositoryProvider);
      
      // 1. Fetch product master details
      final product = await repo.fetchProductByBarcode(barcode);
      final productId = product['id'] as String;

      // 2. Fetch inventory cache. If empty, try to refresh it
      var inventoryMap = _ref.read(locationInventoryProvider);
      if (inventoryMap.isEmpty) {
        await _ref.read(locationInventoryProvider.notifier).refreshInventory(locationId);
        inventoryMap = _ref.read(locationInventoryProvider);
      }

      // 3. Match product to inventory at this location
      final inv = inventoryMap[productId];
      if (inv == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: "Product '${product['name']}' has no inventory record at this location.",
        );
        return false;
      }

      final int stockQty = inv['quantity'] as int;
      final int version = inv['version'] as int;

      if (stockQty <= 0) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: "Product '${product['name']}' is out of stock at this location.",
        );
        return false;
      }

      // Check if item already exists in cart
      final existingIndex = state.items.indexWhere((item) => item.productId == productId);
      if (existingIndex >= 0) {
        final existingItem = state.items[existingIndex];
        if (existingItem.quantity >= stockQty) {
          state = state.copyWith(
            isLoading: false,
            errorMessage: "Cannot add more. Only $stockQty items available in stock.",
          );
          return false;
        }

        final updatedItems = List<CartItem>.from(state.items);
        updatedItems[existingIndex] = existingItem.copyWith(
          quantity: existingItem.quantity + 1,
        );
        state = state.copyWith(items: updatedItems, isLoading: false);
      } else {
        // Add new item
        final newItem = CartItem(
          productId: productId,
          name: product['name'] as String,
          barcode: barcode,
          sellPrice: (product['sell_price'] as num).toDouble(),
          sku: product['sku'] as String,
          quantity: 1,
          stockQuantity: stockQty,
          knownVersion: version,
          taxRate: (product['tax_rate'] as num?)?.toDouble() ?? 18.0,
        );
        state = state.copyWith(
          items: [...state.items, newItem],
          isLoading: false,
        );
      }
      return true;
    } on DioException catch (e) {
      final msg = e.response?.data?['detail']?.toString() ?? 'Failed to load scanned product.';
      state = state.copyWith(isLoading: false, errorMessage: msg);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  /// Manually update the quantity of an item in the cart
  void updateQuantity(String productId, int newQty) {
    if (newQty <= 0) {
      removeProduct(productId);
      return;
    }

    final index = state.items.indexWhere((item) => item.productId == productId);
    if (index >= 0) {
      final item = state.items[index];
      if (newQty > item.stockQuantity) {
        state = state.copyWith(
          errorMessage: "Cannot set quantity to $newQty. Only ${item.stockQuantity} items in stock.",
        );
        return;
      }

      final updatedItems = List<CartItem>.from(state.items);
      updatedItems[index] = item.copyWith(quantity: newQty);
      state = state.copyWith(items: updatedItems, errorMessage: null);
    }
  }

  /// Remove an item from the cart
  void removeProduct(String productId) {
    state = state.copyWith(
      items: state.items.where((item) => item.productId != productId).toList(),
      errorMessage: null,
    );
  }

  /// Apply customer info (auto lookup is handled in the UI sheet)
  void setCustomerInfo(String name, String phone) {
    state = state.copyWith(
      customerName: name,
      customerPhone: phone,
      customerCreditLimit: 10000.0,
      customerOverdue: 0.0,
      clearAmountPaid: true,
    );
  }

  /// Set amount paid
  void setAmountPaid(double? amount) {
    state = state.copyWith(amountPaid: amount, clearAmountPaid: amount == null);
  }

  /// Set payment method (cash, card, upi)
  void setPaymentMode(String mode) {
    state = state.copyWith(paymentMode: mode);
  }

  /// Set discount amount
  void setDiscount(double discount) {
    state = state.copyWith(discountAmount: discount);
  }

  /// Set notes
  void setNotes(String notes) {
    state = state.copyWith(notes: notes);
  }

  /// Clear the cart state completely
  void clearCart() {
    state = const CartState();
  }

  /// Add a pre-resolved [CartItem] to the cart directly.
  ///
  /// Used by [BillingScanHandler] which has already resolved
  /// the product data from the local Drift cache.
  void addCartItem(CartItem item) {
    state = state.copyWith(
      items: [...state.items, item],
      isLoading: false,
      errorMessage: null,
    );
  }

  /// Add a product directly from a manual search/selection
  Future<bool> addProductDirectly(String productId) async {
    final locationId = _ref.read(selectedLocationProvider);
    if (locationId == null) {
      state = state.copyWith(errorMessage: 'Please select a store location first');
      return false;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      // 1. Get product from local cache
      final dao = _ref.read(productCacheDaoProvider);
      final product = await dao.getById(productId);
      if (product == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: "Product not found in local cache.",
        );
        return false;
      }

      // 2. Fetch inventory cache. If empty, try to refresh it
      var inventoryMap = _ref.read(locationInventoryProvider);
      if (inventoryMap.isEmpty) {
        await _ref.read(locationInventoryProvider.notifier).refreshInventory(locationId);
        inventoryMap = _ref.read(locationInventoryProvider);
      }

      // 3. Match product to inventory at this location
      final inv = inventoryMap[productId];
      if (inv == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: "Product '${product.name}' has no inventory record at this location.",
        );
        return false;
      }

      final int stockQty = inv['quantity'] as int;
      final int version = inv['version'] as int;

      if (stockQty <= 0) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: "Product '${product.name}' is out of stock at this location.",
        );
        return false;
      }

      // Check if item already exists in cart
      final existingIndex = state.items.indexWhere((item) => item.productId == productId);
      if (existingIndex >= 0) {
        final existingItem = state.items[existingIndex];
        if (existingItem.quantity >= stockQty) {
          state = state.copyWith(
            isLoading: false,
            errorMessage: "Cannot add more. Only $stockQty items available in stock.",
          );
          return false;
        }

        final updatedItems = List<CartItem>.from(state.items);
        updatedItems[existingIndex] = existingItem.copyWith(
          quantity: existingItem.quantity + 1,
        );
        state = state.copyWith(items: updatedItems, isLoading: false);
      } else {
        // Add new item
        final newItem = CartItem(
          productId: productId,
          name: product.name,
          barcode: product.barcode,
          sellPrice: product.sellPrice,
          sku: product.sku,
          quantity: 1,
          stockQuantity: stockQty,
          knownVersion: version,
          taxRate: product.taxRate,
        );
        state = state.copyWith(
          items: [...state.items, newItem],
          isLoading: false,
        );
      }
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  /// Lookup customer by phone number
  Future<bool> lookupCustomerPhone(String phone) async {
    if (phone.length < 10) return false;
    try {
      final repo = _ref.read(billingRepositoryProvider);
      final customer = await repo.lookupCustomer(phone);
      if (customer != null) {
        state = state.copyWith(
          customerName: customer['name'] as String,
          customerPhone: phone,
          customerCreditLimit: (customer['credit_limit'] as num?)?.toDouble() ?? 10000.0,
          customerOverdue: (customer['overdue_amount'] as num?)?.toDouble() ?? 0.0,
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Process the checkout cart transaction
  Future<bool> processCheckout() async {
    final locationId = _ref.read(selectedLocationProvider);
    if (locationId == null) {
      state = state.copyWith(errorMessage: 'Please select a store location first.');
      return false;
    }

    if (state.items.isEmpty) {
      state = state.copyWith(errorMessage: 'Cart is empty.');
      return false;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final repo = _ref.read(billingRepositoryProvider);
      
      // Build request body
      final requestData = {
        'location_id': locationId,
        'payment_mode': state.paymentMode.toLowerCase(),
        'discount_amount': state.discountAmount,
        'amount_paid': state.amountPaid ?? state.totalAmount,
        'notes': state.notes.isEmpty ? null : state.notes,
        'customer_name': state.customerName.isEmpty ? null : state.customerName,
        'customer_phone': state.customerPhone.isEmpty ? null : state.customerPhone,
        'items': state.items.map((item) => item.toJson()).toList(),
      };

      final invoice = await repo.checkout(requestData);

      // On success, update our local inventory cache so we have updated quantities and versions!
      final invNotifier = _ref.read(locationInventoryProvider.notifier);
      for (final item in state.items) {
        // The backend increments the inventory version by 1 on deduction
        invNotifier.updateProductStock(item.productId, -item.quantity, item.knownVersion + 1);
      }

      // Refresh daily sales summary
      _ref.invalidate(dailySummaryProvider);

      state = state.copyWith(
        isLoading: false,
        invoice: invoice,
      );
      return true;
    } on DioException catch (e) {
      final msg = e.response?.data?['detail']?.toString() ?? 'Checkout failed. Please try again.';
      state = state.copyWith(isLoading: false, errorMessage: msg);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }
}
