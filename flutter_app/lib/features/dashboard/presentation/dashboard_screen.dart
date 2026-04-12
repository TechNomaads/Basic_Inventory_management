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
                  value: 'audit',
                  child: ListTile(
                    leading: Icon(Icons.history, color: AppColors.textSecondary),
                    title: Text(AppStrings.auditLog),
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
          // Refresh dashboard data
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Metric cards ────────────────────────────────────
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _MetricCard(
                  title: AppStrings.totalProducts,
                  value: '—',
                  icon: Icons.inventory_2_rounded,
                  color: AppColors.primary,
                ),
                _MetricCard(
                  title: AppStrings.lowStock,
                  value: '—',
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.stockAmber,
                ),
                _MetricCard(
                  title: AppStrings.todaysScans,
                  value: '—',
                  icon: Icons.qr_code_scanner,
                  color: AppColors.accent,
                ),
                _MetricCard(
                  title: AppStrings.pendingApprovals,
                  value: '—',
                  icon: Icons.pending_actions,
                  color: AppColors.warning,
                ),
              ],
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
            Container(
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
            Container(
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
                context.push('/scanner');
                break;
              case 2:
                context.push('/reports');
                break;
              case 3:
                if (isAdmin) context.push('/products-mgmt');
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
              icon: Icon(Icons.bar_chart_rounded),
              label: 'Reports',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_rounded),
              label: 'Manage',
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

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}
