import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';
import '../domain/customer_model.dart';
import '../domain/customer_detail_model.dart';

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return CustomerRepository(dio);
});

class CustomerRepository {
  final Dio _dio;

  CustomerRepository(this._dio);

  /// Fetch paginated list of customers
  Future<Map<String, dynamic>> fetchCustomers({String? search, int page = 1, int size = 20}) async {
    final response = await _dio.get(
      '/api/v1/customers',
      queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
        'page': page,
        'size': size,
      },
    );
    final data = response.data as Map<String, dynamic>;
    final list = data['items'] as List<dynamic>;
    final items = list.map((e) => CustomerModel.fromJson(e as Map<String, dynamic>)).toList();
    
    return {
      'items': items,
      'total': data['total'] as int,
      'pages': data['pages'] as int,
    };
  }

  /// Fetch aggregated customers KPIs
  Future<Map<String, dynamic>> fetchCustomersKpis() async {
    final response = await _dio.get('/api/v1/customers/kpis');
    return response.data as Map<String, dynamic>;
  }

  /// Fetch detailed customer info and history
  Future<CustomerDetailModel> fetchCustomerDetail(String id) async {
    final response = await _dio.get('/api/v1/customers/$id');
    return CustomerDetailModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Create a new customer
  Future<CustomerModel> createCustomer(Map<String, dynamic> payload) async {
    final response = await _dio.post('/api/v1/customers', data: payload);
    return CustomerModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Update customer profile (credit limit, etc.)
  Future<CustomerModel> updateCustomer(String id, Map<String, dynamic> payload) async {
    final response = await _dio.put('/api/v1/customers/$id', data: payload);
    return CustomerModel.fromJson(response.data as Map<String, dynamic>);
  }
}
