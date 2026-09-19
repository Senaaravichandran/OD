import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_config.dart';
import '../models/od_request.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/od_service.dart';
import '../utils/validators.dart';

class AdvisorDashboard extends StatefulWidget {
  final AppUser user;
  final VoidCallback onLogout;
  final VoidCallback onOpenNotifications;
  final Future<void> Function(AppUser user) onUserUpdated;

  const AdvisorDashboard({
    super.key,
    required this.user,
    required this.onLogout,
    required this.onOpenNotifications,
    required this.onUserUpdated,
  });

  @override
  State<AdvisorDashboard> createState() => _AdvisorDashboardState();
}

class _AdvisorDashboardState extends State<AdvisorDashboard> {
  final _odService = ODService();
  String _filter = 'ALL'; // 'ALL', 'PENDING', 'APPROVED', 'REJECTED'

  @override
  void initState() {
    super.initState();
    _odService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _odService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _openReviewModal(ODRequest req) {
    showDialog(
      context: context,
      builder: (ctx) => _AdvisorReviewDialog(request: req, odService: _odService),
    );
  }

  void _openEditClassDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _EditClassDialog(user: widget.user, odService: _odService, onSaved: widget.onUserUpdated),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3350B0);
    const goldAccent = Color(0xFFD4A429);

    // The server only returns requests where this staff member was chosen as Class Advisor.
    final allClassRequests = _odService.allRequests;

    List<ODRequest> filteredRequests;
    if (_filter == 'PENDING') {
      filteredRequests = allClassRequests.where((r) => r.isPendingAdvisor).toList();
    } else if (_filter == 'APPROVED') {
      filteredRequests = allClassRequests.where((r) => r.isPendingHod || r.isApproved || r.status == 'REJECTED_HOD').toList();
    } else if (_filter == 'REJECTED') {
      filteredRequests = allClassRequests.where((r) => r.status == 'REJECTED_ADVISOR').toList();
    } else {
      filteredRequests = allClassRequests;
    }

    final pendingCount = allClassRequests.where((r) => r.isPendingAdvisor).length;

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
                Text('Class Advisor Portal', style: TextStyle(fontSize: 11, color: Color(0xFFD1D5DB))),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_outlined, color: Colors.white),
            onPressed: widget.onOpenNotifications,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _odService.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_odService.lastError != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(8)),
                child: Text(_odService.lastError!, style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C))),
              ),

            // Class Banner
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E3A8A), Color(0xFF3350B0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: primaryBlue.withValues(alpha: 0.2), blurRadius: 14, offset: const Offset(0, 5)),
                ],
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 26,
                    backgroundColor: goldAccent,
                    child: Icon(Icons.assignment_ind, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.user.name,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Class Advisor · ${yearLabel(widget.user.year ?? 0)} - Section ${widget.user.section ?? "-"}',
                          style: const TextStyle(fontSize: 13, color: Color(0xFFE0E7FF)),
                        ),
                        Text(
                          'Batch ${widget.user.batch ?? "-"} · Information Technology',
                          style: const TextStyle(fontSize: 11, color: Color(0xFFFDE68A), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit class details',
                    icon: const Icon(Icons.edit_outlined, color: Colors.white),
                    onPressed: _openEditClassDialog,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (pendingCount > 0)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notification_important, color: Color(0xFFB45309), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Action Needed: $pendingCount student request${pendingCount > 1 ? "s" : ""} awaiting your review.',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF92400E)),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All Requests (${allClassRequests.length})', 'ALL'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Pending My Review ($pendingCount)', 'PENDING'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Approved by Me', 'APPROVED'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Rejected by Me', 'REJECTED'),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (filteredRequests.isEmpty)
              Container(
                padding: const EdgeInsets.all(40),
                alignment: Alignment.center,
                child: _odService.isLoading
                    ? const CircularProgressIndicator()
                    : const Text('No requests match this filter.', style: TextStyle(color: Color(0xFF6B7280))),
              )
            else
              ...filteredRequests.map((req) => _buildAdvisorCard(req, primaryBlue)),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String key) {
    final isSelected = _filter == key;
    const primaryBlue = Color(0xFF3350B0);

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: primaryBlue,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? Colors.white : const Color(0xFF4B5563),
      ),
      onSelected: (_) => setState(() => _filter = key),
    );
  }

  Widget _buildAdvisorCard(ODRequest req, Color primaryBlue) {
    Color statusColor;
    String statusLabel;

    switch (req.status) {
      case 'PENDING_ADVISOR':
        statusColor = const Color(0xFFD97706);
        statusLabel = 'Pending Your Review';
        break;
      case 'APPROVED_BY_ADVISOR':
        statusColor = const Color(0xFF2563EB);
        statusLabel = 'Waiting for HOD';
        break;
      case 'APPROVED':
        statusColor = const Color(0xFF059669);
        statusLabel = 'OD Sanctioned (HOD)';
        break;
      case 'REJECTED_ADVISOR':
        statusColor = const Color(0xFFDC2626);
        statusLabel = 'Rejected by You';
        break;
      case 'REJECTED_HOD':
        statusColor = const Color(0xFFDC2626);
        statusLabel = 'Rejected by HOD';
        break;
      default:
        statusColor = Colors.grey;
        statusLabel = req.status;
    }

    final isPending = req.isPendingAdvisor;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isPending ? const Color(0xFFF59E0B) : const Color(0xFFE5E7EB), width: isPending ? 1.5 : 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: primaryBlue.withValues(alpha: 0.1),
                  child: Text(
                    req.studentName.isEmpty ? '?' : req.studentName.substring(0, 1).toUpperCase(),
                    style: TextStyle(fontWeight: FontWeight.bold, color: primaryBlue),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        req.studentName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                      ),
                      Text(
                        'Reg No: ${req.rollNumber} · ${yearLabel(req.year)} ${req.section} · ${req.submissionType}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
                ),
              ],
            ),
            const Divider(height: 20),
            Text(req.eventName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(4)),
                  child: Text(req.eventType, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: primaryBlue)),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.calendar_today, size: 12, color: Color(0xFF6B7280)),
                const SizedBox(width: 4),
                Text(
                  '${DateFormat('dd MMM yyyy').format(req.eventDate)} (${req.eventDay})',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              req.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
            ),
            if (req.submissionType == 'TEAM' && req.teamMembers.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Team: ${req.teamMembers.join(", ")}',
                style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFF6B7280)),
              ),
            ],
            if (req.advisorRemarks != null) ...[
              const SizedBox(height: 8),
              Text('Your Remarks: ${req.advisorRemarks}', style: TextStyle(fontSize: 11, color: primaryBlue, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isPending)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryBlue,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    icon: const Icon(Icons.fact_check_outlined, size: 14),
                    label: const Text('Review'),
                    onPressed: () => _openReviewModal(req),
                  )
                else
                  OutlinedButton.icon(
                    icon: const Icon(Icons.description_outlined, size: 14),
                    label: const Text('Details', style: TextStyle(fontSize: 12)),
                    onPressed: () => _openReviewModal(req),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Dialog for reviewing, approving (forwarding to HOD), or rejecting.
class _AdvisorReviewDialog extends StatefulWidget {
  final ODRequest request;
  final ODService odService;

  const _AdvisorReviewDialog({required this.request, required this.odService});

  @override
  State<_AdvisorReviewDialog> createState() => _AdvisorReviewDialogState();
}

class _AdvisorReviewDialogState extends State<_AdvisorReviewDialog> {
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
      await widget.odService.advisorDecide(widget.request.id, approve: approve, remarks: _remarksController.text.trim());
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(
        content: Text(approve ? 'Approved and forwarded to HOD.' : 'Request rejected.'),
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
    const primaryBlue = Color(0xFF3350B0);
    final req = widget.request;
    final isPending = req.isPendingAdvisor;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.fact_check_outlined, color: primaryBlue),
          SizedBox(width: 8),
          Text('Advisor Review', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Student: ${req.studentName} (${req.rollNumber})', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Class: ${yearLabel(req.year)} - Sec ${req.section} · ${req.department}', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            Text(req.studentEmail, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            const Divider(),
            const SizedBox(height: 6),
            Text('Event: ${req.eventName}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('Category: ${req.eventType} · ${req.submissionType}', style: const TextStyle(fontSize: 12)),
            Text('Date: ${DateFormat('dd MMM yyyy').format(req.eventDate)} (${req.eventDay})', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            const Text('Details:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            Text(req.description, style: const TextStyle(fontSize: 12, color: Color(0xFF374151))),
            if (req.teamMembers.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text('Team Members:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ...req.teamMembers.map((m) => Text('• $m', style: const TextStyle(fontSize: 11))),
            ],
            if (!isPending && req.advisorRemarks != null) ...[
              const SizedBox(height: 10),
              Text('Your Remarks: ${req.advisorRemarks}', style: const TextStyle(fontSize: 12, color: primaryBlue)),
            ],
            if (req.hodRemarks != null) ...[
              const SizedBox(height: 6),
              Text('HOD Remarks: ${req.hodRemarks}', style: const TextStyle(fontSize: 12, color: Color(0xFF065F46))),
            ],
            if (isPending) ...[
              const SizedBox(height: 16),
              const Text('Remarks (optional):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _remarksController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Attendance check, internal exam clash, etc.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Close')),
        if (isPending) ...[
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: _busy ? null : () => _decide(false),
            child: const Text('Reject'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white),
            onPressed: _busy ? null : () => _decide(true),
            child: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Approve & Forward'),
          ),
        ],
      ],
    );
  }
}

// Lets a Class Advisor change the class (year / section / batch) they handle.
class _EditClassDialog extends StatefulWidget {
  final AppUser user;
  final ODService odService;
  final Future<void> Function(AppUser user) onSaved;

  const _EditClassDialog({required this.user, required this.odService, required this.onSaved});

  @override
  State<_EditClassDialog> createState() => _EditClassDialogState();
}

class _EditClassDialogState extends State<_EditClassDialog> {
  int? _year;
  String? _section;
  late final TextEditingController _batchController;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _year = AppConfig.years.contains(widget.user.year) ? widget.user.year : null;
    _section = AppConfig.sections.contains(widget.user.section) ? widget.user.section : null;
    _batchController = TextEditingController(text: widget.user.batch ?? '');
  }

  @override
  void dispose() {
    _batchController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final batchError = validateBatch(_batchController.text);
    if (_year == null || _section == null || batchError != null) {
      setState(() => _error = batchError ?? 'Select year and section.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await widget.odService.updateClass(year: _year!, section: _section!, batch: _batchController.text.trim());
      await widget.onSaved(updated);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Class Advisor Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _year,
              decoration: const InputDecoration(labelText: 'Year', border: OutlineInputBorder()),
              items: AppConfig.years.map((y) => DropdownMenuItem(value: y, child: Text(yearLabel(y)))).toList(),
              onChanged: (v) => setState(() => _year = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _section,
              decoration: const InputDecoration(labelText: 'Section', border: OutlineInputBorder()),
              items: AppConfig.sections.map((s) => DropdownMenuItem(value: s, child: Text('Sec $s'))).toList(),
              onChanged: (v) => setState(() => _section = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _batchController,
              maxLength: 9,
              decoration: const InputDecoration(
                labelText: 'Batch',
                hintText: '2023-2027',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C))),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
