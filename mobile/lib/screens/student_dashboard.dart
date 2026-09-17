import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/od_request.dart';
import '../models/user.dart';
import '../services/od_service.dart';

class StudentDashboard extends StatefulWidget {
  final AppUser user;
  final VoidCallback onLogout;
  final VoidCallback onOpenNotifications;

  const StudentDashboard({
    super.key,
    required this.user,
    required this.onLogout,
    required this.onOpenNotifications,
  });

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  final _odService = ODService();

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

  void _openNewODModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NewODSheet(user: widget.user, odService: _odService),
    );
  }

  void _openResultModal(ODRequest request) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ResultSubmissionSheet(request: request, odService: _odService),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3350B0);
    const goldAccent = Color(0xFFD4A429);

    final myRequests = _odService.allRequests
        .where((r) => r.rollNumber == widget.user.rollNumber || r.studentName == widget.user.name)
        .toList();

    final approvedCount = myRequests.where((r) => r.status == 'APPROVED').length;
    final pendingCount = myRequests.where((r) => r.status == 'PENDING_ADVISOR' || r.status == 'FORWARDED_HOD').length;

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
                Text('Student Dashboard', style: TextStyle(fontSize: 11, color: Color(0xFFD1D5DB))),
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
          // Profile Banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3350B0), Color(0xFF1E3A8A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: primaryBlue.withOpacity(0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: goldAccent,
                  child: Text(
                    widget.user.name.substring(0, 1),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.user.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Roll: ${widget.user.rollNumber ?? "21IT101"} · Year ${widget.user.year ?? 3} - Sec ${widget.user.section ?? "A"}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFFE0E7FF)),
                      ),
                      Text(
                        widget.user.department,
                        style: TextStyle(fontSize: 12, color: goldAccent, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Quick Stats
          Row(
            children: [
              _buildStatChip('Total Requests', '${myRequests.length}', Icons.folder_outlined, const Color(0xFF4B5563)),
              const SizedBox(width: 10),
              _buildStatChip('Under Review', '$pendingCount', Icons.hourglass_top, const Color(0xFFD97706)),
              const SizedBox(width: 10),
              _buildStatChip('OD Approved', '$approvedCount', Icons.check_circle_outline, const Color(0xFF059669)),
            ],
          ),

          const SizedBox(height: 24),

          // Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My OD Applications',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1F2937)),
              ),
              Text(
                '${myRequests.length} Found',
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (myRequests.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: const Text('No OD applications yet. Tap + to apply!'),
            )
          else
            ...myRequests.map((req) => _buildRequestCard(req, primaryBlue, goldAccent)),

          const SizedBox(height: 60),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Apply OD Request', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: _openNewODModal,
      ),
    );
  }

  Widget _buildStatChip(String title, String count, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(count, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            Text(title, style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(ODRequest req, Color primaryBlue, Color goldAccent) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (req.status) {
      case 'APPROVED':
        statusColor = const Color(0xFF059669);
        statusLabel = 'HOD Approved ✓';
        statusIcon = Icons.verified;
        break;
      case 'FORWARDED_HOD':
        statusColor = const Color(0xFF2563EB);
        statusLabel = 'Forwarded to HOD';
        statusIcon = Icons.forward_to_inbox;
        break;
      case 'PENDING_ADVISOR':
        statusColor = const Color(0xFFD97706);
        statusLabel = 'Under Advisor Review';
        statusIcon = Icons.access_time;
        break;
      case 'REJECTED_ADVISOR':
      case 'REJECTED_HOD':
        statusColor = const Color(0xFFDC2626);
        statusLabel = 'Rejected ✕';
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.grey;
        statusLabel = req.status;
        statusIcon = Icons.info;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryBlue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.event_note, color: primaryBlue, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              req.eventType.toUpperCase(),
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: primaryBlue),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: req.submissionType == 'TEAM' ? const Color(0xFFFEF3C7) : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              req.submissionType,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: req.submissionType == 'TEAM' ? const Color(0xFFB45309) : const Color(0xFF4B5563),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            req.id,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        req.eventName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1F2937)),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.calendar_month, size: 14, color: Color(0xFF6B7280)),
                          const SizedBox(width: 4),
                          Text(
                            '${DateFormat('MMM dd, yyyy').format(req.eventDate)} · ${req.eventDay}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 3-Step Approval Workflow Stepper
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'APPROVAL WORKFLOW TRACKER',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildStepIcon(1, 'Submitted', true, true),
                    _buildStepDivider(req.status != 'PENDING_ADVISOR'),
                    _buildStepIcon(
                      2,
                      'Advisor Review',
                      req.status != 'PENDING_ADVISOR' || req.status == 'REJECTED_ADVISOR',
                      req.status == 'FORWARDED_HOD' || req.status == 'APPROVED',
                      isRejected: req.status == 'REJECTED_ADVISOR',
                    ),
                    _buildStepDivider(req.status == 'APPROVED'),
                    _buildStepIcon(
                      3,
                      'HOD Sanction',
                      req.status == 'APPROVED' || req.status == 'REJECTED_HOD',
                      req.status == 'APPROVED',
                      isRejected: req.status == 'REJECTED_HOD',
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Remarks If Any
          if (req.advisorRemarks != null || req.hodRemarks != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (req.advisorRemarks != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.comment, size: 14, color: Color(0xFF2563EB)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Advisor: ${req.advisorRemarks}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF1E40AF)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (req.hodRemarks != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.verified, size: 14, color: Color(0xFF059669)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'HOD: ${req.hodRemarks}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF065F46)),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

          // Footer Action
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(statusIcon, size: 16, color: statusColor),
                    const SizedBox(width: 6),
                    Text(
                      statusLabel,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor),
                    ),
                  ],
                ),
                if (req.status == 'APPROVED')
                  if (req.resultStatus != 'PENDING')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Text(
                        'Result: ${req.resultStatus}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF92400E)),
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: goldAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.emoji_events, size: 14),
                      label: const Text('Submit Result'),
                      onPressed: () => _openResultModal(req),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIcon(int step, String label, bool active, bool completed, {bool isRejected = false}) {
    Color bg;
    Widget iconWidget;

    if (isRejected) {
      bg = const Color(0xFFEF4444);
      iconWidget = const Icon(Icons.close, size: 12, color: Colors.white);
    } else if (completed) {
      bg = const Color(0xFF10B981);
      iconWidget = const Icon(Icons.check, size: 12, color: Colors.white);
    } else if (active) {
      bg = const Color(0xFF3350B0);
      iconWidget = Text('$step', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white));
    } else {
      bg = const Color(0xFFE5E7EB);
      iconWidget = Text('$step', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF)));
    }

    return Expanded(
      child: Column(
        children: [
          CircleAvatar(radius: 10, backgroundColor: bg, child: iconWidget),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: isRejected
                  ? const Color(0xFFEF4444)
                  : active
                      ? const Color(0xFF1F2937)
                      : const Color(0xFF9CA3AF),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStepDivider(bool active) {
    return Container(
      width: 24,
      height: 2,
      margin: const EdgeInsets.only(bottom: 14),
      color: active ? const Color(0xFF10B981) : const Color(0xFFE5E7EB),
    );
  }
}

// Modal for Creating New OD Request
class _NewODSheet extends StatefulWidget {
  final AppUser user;
  final ODService odService;

  const _NewODSheet({required this.user, required this.odService});

  @override
  State<_NewODSheet> createState() => _NewODSheetState();
}

class _NewODSheetState extends State<_NewODSheet> {
  String _submissionType = 'SOLO';
  String _eventType = 'Hackathon';
  final _eventNameController = TextEditingController();
  final _descController = TextEditingController();
  final List<TextEditingController> _teamMemberControllers = [];
  DateTime _eventDate = DateTime.now().add(const Duration(days: 3));

  final List<String> _eventTypes = [
    'Hackathon',
    'Internship',
    'Paper Presentation',
    'Workshop',
    'Symposium',
    'Sports',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    _teamMemberControllers.add(TextEditingController(text: '${widget.user.name} (${widget.user.rollNumber ?? "21IT101"})'));
  }

  void _addMember() {
    if (_teamMemberControllers.length < 5) {
      setState(() {
        _teamMemberControllers.add(TextEditingController());
      });
    }
  }

  void _removeMember(int index) {
    if (_teamMemberControllers.length > 1) {
      setState(() {
        _teamMemberControllers.removeAt(index);
      });
    }
  }

  String _calculateDay(DateTime date) {
    return DateFormat('EEEE').format(date);
  }

  void _handleSubmit() {
    if (_eventNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter Event Name')));
      return;
    }
    if (_descController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter Description')));
      return;
    }

    final members = _submissionType == 'TEAM'
        ? _teamMemberControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList()
        : <String>[];

    widget.odService.submitRequest(
      studentName: widget.user.name,
      rollNumber: widget.user.rollNumber ?? '21IT101',
      year: widget.user.year ?? 3,
      section: widget.user.section ?? 'A',
      submissionType: _submissionType,
      teamMembers: members,
      eventType: _eventType,
      eventName: _eventNameController.text.trim(),
      eventDate: _eventDate,
      eventDay: _calculateDay(_eventDate),
      description: _descController.text.trim(),
      attachmentName: 'Event_Proof_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('OD Request submitted! Sent to Class Advisor for initial review.'),
        backgroundColor: Color(0xFF059669),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3350B0);

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Create On-Duty Request',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(),
            const SizedBox(height: 12),

            // Solo / Team Toggle
            const Text('Participation Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _submissionType == 'SOLO' ? primaryBlue.withOpacity(0.08) : Colors.transparent,
                      side: BorderSide(color: _submissionType == 'SOLO' ? primaryBlue : const Color(0xFFD1D5DB), width: 1.5),
                    ),
                    icon: const Icon(Icons.person, size: 18),
                    label: const Text('Solo'),
                    onPressed: () => setState(() => _submissionType = 'SOLO'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _submissionType == 'TEAM' ? primaryBlue.withOpacity(0.08) : Colors.transparent,
                      side: BorderSide(color: _submissionType == 'TEAM' ? primaryBlue : const Color(0xFFD1D5DB), width: 1.5),
                    ),
                    icon: const Icon(Icons.groups, size: 18),
                    label: const Text('Team (Max 5)'),
                    onPressed: () => setState(() => _submissionType = 'TEAM'),
                  ),
                ),
              ],
            ),

            if (_submissionType == 'TEAM') ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Team Members', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Member', style: TextStyle(fontSize: 12)),
                    onPressed: _addMember,
                  ),
                ],
              ),
              ..._teamMemberControllers.asMap().entries.map((entry) {
                final idx = entry.key;
                final ctrl = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: ctrl,
                          decoration: InputDecoration(
                            hintText: 'Member ${idx + 1} Name & Roll No',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      if (idx > 0)
                        IconButton(
                          icon: const Icon(Icons.remove_circle, color: Colors.red),
                          onPressed: () => _removeMember(idx),
                        ),
                    ],
                  ),
                );
              }),
            ],

            const SizedBox(height: 14),
            const Text('Event Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _eventType,
              items: _eventTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (val) => setState(() => _eventType = val!),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),

            const SizedBox(height: 14),
            const Text('Event Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _eventNameController,
              decoration: InputDecoration(
                hintText: 'e.g. Smart India Hackathon / TCS Placement Drive',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),

            const SizedBox(height: 14),
            const Text('Event Date', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _eventDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 180)),
                );
                if (picked != null) setState(() => _eventDate = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD1D5DB)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${DateFormat('dd MMM yyyy').format(_eventDate)} (${_calculateDay(_eventDate)})',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const Icon(Icons.calendar_today, size: 18, color: primaryBlue),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),
            const Text('Description / Purpose', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Provide details about the event, venue, and relevance...',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _handleSubmit,
                child: const Text('Submit for Advisor Review', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Modal for Post-Event Result Submission
class _ResultSubmissionSheet extends StatefulWidget {
  final ODRequest request;
  final ODService odService;

  const _ResultSubmissionSheet({required this.request, required this.odService});

  @override
  State<_ResultSubmissionSheet> createState() => _ResultSubmissionSheetState();
}

class _ResultSubmissionSheetState extends State<_ResultSubmissionSheet> {
  String _resultStatus = 'WON';
  final _projectNameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3350B0);

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Submit Post-Event Result', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            Text('Event: ${widget.request.eventName}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),

            const Text('Result Status', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Won 🏆'),
                  selected: _resultStatus == 'WON',
                  onSelected: (_) => setState(() => _resultStatus = 'WON'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Participated 📜'),
                  selected: _resultStatus == 'PARTICIPATION',
                  onSelected: (_) => setState(() => _resultStatus = 'PARTICIPATION'),
                ),
              ],
            ),
            const SizedBox(height: 14),

            const Text('Project / Presentation Title', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _projectNameCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. AI-Powered Smart Solar Tracker',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 14),

            const Text('Achievement Summary', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Describe prizes won, certificate awarded, feedback received...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white),
                onPressed: () {
                  widget.odService.submitResult(
                    widget.request.id,
                    _projectNameCtrl.text.isEmpty ? widget.request.eventName : _projectNameCtrl.text,
                    _descCtrl.text,
                    _resultStatus,
                    'Certificate_${widget.request.id}.pdf',
                  );
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Result submitted successfully! Saved in college records.')),
                  );
                },
                child: const Text('Save Event Results', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
