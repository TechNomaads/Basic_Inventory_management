import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../data/billing_repository.dart';
import '../domain/billing_notifier.dart';

class SalesHistoryScreen extends ConsumerStatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  ConsumerState<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends ConsumerState<SalesHistoryScreen> {
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _invoices = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _skip = 0;
  final int _limit = 20;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    Future.microtask(() => _refreshInvoices());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _loadMoreInvoices();
    }
  }

  Future<void> _refreshInvoices() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _skip = 0;
      _invoices.clear();
      _hasMore = true;
    });

    try {
      final repo = ref.read(billingRepositoryProvider);
      final locationId = ref.read(selectedLocationProvider);

      final list = await repo.fetchInvoices(
        locationId: locationId,
        skip: _skip,
        limit: _limit,
      );

      setState(() {
        _invoices = list;
        _skip += list.length;
        if (list.length < _limit) {
          _hasMore = false;
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load sales history: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _loadMoreInvoices() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final repo = ref.read(billingRepositoryProvider);
      final locationId = ref.read(selectedLocationProvider);

      final list = await repo.fetchInvoices(
        locationId: locationId,
        skip: _skip,
        limit: _limit,
      );

      setState(() {
        _invoices.addAll(list);
        _skip += list.length;
        if (list.length < _limit) {
          _hasMore = false;
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showInvoiceDetails(String invoiceId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final repo = ref.read(billingRepositoryProvider);
      final invoice = await repo.fetchInvoiceById(invoiceId);
      
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading spinner

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _InvoiceDetailsSheet(invoice: invoice),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context); // Dismiss loading spinner
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load invoice details: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedLocation = ref.watch(selectedLocationProvider);
    final locationsAsync = ref.watch(locationsProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sales History',
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
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          // Store Location Selector
          locationsAsync.when(
            data: (locs) => PopupMenuButton<String>(
              icon: const Icon(Icons.storefront, color: AppColors.textPrimary),
              tooltip: 'Change Store Location',
              onSelected: (locId) {
                ref.read(selectedLocationProvider.notifier).state = locId;
                _refreshInvoices();
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: null,
                  child: Text('All Locations'),
                ),
                ...locs.map((loc) {
                  return PopupMenuItem<String>(
                    value: loc['id'] as String,
                    child: Text(loc['name'] as String),
                  );
                }),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshInvoices,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshInvoices,
        child: _invoices.isEmpty && _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _invoices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.receipt_long_outlined,
                          size: 64,
                          color: AppColors.textHint,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No sales records found',
                          style: GoogleFonts.inter(
                            color: AppColors.textHint,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _invoices.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _invoices.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final invoice = _invoices[index];
                      final invoiceId = invoice['id'] as String;
                      final invoiceNum = invoiceId.substring(0, 8).toUpperCase();
                      final totalAmount = (invoice['total_amount'] as num).toDouble();
                      final paymentMode = invoice['payment_mode']?.toString().toUpperCase() ?? 'CASH';
                      final customerName = invoice['customer_name']?.toString() ?? 'Walk-in Customer';
                      final date = invoice['created_at'] != null
                          ? DateTime.parse(invoice['created_at'] as String).toLocal()
                          : DateTime.now();
                      final formattedDate = '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

                      // Determine invoice due/status
                      final amountPaid = (invoice['amount_paid'] as num?)?.toDouble() ?? totalAmount;
                      final isFullyPaid = amountPaid >= totalAmount;
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: AppColors.cardBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: AppColors.divider),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _showInvoiceDetails(invoiceId),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.receipt_outlined,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'INV-$invoiceNum',
                                            style: GoogleFonts.outfit(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isFullyPaid
                                                  ? AppColors.stockGreen.withOpacity(0.12)
                                                  : AppColors.stockRed.withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              isFullyPaid ? 'PAID' : 'DUE',
                                              style: GoogleFonts.inter(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: isFullyPaid ? AppColors.stockGreen : AppColors.stockRed,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        customerName,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        formattedDate,
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: AppColors.textHint,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '₹${totalAmount.toStringAsFixed(2)}',
                                      style: GoogleFonts.outfit(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      paymentMode,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: AppColors.textHint,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _InvoiceDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> invoice;

  const _InvoiceDetailsSheet({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final invoiceId = invoice['id'] as String;
    final invoiceNum = invoiceId.substring(0, 8).toUpperCase();
    final items = invoice['items'] as List<dynamic>? ?? [];
    final subtotal = (invoice['subtotal'] as num?)?.toDouble() ?? 0.0;
    final taxAmount = (invoice['tax_amount'] as num?)?.toDouble() ?? 0.0;
    final discountAmount = (invoice['discount_amount'] as num?)?.toDouble() ?? 0.0;
    final totalAmount = (invoice['total_amount'] as num).toDouble();
    final amountPaid = (invoice['amount_paid'] as num?)?.toDouble() ?? totalAmount;
    final dueAmount = totalAmount - amountPaid;
    final paymentMode = invoice['payment_mode']?.toString().toUpperCase() ?? 'CASH';
    final customerName = invoice['customer_name']?.toString() ?? 'Walk-in Customer';
    final customerPhone = invoice['customer_phone']?.toString() ?? 'N/A';
    final notes = invoice['notes']?.toString();

    final date = invoice['created_at'] != null
        ? DateTime.parse(invoice['created_at'] as String).toLocal()
        : DateTime.now();
    final formattedDate = '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Invoice Details',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'INV-$invoiceNum | $formattedDate',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.divider),
          const SizedBox(height: 12),

          // Customer Profile Info
          Text(
            'Customer Details',
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Name: $customerName',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
          ),
          Text(
            'Phone: $customerPhone',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.divider),
          const SizedBox(height: 12),

          // Items Title
          Text(
            'Items',
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),

          // List of items
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final name = item['product_name'] ?? 'Unknown Item';
                final qty = item['quantity'] as int? ?? 1;
                final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
                final total = price * qty;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$qty x ₹${price.toStringAsFixed(2)}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '₹${total.toStringAsFixed(2)}',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          
          const Divider(color: AppColors.divider),
          const SizedBox(height: 12),

          // Summary Details
          _buildSummaryRow('Subtotal', '₹${subtotal.toStringAsFixed(2)}'),
          _buildSummaryRow('Tax Amount', '₹${taxAmount.toStringAsFixed(2)}'),
          if (discountAmount > 0)
            _buildSummaryRow('Discount', '-₹${discountAmount.toStringAsFixed(2)}', color: AppColors.stockRed),
          _buildSummaryRow('Total', '₹${totalAmount.toStringAsFixed(2)}', isBold: true),
          _buildSummaryRow('Amount Paid', '₹${amountPaid.toStringAsFixed(2)}'),
          if (dueAmount > 0)
            _buildSummaryRow('Balance Due', '₹${dueAmount.toStringAsFixed(2)}', color: AppColors.stockRed, isBold: true),
          _buildSummaryRow('Payment Mode', paymentMode),
          
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Notes: $notes',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: isBold ? 15 : 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
