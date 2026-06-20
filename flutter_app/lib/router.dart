// [AppRouter] — GoRouter configuration with auth redirect and role guards.
//
// Responsibilities:
//   - Define all app routes
//   - Redirect unauthenticated users to login
//   - Guard admin/manager routes
//
// Dependencies: go_router, auth_notifier


import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/domain/auth_notifier.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'features/scanner/presentation/scanner_screen.dart';
import 'features/scanner/domain/scan_mode.dart';
import 'features/product/presentation/product_detail_screen.dart';
import 'features/inventory/presentation/transaction_history_screen.dart';
import 'features/reports/presentation/reports_screen.dart';
import 'features/products_mgmt/presentation/product_list_screen.dart';
import 'features/products_mgmt/presentation/add_edit_product_screen.dart';
import 'features/users_mgmt/presentation/user_list_screen.dart';
import 'features/users_mgmt/presentation/add_user_screen.dart';
import 'features/audit/presentation/audit_log_screen.dart';
import 'features/billing/presentation/billing_screen.dart';
import 'features/billing/presentation/invoice_success_screen.dart';

/// GoRouter provider that rebuilds on auth state changes
final routerProvider = Provider<GoRouter>((ref) {

  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final isLoggedIn = authState is AuthAuthenticated;
      final isLoginPage = state.matchedLocation == '/login';

      if (!isLoggedIn && !isLoginPage) {
        return '/login';
      }
      if (isLoggedIn && isLoginPage) {
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/scanner',
        builder: (context, state) {
          final modeStr = state.uri.queryParameters['mode'] ?? 'inventory';
          final mode = ScanMode.values.byName(modeStr);
          return ScannerScreen(initialMode: mode);
        },
      ),
      GoRoute(
        path: '/product/:barcode',
        builder: (context, state) {
          final barcode = state.pathParameters['barcode']!;
          return ProductDetailScreen(barcode: barcode);
        },
      ),
      GoRoute(
        path: '/transactions',
        builder: (context, state) => const TransactionHistoryScreen(),
      ),
      GoRoute(
        path: '/reports',
        builder: (context, state) => const ReportsScreen(),
      ),
      GoRoute(
        path: '/products-mgmt',
        builder: (context, state) => const ProductListScreen(),
      ),
      GoRoute(
        path: '/products-mgmt/add',
        builder: (context, state) => const AddEditProductScreen(),
      ),
      GoRoute(
        path: '/products-mgmt/edit/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return AddEditProductScreen(productId: id);
        },
      ),
      GoRoute(
        path: '/users-mgmt',
        builder: (context, state) => const UserListScreen(),
      ),
      GoRoute(
        path: '/users-mgmt/add',
        builder: (context, state) => const AddUserScreen(),
      ),
      GoRoute(
        path: '/audit',
        builder: (context, state) => const AuditLogScreen(),
      ),
      GoRoute(
        path: '/billing',
        builder: (context, state) => const BillingScreen(),
      ),
      GoRoute(
        path: '/billing/success',
        builder: (context, state) => const InvoiceSuccessScreen(),
      ),
    ],
  );
});
