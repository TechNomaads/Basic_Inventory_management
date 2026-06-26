import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_endpoints.dart';

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return ProductRepository(dio);
});

class ProductRepository {
  final Dio _dio;

  ProductRepository(this._dio);

  /// Fetch paginated list of products
  Future<Map<String, dynamic>> fetchProducts({
    String? search,
    String? categoryId,
    int page = 1,
    int size = 20,
  }) async {
    final response = await _dio.get(
      ApiEndpoints.products,
      queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
        if (categoryId != null && categoryId.isNotEmpty) 'category_id': categoryId,
        'page': page,
        'size': size,
      },
    );

    final data = response.data as Map<String, dynamic>;
    final list = data['items'] as List<dynamic>;
    
    return {
      'items': list,
      'total': data['total'] as int,
      'page': data['page'] as int,
      'size': data['size'] as int,
      'pages': data['pages'] as int,
    };
  }

  /// Fetch details of a single product by ID
  Future<Map<String, dynamic>> fetchProductById(String id) async {
    final response = await _dio.get(ApiEndpoints.productById(id));
    return response.data as Map<String, dynamic>;
  }

  /// Fetch details of a single product by barcode
  Future<Map<String, dynamic>> fetchProductByBarcode(String barcode) async {
    final response = await _dio.get(ApiEndpoints.productByBarcode(barcode));
    return response.data as Map<String, dynamic>;
  }

  /// Create a new product
  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> data) async {
    final response = await _dio.post(ApiEndpoints.products, data: data);
    return response.data as Map<String, dynamic>;
  }

  /// Update an existing product
  Future<Map<String, dynamic>> updateProduct(String id, Map<String, dynamic> data) async {
    final response = await _dio.put(ApiEndpoints.productById(id), data: data);
    return response.data as Map<String, dynamic>;
  }

  /// Delete a product (soft delete)
  Future<void> deleteProduct(String id) async {
    await _dio.delete(ApiEndpoints.productById(id));
  }

  /// Record a stock transaction (Stock In/Out or Adjustment)
  Future<Map<String, dynamic>> recordStockTransaction({
    required String productId,
    required String locationId,
    required String type, // receive | dispatch | adjustment | transfer_in | transfer_out | damage
    required int quantityChange,
    required int knownVersion,
    String? notes,
  }) async {
    final payload = {
      'product_id': productId,
      'location_id': locationId,
      'type': type,
      'quantity_change': quantityChange,
      'known_version': knownVersion,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    };
    final response = await _dio.post(ApiEndpoints.transaction, data: payload);
    return response.data as Map<String, dynamic>;
  }

  /// Submit a formal stock adjustment (subject to manager threshold approval)
  Future<Map<String, dynamic>> submitAdjustment({
    required String productId,
    required String locationId,
    required int quantityChange,
    required int knownVersion,
    String? notes,
  }) async {
    final payload = {
      'product_id': productId,
      'location_id': locationId,
      'quantity_change': quantityChange,
      'known_version': knownVersion,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    };
    final response = await _dio.post(ApiEndpoints.adjustment, data: payload);
    return response.data as Map<String, dynamic>;
  }
}
