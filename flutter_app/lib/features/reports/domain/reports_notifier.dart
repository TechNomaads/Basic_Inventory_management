import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../billing/domain/billing_notifier.dart';
import '../../billing/data/billing_repository.dart';
import '../data/reports_repository.dart';

/// Provider for Reports summary analytics
final reportsSummaryProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final locationId = ref.watch(selectedLocationProvider);
  return repo.fetchSummary(locationId: locationId);
});

/// Provider for daily sales trend data (revenue & profit)
final salesTrendProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final locationId = ref.watch(selectedLocationProvider);
  return repo.fetchSalesTrend(locationId: locationId);
});

/// Provider for category stock level breakdown
final categoryStockProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final locationId = ref.watch(selectedLocationProvider);
  return repo.fetchCategoryStock(locationId: locationId);
});

/// Provider for recent stock/sale transactions
final recentTransactionsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final data = await repo.fetchTransactions(page: 1, size: 15);
  final items = data['items'] as List<dynamic>? ?? [];
  return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

/// Provider for raw location inventory (used for low-stock lists)
final locationInventoryListProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  // Let's import billing repo provider
  final repo = ref.watch(reportsRepositoryProvider); // reports repo can fetch or we can use billing repo
  // Let's use the reports repository's parent/underlying HTTP client to fetch, or use billing repo
  // Let's import billingRepositoryProvider from billing features
  final billingRepo = ref.watch(billingRepositoryProvider);
  final locationId = ref.watch(selectedLocationProvider);
  if (locationId == null || locationId.isEmpty) return const [];
  return billingRepo.fetchInventoryByLocation(locationId);
});
