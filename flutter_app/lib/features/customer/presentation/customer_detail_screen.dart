import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../data/customer_repository.dart';
import '../domain/customer_detail_model.dart';
import '../domain/customer_model.dart';

final customerDetailProvider = FutureProvider.autoDispose.family<CustomerDetailModel, String>((ref, id) async {
  final repo = ref.watch(customerRepositoryProvider);
  return repo.fetchCustomerDetail(id);
});

class CustomerDetailScreen extends ConsumerStatefulWidget {
  final String customerId;

  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  ConsumerState<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  final _dateFormat = DateFormat('MMM dd, yyyy | hh:mm a');

  void _showEditCustomerDialog(CustomerModel customer) {
    final nameCtrl = TextEditingController(text: customer.name);
    final phoneCtrl = TextEditingController(text: customer.phone);
    final limitCtrl = TextEditingController(text: customer.creditLimit.toStringAsFixed(2));
    final overdueCtrl = TextEditingController(text: customer.overdueAmount.toStringAsFixed(2));
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;
    String? dialogError;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Edit Customer Details',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          content: isSaving
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: 20),
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Saving changes...', style: TextStyle(color: AppColors.textSecondary)),
                    SizedBox(height: 20),
                  ],
                )
              : Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (dialogError != null) ...[
                          Text(dialogError!, style: const TextStyle(color: AppColors.stockRed, fontSize: 13)),
                          const SizedBox(height: 12),
                        ],
                        TextFormField(
                          controller: nameCtrl,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Customer Name *',
                            labelStyle: const TextStyle(color: AppColors.textHint),
                            filled: true,
                            fillColor: AppColors.surfaceBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          validator: (value) => (value == null || value.trim().isEmpty) ? 'Please enter a name' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Phone Number *',
                            labelStyle: const TextStyle(color: AppColors.textHint),
                            filled: true,
                            fillColor: AppColors.surfaceBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          validator: (value) => (value == null || value.trim().length < 10) ? 'Please enter a valid 10+ digit phone' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: limitCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Credit Limit (₹) *',
                            labelStyle: const TextStyle(color: AppColors.textHint),
                            filled: true,
                            fillColor: AppColors.surfaceBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          validator: (value) {
                            if (value == null || double.tryParse(value) == null) {
                              return 'Please enter a numeric limit';
                            }
                            if (double.parse(value) < 0) {
                              return 'Limit cannot be negative';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: overdueCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Outstanding Overdue (₹) *',
                            labelStyle: const TextStyle(color: AppColors.textHint),
                            filled: true,
                            fillColor: AppColors.surfaceBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          validator: (value) {
                            if (value == null || double.tryParse(value) == null) {
                              return 'Please enter a numeric amount';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
          actions: isSaving
              ? null
              : [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() {
                        isSaving = true;
                        dialogError = null;
                      });

                      try {
                        final repo = ref.read(customerRepositoryProvider);
                        await repo.updateCustomer(customer.id, {
                          'name': nameCtrl.text.trim(),
                          'phone': phoneCtrl.text.trim(),
                          'credit_limit': double.parse(limitCtrl.text),
                          'overdue_amount': double.parse(overdueCtrl.text),
                        });
                        
                        // Success
                        Navigator.pop(context);
                        ref.invalidate(customerDetailProvider(widget.customerId));
                      } catch (e) {
                        setDialogState(() {
                          isSaving = false;
                          dialogError = 'Failed to update customer: $e';
                        });
                      }
                    },
                    child: const Text('SAVE'),
                  ),
                ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(customerDetailProvider(widget.customerId));

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(
          'Customer Details',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        actions: detailAsync.when(
          data: (detail) => [
            IconButton(
              icon: const Icon(Icons.edit_note_rounded, color: AppColors.accent, size: 28),
              tooltip: 'Edit Profile',
              onPressed: () => _showEditCustomerDialog(detail.profile),
            ),
          ],
          loading: () => [],
          error: (_, __) => [],
        ),
      ),
      body: detailAsync.when(
        data: (detail) {
          final profile = detail.profile;
          final invoices = detail.invoices;
          final bool hasOverdue = profile.overdueAmount > 0.01;

          // Initials for avatar
          final initials = profile.name.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header Profile Area ─────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                decoration: const BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: hasOverdue ? AppColors.stockRed.withOpacity(0.12) : AppColors.primary.withOpacity(0.12),
                      child: Text(
                        initials.isNotEmpty ? initials : '?',
                        style: GoogleFonts.outfit(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: hasOverdue ? AppColors.stockRed : AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.name,
                            style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.phone_rounded, size: 14, color: AppColors.textHint),
                              const SizedBox(width: 6),
                              Text(
                                profile.phone ?? 'No Phone Number',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Registered: ${DateFormat('MMM dd, yyyy').format(profile.createdAt)}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── KPI Stats Grid ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: _KpiStatCard(
                        title: 'Outstanding Debt',
                        value: '₹${profile.overdueAmount.toStringAsFixed(2)}',
                        icon: Icons.monetization_on_outlined,
                        color: hasOverdue ? AppColors.stockRed : AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _KpiStatCard(
                        title: 'Credit Limit',
                        value: '₹${profile.creditLimit.toStringAsFixed(0)}',
                        icon: Icons.speed_rounded,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Purchase History Title ──────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Purchase History (${invoices.length})',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),

              // ── Invoices List ───────────────────────────────────
              Expanded(
                child: invoices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_rounded, color: AppColors.textHint, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              'No purchases recorded yet.',
                              style: TextStyle(color: AppColors.textHint),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: invoices.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final invoice = invoices[index];
                          final isPaidInFull = invoice.remainingDue.abs() < 0.01;

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.cardBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      invoice.invoiceNumber,
                                      style: GoogleFonts.outfit(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: (isPaidInFull ? AppColors.success : AppColors.stockAmber).withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        isPaidInFull ? 'Fully Paid' : 'Credit Due',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isPaidInFull ? AppColors.success : AppColors.stockAmber,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                const Divider(color: AppColors.divider, height: 1),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _InvoiceDetailCol(
                                      label: 'Net Total',
                                      value: '₹${invoice.totalAmount.toStringAsFixed(2)}',
                                      color: AppColors.textPrimary,
                                    ),
                                    _InvoiceDetailCol(
                                      label: 'Amount Paid',
                                      value: '₹${invoice.amountPaid.toStringAsFixed(2)}',
                                      color: AppColors.textSecondary,
                                    ),
                                    _InvoiceDetailCol(
                                      label: 'Due Balance',
                                      value: '₹${invoice.remainingDue.toStringAsFixed(2)}',
                                      color: isPaidInFull ? AppColors.textHint : AppColors.stockRed,
                                      isBold: !isPaidInFull,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _dateFormat.format(invoice.createdAt),
                                      style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                                    ),
                                    Row(
                                      children: [
                                        const Icon(Icons.payment_rounded, size: 12, color: AppColors.textHint),
                                        const SizedBox(width: 4),
                                        Text(
                                          invoice.paymentMode.toUpperCase(),
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.accent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
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
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.stockRed, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Failed to load details:\n$err',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.stockRed),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(customerDetailProvider(widget.customerId)),
                  child: const Text('RETRY'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiStatCard({
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
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textHint, fontWeight: FontWeight.w500),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceDetailCol extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isBold;

  const _InvoiceDetailCol({
    required this.label,
    required this.value,
    required this.color,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 14,
            color: color,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
