/// [DashboardScreen] — Main staff dashboard with summary cards and activity.
///
/// Responsibilities:
///   - Summary metric cards (total products, low stock, today's scans, pending)
///   - Low stock alerts list
///   - Recent activity feed
///   - Bottom navigation for scanner, dashboard, reports, menu
///
/// Dependencies: Riverpod, go_router, AppColors

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../auth/domain/auth_notifier.dart';
import '../../billing/domain/billing_notifier.dart';
import '../../reports/domain/reports_notifier.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final userName = authState is AuthAuthenticated
        ? authState.user.name
        : 'User';
    final isAdmin = authState is AuthAuthenticated && authState.user.canManage;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hello, $userName',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              AppStrings.dashboardTitle,
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: AppColors.cardBg,
            onSelected: (value) {
              if (value == 'logout') {
                ref.read(authNotifierProvider.notifier).logout();
              } else if (value == 'products') {
                context.push('/products-mgmt');
              } else if (value == 'users') {
                context.push('/users-mgmt');
              } else if (value == 'customers') {
                context.push('/customers');
              } else if (value == 'sales') {
                context.push('/sales-history');
              } else if (value == 'pending') {
                context.push('/pending-approvals');
              } else if (value == 'audit') {
                context.push('/audit');
              }
            },
            itemBuilder: (context) => [
              if (isAdmin) ...[
                const PopupMenuItem(
                  value: 'products',
                  child: ListTile(
                    leading: Icon(Icons.inventory, color: AppColors.textSecondary),
                    title: Text(AppStrings.productsManagement),
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'users',
                  child: ListTile(
                    leading: Icon(Icons.people, color: AppColors.textSecondary),
                    title: Text(AppStrings.usersManagement),
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'customers',
                  child: ListTile(
                    leading: Icon(Icons.people_outline_rounded, color: AppColors.textSecondary),
                    title: Text('Customers Directory'),
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'sales',
                  child: ListTile(
                    leading: Icon(Icons.receipt_long_rounded, color: AppColors.textSecondary),
                    title: Text('Sales History'),
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'pending',
                  child: ListTile(
                    leading: Icon(Icons.pending_actions_rounded, color: AppColors.textSecondary),
                    title: Text('Pending Approvals'),
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'audit',
                  child: ListTile(
                    leading: Icon(Icons.history, color: AppColors.textSecondary),
                    title: Text(AppStrings.auditLog),
                    dense: true,
                  ),
                ),
              ] else ...[
                const PopupMenuItem(
                  value: 'customers',
                  child: ListTile(
                    leading: Icon(Icons.people_outline_rounded, color: AppColors.textSecondary),
                    title: Text('Customers Directory'),
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'sales',
                  child: ListTile(
                    leading: Icon(Icons.receipt_long_rounded, color: AppColors.textSecondary),
                    title: Text('Sales History'),
                    dense: true,
                  ),
                ),
              ],
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout, color: AppColors.error),
                  title: Text(AppStrings.logoutButton),
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.cardBg,
        onRefresh: () async {
          ref.invalidate(dailySummaryProvider);
          ref.invalidate(reportsSummaryProvider);
          ref.invalidate(salesTrendProvider);
          ref.invalidate(categoryStockProvider);
          ref.invalidate(recentTransactionsProvider);
          ref.invalidate(locationInventoryListProvider);
          try {
            await ref.read(reportsSummaryProvider.future);
          } catch (_) {}
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Metric cards ────────────────────────────────────
            ref.watch(reportsSummaryProvider).when(
              data: (summary) {
                final totalProducts = summary['total_products'] ?? 0;
                final lowStock = summary['low_stock_count'] ?? 0;
                final todaysScans = summary['todays_scans'] ?? 0;
                final pending = summary['pending_adjustments'] ?? 0;
                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.5,
                  children: [
                    _MetricCard(
                      title: AppStrings.totalProducts,
                      value: '$totalProducts',
                      icon: Icons.inventory_2_rounded,
                      color: AppColors.primary,
                      onTap: () => context.push('/products-mgmt'),
                    ),
                    _MetricCard(
                      title: AppStrings.lowStock,
                      value: '$lowStock',
                      icon: Icons.warning_amber_rounded,
                      color: AppColors.stockAmber,
                      onTap: () => context.push('/products-mgmt?filter=low_stock'),
                    ),
                    _MetricCard(
                      title: AppStrings.todaysScans,
                      value: '$todaysScans',
                      icon: Icons.qr_code_scanner,
                      color: AppColors.accent,
                      onTap: () => context.push('/sales-history'),
                    ),
                    _MetricCard(
                      title: AppStrings.pendingApprovals,
                      value: '$pending',
                      icon: Icons.pending_actions,
                      color: AppColors.warning,
                      onTap: isAdmin ? () => context.push('/pending-approvals') : null,
                    ),
                  ],
                );
              },
              loading: () => GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: const [
                  _MetricCard(title: AppStrings.totalProducts, value: '...', icon: Icons.inventory_2_rounded, color: AppColors.primary),
                  _MetricCard(title: AppStrings.lowStock, value: '...', icon: Icons.warning_amber_rounded, color: AppColors.stockAmber),
                  _MetricCard(title: AppStrings.todaysScans, value: '...', icon: Icons.qr_code_scanner, color: AppColors.accent),
                  _MetricCard(title: AppStrings.pendingApprovals, value: '...', icon: Icons.pending_actions, color: AppColors.warning),
                ],
              ),
              error: (err, _) => GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: const [
                  _MetricCard(title: AppStrings.totalProducts, value: 'Err', icon: Icons.inventory_2_rounded, color: AppColors.primary),
                  _MetricCard(title: AppStrings.lowStock, value: 'Err', icon: Icons.warning_amber_rounded, color: AppColors.stockAmber),
                  _MetricCard(title: AppStrings.todaysScans, value: 'Err', icon: Icons.qr_code_scanner, color: AppColors.accent),
                  _MetricCard(title: AppStrings.pendingApprovals, value: 'Err', icon: Icons.pending_actions, color: AppColors.warning),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── POS Daily Sales Summary ──────────────────────────
            Text(
              'POS Sales Summary',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ref.watch(dailySummaryProvider).when(
              data: (summary) {
                final sales = summary['total_sales_today'] ?? 0;
                final revenue = (summary['revenue_today'] ?? 0.0).toDouble();
                final profit = (summary['profit_today'] ?? 0.0).toDouble();
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SalesStat(
                          label: 'Sales',
                          value: '$sales',
                          icon: Icons.receipt_long_outlined,
                          color: AppColors.primary,
                        ),
                      ),
                      Container(width: 1, height: 40, color: AppColors.divider),
                      Expanded(
                        child: _SalesStat(
                          label: 'Revenue',
                          value: '₹${revenue.toStringAsFixed(0)}',
                          icon: Icons.monetization_on_outlined,
                          color: AppColors.success,
                        ),
                      ),
                      Container(width: 1, height: 40, color: AppColors.divider),
                      Expanded(
                        child: _SalesStat(
                          label: 'Profit',
                          value: '₹${profit.toStringAsFixed(0)}',
                          icon: Icons.trending_up_rounded,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'Failed to load sales: $err',
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Weekly Sales Performance',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 180,
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ref.watch(salesTrendProvider).when(
                data: (trend) {
                  if (trend.isEmpty) {
                    return const Center(child: Text('No trend data available', style: TextStyle(color: AppColors.textSecondary)));
                  }
                  
                  final maxRev = trend.map((e) => (e['revenue'] as num?)?.toDouble() ?? 0.0).reduce((a, b) => a > b ? a : b);
                  final maxY = maxRev == 0 ? 100.0 : maxRev * 1.25;

                  return LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: FlTitlesData(
                        show: true,
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final int index = value.toInt();
                              if (index < 0 || index >= trend.length) return const SizedBox.shrink();
                              final item = trend[index];
                              final dateStr = item['date'] as String? ?? '';
                              if (dateStr.isEmpty) return const SizedBox.shrink();
                              final parsed = DateTime.parse(dateStr);
                              final dayFormat = DateFormat('E').format(parsed);
                              return Padding(
                                padding: const EdgeInsets.only(top: 6.0),
                                child: Text(
                                  dayFormat,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                    fontFamily: GoogleFonts.inter().fontFamily,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      minX: 0,
                      maxX: (trend.length - 1).toDouble(),
                      minY: 0,
                      maxY: maxY,
                      lineBarsData: [
                        LineChartBarData(
                          spots: List.generate(trend.length, (idx) {
                            final rev = (trend[idx]['revenue'] as num?)?.toDouble() ?? 0.0;
                            return FlSpot(idx.toDouble(), rev);
                          }),
                          isCurved: true,
                          color: AppColors.primary,
                          barWidth: 3.5,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppColors.primary.withOpacity(0.08),
                          ),
                        ),
                        LineChartBarData(
                          spots: List.generate(trend.length, (idx) {
                            final prf = (trend[idx]['profit'] as num?)?.toDouble() ?? 0.0;
                            return FlSpot(idx.toDouble(), prf);
                          }),
                          isCurved: true,
                          color: AppColors.success,
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppColors.success.withOpacity(0.04),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Chart error: $err', style: const TextStyle(fontSize: 11, color: AppColors.error))),
              ),
            ),
            const SizedBox(height: 24),

            // ── Low stock alerts ────────────────────────────────
            Text(
              AppStrings.lowStockAlerts,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ref.watch(locationInventoryListProvider).when(
              data: (list) {
                final lowStockItems = list.where((item) {
                  final qty = item['quantity'] as int? ?? 0;
                  final minQty = item['min_quantity'] as int? ?? 0;
                  return minQty > 0 && qty < minQty;
                }).toList();

                if (lowStockItems.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        AppStrings.noAlerts,
                        style: GoogleFonts.inter(
                          color: AppColors.textHint,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                }

                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: lowStockItems.length > 5 ? 5 : lowStockItems.length,
                    separatorBuilder: (_, __) => const Divider(color: AppColors.divider, height: 1),
                    itemBuilder: (context, idx) {
                      final item = lowStockItems[idx];
                      final name = item['product_name'] ?? 'Unknown';
                      final qty = item['quantity'] ?? 0;
                      final minQty = item['min_quantity'] ?? 0;
                      return ListTile(
                        leading: const Icon(Icons.warning_amber_rounded, color: AppColors.stockAmber),
                        title: Text(name, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        subtitle: Text('Current Stock: $qty / Min threshold: $minQty', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        dense: true,
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) => Container(
                padding: const EdgeInsets.all(20),
                child: Center(child: Text('Error loading alerts: $err', style: const TextStyle(color: AppColors.error))),
              ),
            ),
            const SizedBox(height: 24),

            // ── Recent activity ─────────────────────────────────
            Text(
              AppStrings.recentActivity,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ref.watch(recentTransactionsProvider).when(
              data: (list) {
                if (list.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        AppStrings.noTransactions,
                        style: GoogleFonts.inter(
                          color: AppColors.textHint,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                }
                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: list.length > 5 ? 5 : list.length,
                    separatorBuilder: (_, __) => const Divider(color: AppColors.divider, height: 1),
                    itemBuilder: (context, idx) {
                      final item = list[idx];
                      final pName = item['product_name'] ?? 'Unknown';
                      final uName = item['user_name'] ?? 'Staff';
                      final typeStr = item['type'] ?? 'transaction';
                      final qtyChange = item['quantity_change'] ?? 0;
                      final dateStr = item['created_at'] != null 
                          ? DateFormat('MMM dd, hh:mm a').format(DateTime.parse(item['created_at']))
                          : '';
                      final isPositive = qtyChange > 0;

                      IconData icon = Icons.swap_horiz;
                      Color iconColor = AppColors.textSecondary;
                      if (typeStr == 'sale') {
                        icon = Icons.shopping_bag_outlined;
                        iconColor = AppColors.accent;
                      } else if (typeStr == 'receive') {
                        icon = Icons.add_circle_outline;
                        iconColor = AppColors.success;
                      } else if (typeStr == 'dispatch') {
                        icon = Icons.remove_circle_outline;
                        iconColor = AppColors.error;
                      }

                      return ListTile(
                        leading: Icon(icon, color: iconColor),
                        title: Text(pName, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        subtitle: Text('By $uName | $dateStr', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        trailing: Text(
                          '${isPositive ? "+" : ""}$qtyChange',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            color: isPositive ? AppColors.success : AppColors.error,
                            fontSize: 14,
                          ),
                        ),
                        dense: true,
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) => Container(
                padding: const EdgeInsets.all(20),
                child: Center(child: Text('Error loading activity: $err', style: const TextStyle(color: AppColors.error))),
              ),
            ),
          ],
        ),
      ),

      // ── Bottom navigation ─────────────────────────────────────
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.bottomNavBg,
          border: Border(
            top: BorderSide(color: AppColors.divider, width: 0.5),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: 0,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedLabelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 11),
          onTap: (index) {
            switch (index) {
              case 0:
                break; // Already on dashboard
              case 1:
                showModalBottomSheet(
                  context: context,
                  backgroundColor: AppColors.cardBg,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (context) => SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Select Scan Mode',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.shopping_cart_checkout_outlined, color: AppColors.accent),
                            ),
                            title: Text(
                              'POS Billing',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            ),
                            subtitle: const Text(
                              'Continuous scanning to auto-append items to cart',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              context.push('/billing');
                            },
                          ),
                          const Divider(color: AppColors.divider),
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.warehouse_outlined, color: AppColors.primary),
                            ),
                            title: Text(
                              'Inventory Stock Management',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            ),
                            subtitle: const Text(
                              'Adjust stock quantities or add new products to catalog',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              context.push('/scanner?mode=inventory');
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
                break;
              case 2:
                context.push('/billing');
                break;
              case 3:
                context.push('/reports');
                break;
              case 4:
                context.push('/products-mgmt');
                break;
            }
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_scanner),
              label: 'Scan',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.shopping_cart_checkout_outlined),
              label: 'Billing',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded),
              label: 'Reports',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2_rounded),
              label: 'Products',
            ),
          ],
        ),
      ),
    );
  }
}

/// Summary metric card widget
class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SalesStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SalesStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: AppColors.textHint,
          ),
        ),
      ],
    );
  }
}

