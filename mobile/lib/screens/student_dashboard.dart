import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/od_request.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/od_service.dart';
import '../utils/validators.dart';

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

    // The server only returns this student's own requests.
    final myRequests = _odService.allRequests;

    final approvedCount = myRequests.where((r) => r.isApproved).length;
    final pendingCount = myRequests.where((r) => r.isPendingAdvisor || r.isPendingHod).length;

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
                  color: primaryBlue.withValues(alpha: 0.25),
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
                    widget.user.name.isEmpty ? '?' : widget.user.name.substring(0, 1).toUpperCase(),
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
                        'Reg No: ${widget.user.rollNumber ?? "-"} · ${yearLabel(widget.user.year ?? 0)} - Sec ${widget.user.section ?? "-"}',
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
              child: _odService.isLoading
                  ? const CircularProgressIndicator()
                  : const Text('No OD applications yet. Tap + to apply!'),
            )
          else
            ...myRequests.map((req) => _buildRequestCard(req, primaryBlue, goldAccent)),

          const SizedBox(height: 60),
        ],
        ),
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
      case 'APPROVED_BY_ADVISOR':
        statusColor = const Color(0xFF2563EB);
        statusLabel = 'Advisor Approved · Waiting for HOD';
        statusIcon = Icons.forward_to_inbox;
        break;
      case 'PENDING_ADVISOR':
        statusColor = const Color(0xFFD97706);
        statusLabel = 'Waiting for ${req.advisorName}';
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
            color: Colors.black.withValues(alpha: 0.03),
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
                    color: primaryBlue.withValues(alpha: 0.08),
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
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.assignment_ind_outlined, size: 14, color: Color(0xFF6B7280)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Advisor: ${req.advisorName}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                            ),
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
                    _buildStepDivider(!req.isPendingAdvisor),
                    _buildStepIcon(
                      2,
                      'Advisor Review',
                      true,
                      req.isPendingHod || req.isApproved || req.status == 'REJECTED_HOD',
                      isRejected: req.status == 'REJECTED_ADVISOR',
                    ),
                    _buildStepDivider(req.isApproved || req.status == 'REJECTED_HOD'),
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
                Expanded(
                  child: Row(
                    children: [
                      Icon(statusIcon, size: 16, color: statusColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          statusLabel,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor),
                        ),
                      ),
                    ],
                  ),
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

  List<AdvisorInfo>? _advisors;
  String? _advisorEmail;
  String? _advisorError;
  bool _submitting = false;

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
    _teamMemberControllers.add(TextEditingController(text: '${widget.user.name} (${widget.user.rollNumber ?? ""})'));
    _loadAdvisors();
  }

  @override
  void dispose() {
    _eventNameController.dispose();
    _descController.dispose();
    for (final c in _teamMemberControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAdvisors({bool force = false}) async {
    setState(() => _advisorError = null);
    try {
      final list = await widget.odService.fetchAdvisors(force: force);
      if (!mounted) return;
      // Put the student's own class advisor(s) first and pre-select when there is exactly one.
      final mine = list.where((a) => a.year == widget.user.year && a.section == widget.user.section).toList();
      final others = list.where((a) => !mine.contains(a)).toList();
      setState(() {
        _advisors = [...mine, ...others];
        if (_advisorEmail == null && mine.length == 1) _advisorEmail = mine.first.email;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _advisorError = e.message);
    }
  }

  void _addMember() {
    if (_teamMemberControllers.length < 5) {
      setState(() => _teamMemberControllers.add(TextEditingController()));
    }
  }

  void _removeMember(int index) {
    if (_teamMemberControllers.length > 1) {
      setState(() => _teamMemberControllers.removeAt(index).dispose());
    }
  }

  String _calculateDay(DateTime date) => DateFormat('EEEE').format(date);

  Future<void> _handleSubmit() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_advisorEmail == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Please select your Class Advisor')));
      return;
    }
    if (_eventNameController.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Please enter Event Name')));
      return;
    }
    if (_descController.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Please enter Description')));
      return;
    }

    final members = _submissionType == 'TEAM'
        ? _teamMemberControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList()
        : <String>[];

    setState(() => _submitting = true);
    try {
      await widget.odService.submitRequest(
        advisorEmail: _advisorEmail!,
        submissionType: _submissionType,
        teamMembers: members,
        eventType: _eventType,
        eventName: _eventNameController.text.trim(),
        eventDate: _eventDate,
        eventDay: _calculateDay(_eventDate),
        description: _descController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('OD Request submitted! Sent to your Class Advisor for review.'),
          backgroundColor: Color(0xFF059669),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent));
    }
  }

  Widget _buildAdvisorPicker() {
    if (_advisorError != null) {
      return Row(
        children: [
          Expanded(child: Text(_advisorError!, style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)))),
          TextButton(onPressed: () => _loadAdvisors(force: true), child: const Text('Retry')),
        ],
      );
    }
    final advisors = _advisors;
    if (advisors == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    if (advisors.isEmpty) {
      return const Text(
        'No class advisors have registered yet. Please ask your advisor to sign in to the app first.',
        style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: _advisorEmail,
      isExpanded: true,
      hint: const Text('Select your Class Advisor'),
      items: advisors
          .map((a) => DropdownMenuItem(
                value: a.email,
                child: Text(
                  '${a.name} · ${yearLabel(a.year)} ${a.section} (${a.batch})',
                  overflow: TextOverflow.ellipsis,
                ),
              ))
          .toList(),
      onChanged: (val) => setState(() => _advisorEmail = val),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.assignment_ind_outlined, size: 18),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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

            const Text('Class Advisor', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            _buildAdvisorPicker(),
            const SizedBox(height: 14),

            // Solo / Team Toggle
            const Text('Participation Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _submissionType == 'SOLO' ? primaryBlue.withValues(alpha: 0.08) : Colors.transparent,
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
                      backgroundColor: _submissionType == 'TEAM' ? primaryBlue.withValues(alpha: 0.08) : Colors.transparent,
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
                            hintText: 'Member ${idx + 1} Name & Register No',
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
              initialValue: _eventType,
              items: _eventTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (val) => setState(() => _eventType = val ?? _eventType),
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
                final today = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _eventDate,
                  firstDate: DateTime(today.year, today.month, today.day),
                  lastDate: today.add(const Duration(days: 180)),
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
                onPressed: _submitting ? null : _handleSubmit,
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Submit to Class Advisor', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
  bool _submitting = false;

  @override
  void dispose() {
    _projectNameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _submitting = true);
    try {
      await widget.odService.submitResult(
        widget.request.id,
        _projectNameCtrl.text.trim().isEmpty ? widget.request.eventName : _projectNameCtrl.text.trim(),
        _descCtrl.text.trim(),
        _resultStatus,
      );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Result submitted successfully!')));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent));
    }
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
                onPressed: _submitting ? null : _save,
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Event Results', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
