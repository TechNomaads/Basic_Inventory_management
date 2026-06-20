/// [ReportsScreen] — Dashboard analytics and transaction history.
///
/// Responsibilities:
///   - Show summary metrics in a card grid
///   - Display line chart for daily trends
///   - Display pie chart for category stock levels
///   - Link to full transaction history
///
/// Dependencies: Riverpod, AppColors, fl_chart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../billing/domain/billing_notifier.dart';
import '../domain/reports_notifier.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(locationsProvider);
    final selectedLocation = ref.watch(selectedLocationProvider);
    final summaryAsync = ref.watch(reportsSummaryProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.reportsTitle,
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
            ),
            locationsAsync.when(
              data: (locs) {
                final currentLoc = locs.firstWhere(
                  (l) => l['id'] == selectedLocation,
                  orElse: () => {'name': 'All Locations'},
                );
                return Text(
                  currentLoc['name'] as String,
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.primaryLight),
                );
              },
              loading: () => const Text('Loading location...', style: TextStyle(fontSize: 11)),
              error: (_, __) => const Text('Error loading location', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          locationsAsync.when(
            data: (locs) => PopupMenuButton<String>(
              icon: const Icon(Icons.storefront, color: AppColors.textPrimary),
              tooltip: 'Filter by Location',
              onSelected: (locId) {
                ref.read(selectedLocationProvider.notifier).state = locId;
                ref.invalidate(reportsSummaryProvider);
                ref.invalidate(salesTrendProvider);
                ref.invalidate(categoryStockProvider);
              },
              itemBuilder: (context) => locs.map((l) {
                return PopupMenuItem<String>(
                  value: l['id'] as String,
                  child: Text(l['name'] as String),
                );
              }).toList(),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.cardBg,
        onRefresh: () async {
          ref.invalidate(reportsSummaryProvider);
          ref.invalidate(salesTrendProvider);
          ref.invalidate(categoryStockProvider);
          try {
            await ref.read(reportsSummaryProvider.future);
          } catch (_) {}
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Summary metrics ───────────────────────────────────
            summaryAsync.when(
              data: (summary) {
                final dispatched = summary['total_dispatched'] ?? 0;
                final received = summary['total_received'] ?? 0;
                final outOfStock = summary['out_of_stock_count'] ?? 0;
                final activeUsers = summary['active_users'] ?? 0;

                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.5,
                  children: [
                    _ReportCard(
                      title: AppStrings.dispatched,
                      value: '$dispatched',
                      icon: Icons.arrow_upward_rounded,
                      color: AppColors.stockRed,
                    ),
                    _ReportCard(
                      title: AppStrings.received,
                      value: '$received',
                      icon: Icons.arrow_downward_rounded,
                      color: AppColors.stockGreen,
                    ),
                    _ReportCard(
                      title: AppStrings.outOfStock,
                      value: '$outOfStock',
                      icon: Icons.remove_shopping_cart,
                      color: AppColors.error,
                    ),
                    _ReportCard(
                      title: AppStrings.activeUsers,
                      value: '$activeUsers',
                      icon: Icons.people_outline,
                      color: AppColors.primary,
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
                  _ReportCard(title: AppStrings.dispatched, value: '...', icon: Icons.arrow_upward_rounded, color: AppColors.stockRed),
                  _ReportCard(title: AppStrings.received, value: '...', icon: Icons.arrow_downward_rounded, color: AppColors.stockGreen),
                  _ReportCard(title: AppStrings.outOfStock, value: '...', icon: Icons.remove_shopping_cart, color: AppColors.error),
                  _ReportCard(title: AppStrings.activeUsers, value: '...', icon: Icons.people_outline, color: AppColors.primary),
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
                  _ReportCard(title: AppStrings.dispatched, value: 'Err', icon: Icons.arrow_upward_rounded, color: AppColors.stockRed),
                  _ReportCard(title: AppStrings.received, value: 'Err', icon: Icons.arrow_downward_rounded, color: AppColors.stockGreen),
                  _ReportCard(title: AppStrings.outOfStock, value: 'Err', icon: Icons.remove_shopping_cart, color: AppColors.error),
                  _ReportCard(title: AppStrings.activeUsers, value: 'Err', icon: Icons.people_outline, color: AppColors.primary),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Weekly Trend Line Chart ──────────────────────────
            Container(
              height: 240,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Weekly Sales & Profit Trend',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(width: 8, height: 8, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text('Revenue', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
                      const SizedBox(width: 12),
                      Container(width: 8, height: 8, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text('Profit', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ref.watch(salesTrendProvider).when(
                      data: (trend) {
                        if (trend.isEmpty) {
                          return const Center(child: Text('No trend data available', style: TextStyle(color: AppColors.textSecondary)));
                        }

                        final maxRev = trend.map((e) => (e['revenue'] as num?)?.toDouble() ?? 0.0).reduce((a, b) => a > b ? a : b);
                        final maxY = maxRev == 0 ? 100.0 : maxRev * 1.25;

                        return LineChart(
                          LineChartData(
                            gridData: const FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: 500,
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 32,
                                  getTitlesWidget: (value, meta) {
                                    if (value == 0) return const SizedBox.shrink();
                                    return Text(
                                      '₹${value.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 9,
                                        fontFamily: GoogleFonts.inter().fontFamily,
                                      ),
                                    );
                                  },
                                ),
                              ),
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
                            borderData: FlBorderData(
                              show: true,
                              border: const Border(
                                bottom: BorderSide(color: AppColors.divider, width: 1),
                              ),
                            ),
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
                                barWidth: 3,
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
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Category Stock Distribution Pie Chart ─────────────
            Container(
              height: 280,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stock Distribution by Category',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ref.watch(categoryStockProvider).when(
                      data: (data) {
                        if (data.isEmpty) {
                          return const Center(child: Text('No category stock levels available', style: TextStyle(color: AppColors.textSecondary)));
                        }

                        final totalStock = data.fold<int>(0, (sum, e) => sum + (e['total_stock'] as num).toInt());
                        final chartColors = [
                          AppColors.primary,
                          AppColors.accent,
                          AppColors.success,
                          AppColors.stockAmber,
                          AppColors.warning,
                        ];

                        return Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: PieChart(
                                PieChartData(
                                  sectionsSpace: 2,
                                  centerSpaceRadius: 40,
                                  sections: List.generate(data.length, (idx) {
                                    final item = data[idx];
                                    final stock = (item['total_stock'] as num).toInt();
                                    final percent = totalStock > 0 ? (stock / totalStock) * 100 : 0.0;
                                    return PieChartSectionData(
                                      color: chartColors[idx % chartColors.length],
                                      value: stock.toDouble(),
                                      title: percent > 10 ? '${percent.toStringAsFixed(0)}%' : '',
                                      radius: 45,
                                      titleStyle: GoogleFonts.outfit(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: data.length > 5 ? 5 : data.length,
                                itemBuilder: (context, idx) {
                                  final item = data[idx];
                                  final name = item['category_name'] ?? 'Other';
                                  final stock = item['total_stock'] ?? 0;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: chartColors[idx % chartColors.length],
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '$name ($stock)',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (err, _) => Center(child: Text('Chart error: $err', style: const TextStyle(fontSize: 11, color: AppColors.error))),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── View transaction history ──────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/transactions'),
                icon: const Icon(Icons.history),
                label: Text(
                  'View Transaction History',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _ReportCard({
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
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.outfit(
                  fontSize: 22,
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
