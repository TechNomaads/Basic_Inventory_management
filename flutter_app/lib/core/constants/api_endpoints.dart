/// Centralised API endpoint paths.
///
/// All backend URLs in one place — never hardcode paths in
/// repositories or data sources.
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiEndpoints {
  ApiEndpoints._();

  static const String _envBaseUrl = String.fromEnvironment('API_URL', defaultValue: '');

  /// Base URL — auto-detects Android emulator vs web/desktop, supports compile-time override
  static String get baseUrl {
    if (_envBaseUrl.isNotEmpty) {
      return _envBaseUrl;
    }
    if (kIsWeb) {
      return 'http://localhost:8000';
    }
    // Physical mobile device connects to the host machine's IP address
    return 'http://192.168.0.120:8000';
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
  static const String reportsSalesTrend = '/api/v1/reports/sales-trend';
  static const String reportsCategoryStock = '/api/v1/reports/category-stock';

  // ── Users ──────────────────────────────────────────────────────
  static const String users = '/api/v1/users';
  static String userRole(String id) => '/api/v1/users/$id/role';
  static String userLocations(String id) => '/api/v1/users/$id/locations';
  static String deleteUser(String id) => '/api/v1/users/$id';

  // ── Audit ──────────────────────────────────────────────────────
  static const String audit = '/api/v1/audit';

  // ── Billing ────────────────────────────────────────────────────
  static const String checkout = '/api/v1/billing/checkout';
  static const String invoices = '/api/v1/billing/invoices';
  static String invoiceDetail(String id) => '/api/v1/billing/invoices/$id';
  static String thermalReceipt(String id) => '/api/v1/billing/invoices/$id/receipt';
  static String customerLookup(String phone) =>
      '/api/v1/billing/customers/lookup?phone=${Uri.encodeQueryComponent(phone)}';
  static const String dailySalesSummary = '/api/v1/billing/daily-summary';

  // ── Inventory Quick Adjust ─────────────────────────────────────
  static const String quickAdjust = '/api/v1/inventory/quick-adjust';

  // ── Inventory Metadata ─────────────────────────────────────────
  static const String locationsMeta = '/api/v1/inventory/meta/locations';
}

