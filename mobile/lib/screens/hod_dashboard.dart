import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/od_request.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/od_service.dart';
import '../utils/validators.dart';

class HodDashboard extends StatefulWidget {
  final AppUser user;
  final VoidCallback onLogout;
  final VoidCallback onOpenNotifications;

  const HodDashboard({
    super.key,
    required this.user,
    required this.onLogout,
    required this.onOpenNotifications,
  });

  @override
  State<HodDashboard> createState() => _HodDashboardState();
}

class _HodDashboardState extends State<HodDashboard> with SingleTickerProviderStateMixin {
  final _odService = ODService();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _odService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _odService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _openApprovalDialog(ODRequest req) {
    showDialog(
      context: context,
      builder: (ctx) => _HodDecisionDialog(request: req, odService: _odService),
    );
  }

  void _showSummaryDialog() {
    final all = _odService.allRequests;
    int count(bool Function(ODRequest) test) => all.where(test).length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('OD Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total requests: ${all.length}'),
            Text('Waiting for advisor: ${count((r) => r.isPendingAdvisor)}'),
            Text('Waiting for HOD: ${count((r) => r.isPendingHod)}'),
            Text('Approved: ${count((r) => r.isApproved)}'),
            Text('Rejected: ${count((r) => r.isRejected)}'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3350B0);
    const goldAccent = Color(0xFFD4A429);

    final all = _odService.allRequests;
    final forwardedToHod = all.where((r) => r.isPendingHod).toList();
    final approved = all.where((r) => r.isApproved).toList();
    final auditLogs = _odService.allAuditLogs;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FD),
      appBar: AppBar(
        backgroundColor: primaryBlue,
        elevation: 0,
        title: Row(
          children: [
            Image.asset(
              'assets/college_logo.png',
              width: 32,
              height: 32,
              errorBuilder: (_, __, ___) => const Icon(Icons.school, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SMVEC OD PORTAL', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                Text('HOD Executive Portal', style: TextStyle(fontSize: 11, color: Color(0xFFD1D5DB))),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.insights_outlined, color: Colors.white),
            tooltip: 'Summary',
            onPressed: _showSummaryDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: _odService.refresh,
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none_outlined, color: Colors.white),
            onPressed: widget.onOpenNotifications,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: widget.onLogout,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: goldAccent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFFD1D5DB),
          tabs: [
            Tab(text: 'Pending (${forwardedToHod.length})'),
            Tab(text: 'Approved (${approved.length})'),
            const Tab(text: 'Audit Trail'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Pending Decision (Forwarded from Advisors)
          _buildPendingTab(forwardedToHod, primaryBlue, goldAccent),
          // Tab 2: Approved Submissions & Results
          _buildApprovedTab(approved, primaryBlue, goldAccent),
          // Tab 3: Immutable Audit Trail
          _buildAuditTrailTab(auditLogs, primaryBlue),
        ],
      ),
    );
  }

  Widget _buildPendingTab(List<ODRequest> list, Color primaryBlue, Color goldAccent) {
    if (list.isEmpty) {
      if (_odService.isLoading) return const Center(child: CircularProgressIndicator());
      return Container(
        padding: const EdgeInsets.all(40),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_odService.lastError != null)
              Text(_odService.lastError!, style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C))),
            const Icon(Icons.check_circle_outline, size: 56, color: Color(0xFF10B981)),
            const SizedBox(height: 12),
            const Text('All caught up!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Text('No requests currently waiting for HOD final sanction.', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _odService.refresh,
      child: ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final req = list[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2563EB), width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(6)),
                      child: Text('Approved by ${req.advisorName}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8))),
                    ),
                    Text(req.id, style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(req.studentName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
                Text('Reg No: ${req.rollNumber} · ${yearLabel(req.year)} - Sec ${req.section}', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                const Divider(height: 20),
                Text(req.eventName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                const SizedBox(height: 4),
                Text(
                  '${req.eventType} · ${DateFormat('dd MMM yyyy').format(req.eventDate)} (${req.eventDay})',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
                ),
                const SizedBox(height: 8),
                Text(req.description, style: const TextStyle(fontSize: 12, color: Color(0xFF374151))),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFBBF7D0))),
                  child: Row(
                    children: [
                      const Icon(Icons.assignment_turned_in, size: 16, color: Color(0xFF15803D)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${req.advisorName}: "${req.advisorRemarks ?? "Recommended for approval"}"',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF166534)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => _openApprovalDialog(req),
                      child: const Text('Review Details'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
                      icon: const Icon(Icons.verified, size: 16),
                      label: const Text('Decide'),
                      onPressed: () => _openApprovalDialog(req),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
      ),
    );
  }

  Widget _buildApprovedTab(List<ODRequest> list, Color primaryBlue, Color goldAccent) {
    if (list.isEmpty) {
      return const Center(child: Text('No approved ODs yet.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final req = list[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD1FAE5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(req.studentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(6)),
                      child: const Text('OD Sanctioned ✓', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF065F46))),
                    ),
                  ],
                ),
                Text('Reg No: ${req.rollNumber} · ${yearLabel(req.year)} ${req.section} · Event: ${req.eventName}', style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563))),
                const SizedBox(height: 6),
                Text('Date: ${DateFormat('dd MMM yyyy').format(req.eventDate)} · ${req.eventType}', style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                if (req.resultStatus != 'PENDING') ...[
                  const Divider(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.emoji_events, size: 16, color: Color(0xFFD97706)),
                      const SizedBox(width: 6),
                      Text(
                        'Result: ${req.resultStatus} (${req.resultProjectName ?? ""})',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAuditTrailTab(List<AuditEntry> logs, Color primaryBlue) {
    if (logs.isEmpty) {
      return const Center(child: Text('No audit logs available.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: logs.length,
      itemBuilder: (ctx, i) {
        final log = logs[i];
        Color actionColor;
        switch (log.action) {
          case 'CREATED':
            actionColor = const Color(0xFF2563EB);
            break;
          case 'APPROVED_BY_ADVISOR':
            actionColor = const Color(0xFFD97706);
            break;
          case 'APPROVED':
          case 'APPROVED_BY_HOD':
            actionColor = const Color(0xFF059669);
            break;
          case 'REJECTED':
          case 'REJECTED_BY_ADVISOR':
          case 'REJECTED_BY_HOD':
            actionColor = const Color(0xFFDC2626);
            break;
          default:
            actionColor = Colors.grey;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: actionColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          log.action.replaceAll('_', ' '),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: actionColor),
                        ),
                        Text(
                          DateFormat('dd MMM, hh:mm a').format(log.timestamp),
                          style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'By: ${log.performedBy} [${log.role}]',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                    ),
                    Text(
                      log.details,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HodDecisionDialog extends StatefulWidget {
  final ODRequest request;
  final ODService odService;

  const _HodDecisionDialog({required this.request, required this.odService});

  @override
  State<_HodDecisionDialog> createState() => _HodDecisionDialogState();
}

class _HodDecisionDialogState extends State<_HodDecisionDialog> {
  final _remarksController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _decide(bool approve) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.odService.hodDecide(widget.request.id, approve: approve, remarks: _remarksController.text.trim());
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(
        content: Text(approve ? 'OD sanctioned. The student has been notified.' : 'OD request rejected.'),
        backgroundColor: approve ? const Color(0xFF059669) : null,
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.verified, color: Color(0xFF059669)),
          SizedBox(width: 8),
          Text('Final OD Sanction', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Student: ${req.studentName} (${req.rollNumber})', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${yearLabel(req.year)} - Sec ${req.section}', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            Text('Event: ${req.eventName}', style: const TextStyle(fontSize: 13, color: Color(0xFF3350B0))),
            Text('Category: ${req.eventType} · Date: ${DateFormat('dd MMM yyyy').format(req.eventDate)}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Text(req.description, style: const TextStyle(fontSize: 12, color: Color(0xFF374151))),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(6)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Class Advisor Recommendation:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF))),
                  Text('${req.advisorRemarks ?? "Recommended"} (${req.advisorName})', style: const TextStyle(fontSize: 11, color: Color(0xFF1E3A8A))),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text('HOD Remarks (optional):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _remarksController,
              maxLines: 2,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Enter comments...'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: _busy ? null : () => _decide(false),
          child: const Text('Reject'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
          onPressed: _busy ? null : () => _decide(true),
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Approve OD'),
        ),
      ],
    );
  }
}
