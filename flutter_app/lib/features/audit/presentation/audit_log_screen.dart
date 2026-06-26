import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../data/audit_repository.dart';

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _logs = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _skip = 0;
  final int _limit = 25;
  String? _selectedActionFilter;

  final List<String> _actions = ['INSERT', 'UPDATE', 'DELETE'];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    Future.microtask(() => _refreshLogs());
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
      _loadMoreLogs();
    }
  }

  Future<void> _refreshLogs() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _skip = 0;
      _logs.clear();
      _hasMore = true;
    });

    try {
      final repo = ref.read(auditRepositoryProvider);
      final data = await repo.fetchAuditLogs(
        action: _selectedActionFilter,
        skip: _skip,
        limit: _limit,
      );

      final list = data['items'] as List<dynamic>? ?? [];

      setState(() {
        _logs = list;
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
          content: Text('Failed to load audit logs: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _loadMoreLogs() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final repo = ref.read(auditRepositoryProvider);
      final data = await repo.fetchAuditLogs(
        action: _selectedActionFilter,
        skip: _skip,
        limit: _limit,
      );

      final list = data['items'] as List<dynamic>? ?? [];

      setState(() {
        _logs.addAll(list);
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

  void _showLogDetails(Map<String, dynamic> log) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AuditDetailsSheet(log: log),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(
          'System Audit Logs',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter by Action',
            onSelected: (action) {
              setState(() {
                _selectedActionFilter = action;
              });
              _refreshLogs();
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String?>(
                value: null,
                child: Text('All Actions'),
              ),
              ..._actions.map((act) => PopupMenuItem<String?>(
                    value: act,
                    child: Text(act),
                  )),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshLogs,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshLogs,
        child: _logs.isEmpty && _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _logs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.history_edu,
                          size: 64,
                          color: AppColors.textHint,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No audit logs found',
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
                    itemCount: _logs.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _logs.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final log = Map<String, dynamic>.from(_logs[index] as Map);
                      final action = log['action']?.toString().toUpperCase() ?? 'ACTION';
                      final tableName = log['table_name']?.toString() ?? 'N/A';
                      final userName = log['user_name']?.toString() ?? 'System';
                      final ipAddress = log['ip_address']?.toString() ?? 'N/A';
                      final date = log['created_at'] != null
                          ? DateTime.parse(log['created_at'] as String).toLocal()
                          : DateTime.now();
                      final formattedDate =
                          '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

                      Color badgeColor;
                      switch (action) {
                        case 'INSERT':
                          badgeColor = AppColors.stockGreen;
                          break;
                        case 'UPDATE':
                          badgeColor = AppColors.stockAmber;
                          break;
                        case 'DELETE':
                          badgeColor = AppColors.stockRed;
                          break;
                        default:
                          badgeColor = AppColors.primary;
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: AppColors.cardBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: AppColors.divider),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _showLogDetails(log),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: badgeColor.withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              action,
                                              style: GoogleFonts.inter(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: badgeColor,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            tableName.toUpperCase(),
                                            style: GoogleFonts.outfit(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'User: $userName',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'IP: $ipAddress | $formattedDate',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: AppColors.textHint,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: AppColors.textSecondary,
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

class _AuditDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> log;

  const _AuditDetailsSheet({required this.log});

  @override
  Widget build(BuildContext context) {
    final action = log['action']?.toString().toUpperCase() ?? 'ACTION';
    final tableName = log['table_name']?.toString() ?? 'N/A';
    final recordId = log['record_id']?.toString() ?? 'N/A';
    final userName = log['user_name']?.toString() ?? 'System';
    final ipAddress = log['ip_address']?.toString() ?? 'N/A';
    final date = log['created_at'] != null
        ? DateTime.parse(log['created_at'] as String).toLocal()
        : DateTime.now();
    final formattedDate =
        '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    final oldValues = log['old_values'] as Map<String, dynamic>?;
    final newValues = log['new_values'] as Map<String, dynamic>?;

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
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
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Audit Log Details',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$formattedDate',
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

          _buildRow('ActionPerformed', action),
          _buildRow('Target Table', tableName),
          _buildRow('Record ID', recordId),
          _buildRow('Operator User', userName),
          _buildRow('IP Address', ipAddress),

          const SizedBox(height: 16),
          const Divider(color: AppColors.divider),
          const SizedBox(height: 12),

          // Display diff (old vs new)
          Expanded(
            child: ListView(
              children: [
                if (oldValues != null && oldValues.isNotEmpty) ...[
                  Text(
                    'PREVIOUS STATE (OLD VALUES)',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.stockRed,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Text(
                      _formatMap(oldValues),
                      style: GoogleFonts.firaCode(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (newValues != null && newValues.isNotEmpty) ...[
                  Text(
                    'UPDATED STATE (NEW VALUES)',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.stockGreen,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Text(
                      _formatMap(newValues),
                      style: GoogleFonts.firaCode(
                        fontSize: 11,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
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

  String _formatMap(Map<String, dynamic> map) {
    final List<String> lines = [];
    map.forEach((key, val) {
      lines.add('"$key": $val');
    });
    return lines.join('\n');
  }
}
