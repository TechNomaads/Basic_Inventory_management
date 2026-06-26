import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';

import '../../../core/constants/app_colors.dart';
import '../data/pending_repository.dart';
import '../../auth/domain/auth_notifier.dart';

class PendingApprovalsScreen extends ConsumerStatefulWidget {
  const PendingApprovalsScreen({super.key});

  @override
  ConsumerState<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends ConsumerState<PendingApprovalsScreen> {
  List<Map<String, dynamic>> _adjustments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _fetchAdjustments());
  }

  Future<void> _fetchAdjustments() async {
    setState(() => _isLoading = true);

    try {
      final repo = ref.read(pendingRepositoryProvider);
      final list = await repo.fetchPendingAdjustments();
      setState(() {
        _adjustments = list;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load pending adjustments: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _reviewAdjustment(String id, bool approve) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final repo = ref.read(pendingRepositoryProvider);
      if (approve) {
        await repo.approveAdjustment(id);
      } else {
        await repo.rejectAdjustment(id);
      }

      if (!mounted) return;
      Navigator.pop(context); // Dismiss spinner

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Adjustment request approved!' : 'Adjustment request rejected.'),
          backgroundColor: approve ? AppColors.stockGreen : AppColors.stockRed,
        ),
      );

      // Refresh list
      _fetchAdjustments();
    } on DioException catch (e) {
      if (mounted) Navigator.pop(context); // Dismiss spinner
      final msg = e.response?.data?['detail']?.toString() ?? 'Action failed. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context); // Dismiss spinner
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isAuthorized = authState is AuthAuthenticated && authState.user.canManage;

    if (!isAuthorized) {
      return Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: const Text('Pending Approvals'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.gpp_bad_outlined, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                'Access Denied',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Only managers and admins can review pending adjustments.',
                style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(
          'Pending Approvals',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchAdjustments,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchAdjustments,
        child: _isLoading && _adjustments.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _adjustments.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.7,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.assignment_turned_in_outlined,
                                size: 64,
                                color: AppColors.textHint,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No pending adjustments',
                                style: GoogleFonts.inter(
                                  color: AppColors.textHint,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _adjustments.length,
                    itemBuilder: (context, index) {
                      final adj = _adjustments[index];
                      final adjId = adj['id'] as String;
                      final productName = adj['product_name']?.toString() ?? 'Unknown Product';
                      final locationName = adj['location_name']?.toString() ?? 'Unknown Location';
                      final userName = adj['user_name']?.toString() ?? 'System';
                      final qtyChange = adj['quantity_change'] as int;
                      final isPositive = qtyChange > 0;
                      final notes = adj['notes']?.toString();
                      final date = adj['created_at'] != null
                          ? DateTime.parse(adj['created_at'] as String).toLocal()
                          : DateTime.now();
                      final formattedDate =
                          '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        color: AppColors.cardBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: AppColors.divider),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Product and quantity change
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      productName,
                                      style: GoogleFonts.outfit(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: (isPositive ? AppColors.stockGreen : AppColors.stockRed)
                                          .withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${isPositive ? '+' : ''}$qtyChange',
                                      style: GoogleFonts.outfit(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: isPositive ? AppColors.stockGreen : AppColors.stockRed,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Divider(color: AppColors.divider),
                              const SizedBox(height: 8),

                              // Metadata
                              _buildRow('Store Location', locationName),
                              _buildRow('Requested By', userName),
                              _buildRow('Request Date', formattedDate),
                              
                              if (notes != null && notes.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Reason: $notes',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                              
                              const SizedBox(height: 16),
                              const Divider(color: AppColors.divider),
                              const SizedBox(height: 12),

                              // Actions
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _reviewAdjustment(adjId, false),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.stockRed,
                                        side: const BorderSide(color: AppColors.stockRed),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                      icon: const Icon(Icons.close, size: 18),
                                      label: const Text('Reject'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => _reviewAdjustment(adjId, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.stockGreen,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                      icon: const Icon(Icons.check, size: 18),
                                      label: const Text('Approve'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
