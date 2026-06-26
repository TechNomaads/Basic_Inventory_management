import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../data/customer_repository.dart';
import '../domain/customer_model.dart';

final customerKpisProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(customerRepositoryProvider);
  return repo.fetchCustomersKpis();
});

class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key});

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  final _searchController = TextEditingController();
  int _currentPage = 1;
  bool _isLoading = false;
  List<CustomerModel> _customers = [];
  int _totalPages = 1;
  int _totalCustomersCount = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(customerRepositoryProvider);
      final result = await repo.fetchCustomers(
        search: _searchController.text.trim(),
        page: _currentPage,
      );
      setState(() {
        _customers = result['items'] as List<CustomerModel>;
        _totalPages = result['pages'] as int;
        _totalCustomersCount = result['total'] as int;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load customers: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _triggerSearch() {
    setState(() {
      _currentPage = 1;
    });
    _loadCustomers();
  }

  void _showAddCustomerDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final limitCtrl = TextEditingController(text: '10000.00');
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
            'Register Customer',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          content: isSaving
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: 20),
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Saving customer...', style: TextStyle(color: AppColors.textSecondary)),
                    SizedBox(height: 20),
                  ],
                )
              : Form(
                  key: formKey,
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
                    ],
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
                        await repo.createCustomer({
                          'name': nameCtrl.text.trim(),
                          'phone': phoneCtrl.text.trim(),
                          'credit_limit': double.parse(limitCtrl.text),
                        });
                        
                        // Success
                        Navigator.pop(context);
                        ref.invalidate(customerKpisProvider);
                        _loadCustomers();
                      } catch (e) {
                        setDialogState(() {
                          isSaving = false;
                          dialogError = e.toString().contains('already exists')
                              ? 'A customer with this phone number already exists.'
                              : 'Failed to create customer: $e';
                        });
                      }
                    },
                    child: const Text('REGISTER'),
                  ),
                ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kpisAsync = ref.watch(customerKpisProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(
          'Customers Directory',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.accent),
            tooltip: 'Register Customer',
            onPressed: _showAddCustomerDialog,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── KPI Summary Cards ─────────────────────────────────
          kpisAsync.when(
            data: (kpis) {
              final totalCustomers = kpis['total_count'] ?? 0;
              final totalOverdue = (kpis['total_overdue'] as num? ?? 0.0).toDouble();
              final totalCredit = (kpis['total_credit'] as num? ?? 0.0).toDouble();

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _KpiCard(
                        title: 'Total Customers',
                        value: '$totalCustomers',
                        icon: Icons.people_outline_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _KpiCard(
                        title: 'Outstanding Debt',
                        value: '₹${totalOverdue.toStringAsFixed(0)}',
                        icon: Icons.monetization_on_outlined,
                        color: AppColors.stockRed,
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => const SizedBox.shrink(),
          ),

          // ── Search & Filter ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search by name or phone...',
                      prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
                      filled: true,
                      fillColor: AppColors.cardBg,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.divider),
                      ),
                    ),
                    onSubmitted: (_) => _triggerSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _triggerSearch,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  child: const Icon(Icons.arrow_forward),
                ),
              ],
            ),
          ),

          // ── Customers List Table ──────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Text(_errorMessage!, style: const TextStyle(color: AppColors.stockRed)),
                      )
                    : _customers.isEmpty
                        ? const Center(
                            child: Text(
                              'No customers found.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _customers.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final cust = _customers[index];
                              return _CustomerListTile(
                                customer: cust,
                                onTap: () async {
                                  await context.push('/customers/${cust.id}');
                                  ref.invalidate(customerKpisProvider);
                                  _loadCustomers();
                                },
                              );
                            },
                          ),
          ),

          // ── Pagination Controls ───────────────────────────────
          if (_totalPages > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    color: AppColors.textPrimary,
                    onPressed: _currentPage > 1
                        ? () {
                            setState(() => _currentPage--);
                            _loadCustomers();
                          }
                        : null,
                  ),
                  Text(
                    'Page $_currentPage of $_totalPages',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    color: AppColors.textPrimary,
                    onPressed: _currentPage < _totalPages
                        ? () {
                            setState(() => _currentPage++);
                            _loadCustomers();
                          }
                        : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
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
              Text(title, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textHint, fontWeight: FontWeight.w500)),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerListTile extends StatelessWidget {
  final CustomerModel customer;
  final VoidCallback onTap;

  const _CustomerListTile({required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool hasOverdue = customer.overdueAmount > 0.01;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              backgroundColor: hasOverdue ? AppColors.stockRed.withOpacity(0.12) : AppColors.primary.withOpacity(0.12),
              child: Icon(
                Icons.person,
                color: hasOverdue ? AppColors.stockRed : AppColors.primary,
              ),
            ),
            const SizedBox(width: 14),

            // Profile info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    customer.phone ?? 'No Phone',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textHint),
                  ),
                ],
              ),
            ),

            // Overdue and Credit Limits
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (hasOverdue)
                  Text(
                    '₹${customer.overdueAmount.toStringAsFixed(2)} due',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.stockRed),
                  )
                else
                  const Text(
                    'No Overdue',
                    style: TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Limit: ₹${customer.creditLimit.toStringAsFixed(0)}',
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.textHint),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}
