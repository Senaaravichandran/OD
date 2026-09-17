import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/od_request.dart';
import '../models/user.dart';
import '../services/od_service.dart';

class AdvisorDashboard extends StatefulWidget {
  final AppUser user;
  final VoidCallback onLogout;
  final VoidCallback onOpenNotifications;

  const AdvisorDashboard({
    super.key,
    required this.user,
    required this.onLogout,
    required this.onOpenNotifications,
  });

  @override
  State<AdvisorDashboard> createState() => _AdvisorDashboardState();
}

class _AdvisorDashboardState extends State<AdvisorDashboard> {
  final _odService = ODService();
  String _filter = 'ALL'; // 'ALL', 'PENDING', 'FORWARDED', 'REJECTED'

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
      builder: (ctx) => _AdvisorReviewDialog(request: req, advisorUser: widget.user, odService: _odService),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3350B0);
    const goldAccent = Color(0xFFD4A429);

    final allClassRequests = _odService.allRequests.where((r) => r.year == 3 && r.section == 'A').toList();

    List<ODRequest> filteredRequests;
    if (_filter == 'PENDING') {
      filteredRequests = allClassRequests.where((r) => r.status == 'PENDING_ADVISOR').toList();
    } else if (_filter == 'FORWARDED') {
      filteredRequests = allClassRequests.where((r) => r.status == 'FORWARDED_HOD' || r.status == 'APPROVED').toList();
    } else if (_filter == 'REJECTED') {
      filteredRequests = allClassRequests.where((r) => r.status == 'REJECTED_ADVISOR').toList();
    } else {
      filteredRequests = allClassRequests;
    }

    final pendingCount = allClassRequests.where((r) => r.status == 'PENDING_ADVISOR').length;

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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                BoxShadow(
                  color: primaryBlue.withOpacity(0.2),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: goldAccent,
                  child: const Icon(Icons.assignment_ind, color: Colors.white, size: 28),
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
                      const Text(
                        'Class Advisor · III Year - Section A',
                        style: TextStyle(fontSize: 13, color: Color(0xFFE0E7FF)),
                      ),
                      const Text(
                        'Department of Information Technology',
                        style: TextStyle(fontSize: 11, color: Color(0xFFFDE68A), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Action Queue Banner
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
                      'Action Needed: $pendingCount student submission${pendingCount > 1 ? "s" : ""} awaiting your review & recommendation.',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF92400E)),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All Requests (${allClassRequests.length})', 'ALL'),
                const SizedBox(width: 8),
                _buildFilterChip('Pending My Review ($pendingCount)', 'PENDING'),
                const SizedBox(width: 8),
                _buildFilterChip('Forwarded to HOD', 'FORWARDED'),
                const SizedBox(width: 8),
                _buildFilterChip('Rejected by Me', 'REJECTED'),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Submissions List
          if (filteredRequests.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              alignment: Alignment.center,
              child: const Text('No requests match this filter.', style: TextStyle(color: Color(0xFF6B7280))),
            )
          else
            ...filteredRequests.map((req) => _buildAdvisorCard(req, primaryBlue, goldAccent)),

          const SizedBox(height: 40),
        ],
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

  Widget _buildAdvisorCard(ODRequest req, Color primaryBlue, Color goldAccent) {
    Color statusColor;
    String statusLabel;

    switch (req.status) {
      case 'PENDING_ADVISOR':
        statusColor = const Color(0xFFD97706);
        statusLabel = 'Pending Your Review';
        break;
      case 'FORWARDED_HOD':
        statusColor = const Color(0xFF2563EB);
        statusLabel = 'Forwarded to HOD';
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

    final isPending = req.status == 'PENDING_ADVISOR';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isPending ? const Color(0xFFF59E0B) : const Color(0xFFE5E7EB), width: isPending ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
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
                  backgroundColor: primaryBlue.withOpacity(0.1),
                  child: Text(
                    req.studentName.substring(0, 1),
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
                        'Roll: ${req.rollNumber} · ${req.submissionType}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Text(
              req.eventName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
            ),
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
                OutlinedButton.icon(
                  icon: const Icon(Icons.description_outlined, size: 14),
                  label: const Text('Review & Details', style: TextStyle(fontSize: 12)),
                  onPressed: () => _openReviewModal(req),
                ),
                if (isPending) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryBlue,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    icon: const Icon(Icons.forward_to_inbox, size: 14),
                    label: const Text('Forward to HOD'),
                    onPressed: () => _openReviewModal(req),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Dialog for Reviewing, Forwarding, or Rejecting
class _AdvisorReviewDialog extends StatefulWidget {
  final ODRequest request;
  final AppUser advisorUser;
  final ODService odService;

  const _AdvisorReviewDialog({
    required this.request,
    required this.advisorUser,
    required this.odService,
  });

  @override
  State<_AdvisorReviewDialog> createState() => _AdvisorReviewDialogState();
}

class _AdvisorReviewDialogState extends State<_AdvisorReviewDialog> {
  final _remarksController = TextEditingController(text: 'Verified attendance and credentials. Recommended for approval.');

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3350B0);
    final req = widget.request;
    final isPending = req.status == 'PENDING_ADVISOR';

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.fact_check_outlined, color: primaryBlue),
          const SizedBox(width: 8),
          const Text('Advisor Review', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Student: ${req.studentName} (${req.rollNumber})', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Class: Year ${req.year} - Sec ${req.section} · ${req.department}', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
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
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(6)),
              child: Row(
                children: [
                  const Icon(Icons.attach_file, size: 16, color: Color(0xFF4B5563)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Attachment: ${req.attachmentName}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            if (isPending) ...[
              const SizedBox(height: 16),
              const Text('Advisor Remarks & Recommendation:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _remarksController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Enter attendance check, internal exam schedule notes...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (isPending) ...[
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              widget.odService.rejectByAdvisor(
                req.id,
                _remarksController.text.isEmpty ? 'Dates clash with internal assessments.' : _remarksController.text,
                widget.advisorUser.name,
              );
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request marked as Rejected.')));
            },
            child: const Text('Reject'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white),
            onPressed: () {
              widget.odService.forwardToHod(
                req.id,
                _remarksController.text,
                widget.advisorUser.name,
              );
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Successfully verified and forwarded to HOD!'),
                  backgroundColor: Color(0xFF059669),
                ),
              );
            },
            child: const Text('Forward to HOD'),
          ),
        ],
      ],
    );
  }
}
