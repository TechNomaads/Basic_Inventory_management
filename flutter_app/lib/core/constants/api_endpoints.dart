/// Centralised API endpoint paths.
///
/// All backend URLs in one place — never hardcode paths in
/// repositories or data sources.
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiEndpoints {
  ApiEndpoints._();

  /// Base URL — auto-detects Android emulator vs web/desktop
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:8000';
    }
    // Android emulator routes to host machine via 10.0.2.2
    return 'http://10.0.2.2:8000';
  }

  /// WebSocket URL for Socket.IO
  static String get wsUrl => baseUrl;

  // ── Auth ───────────────────────────────────────────────────────
  static const String login = '/api/v1/auth/login';
  static const String refresh = '/api/v1/auth/refresh';
  static const String logout = '/api/v1/auth/logout';

  // ── Products ───────────────────────────────────────────────────
  static const String products = '/api/v1/products';
  static String productByBarcode(String barcode) => '/api/v1/products/$barcode';
  static String productById(String id) => '/api/v1/products/$id';

  // ── Inventory ──────────────────────────────────────────────────
  static String inventoryByLocation(String locationId) =>
      '/api/v1/inventory/$locationId';
  static const String transaction = '/api/v1/inventory/transaction';
  static const String adjustment = '/api/v1/inventory/adjustment';

  // ── Pending ────────────────────────────────────────────────────
  static const String pending = '/api/v1/pending';
  static String approveAdjustment(String id) => '/api/v1/pending/$id/approve';
  static String rejectAdjustment(String id) => '/api/v1/pending/$id/reject';

  // ── Reports ────────────────────────────────────────────────────
  static const String reportsSummary = '/api/v1/reports/summary';
  static const String reportsTransactions = '/api/v1/reports/transactions';

  // ── Users ──────────────────────────────────────────────────────
  static const String users = '/api/v1/users';
  static String userRole(String id) => '/api/v1/users/$id/role';
  static String userLocations(String id) => '/api/v1/users/$id/locations';
  static String deleteUser(String id) => '/api/v1/users/$id';

  // ── Audit ──────────────────────────────────────────────────────
  static const String audit = '/api/v1/audit';
}
