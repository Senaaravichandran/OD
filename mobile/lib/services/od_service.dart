import 'package:flutter/foundation.dart';
import '../models/od_request.dart';

class AuditEntry {
  final String id;
  final String requestId;
  final String action; // 'CREATED', 'FORWARDED', 'APPROVED', 'REJECTED'
  final String performedBy;
  final String role;
  final String details;
  final DateTime timestamp;

  AuditEntry({
    required this.id,
    required this.requestId,
    required this.action,
    required this.performedBy,
    required this.role,
    required this.details,
    required this.timestamp,
  });
}

class AppNotification {
  final String id;
  final String title;
  final String message;
  final String targetRole; // 'ALL', 'STUDENT', 'ADVISOR', 'HOD'
  final String? targetRollNumber;
  final DateTime timestamp;
  bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.targetRole,
    this.targetRollNumber,
    required this.timestamp,
    this.isRead = false,
  });
}

class ODService extends ChangeNotifier {
  static final ODService _instance = ODService._internal();
  factory ODService() => _instance;

  final List<ODRequest> _requests = [];
  final List<AuditEntry> _auditLogs = [];
  final List<AppNotification> _notifications = [];

  ODService._internal() {
    _seedInitialData();
  }

  List<ODRequest> get allRequests => List.unmodifiable(_requests);
  List<AuditEntry> get allAuditLogs => List.unmodifiable(_auditLogs);
  List<AppNotification> get allNotifications => List.unmodifiable(_notifications);

  void _seedInitialData() {
    final now = DateTime.now();

    final req1 = ODRequest(
      id: 'OD-2026-001',
      studentName: 'Aravindhan S',
      rollNumber: '21IT101',
      department: 'Information Technology',
      year: 3,
      section: 'A',
      submissionType: 'TEAM',
      teamMembers: ['Aravindhan S (21IT101)', 'Priya K (21IT102)', 'Rahul M (21IT103)'],
      eventType: 'Hackathon',
      eventName: 'Smart India Hackathon 2026 (Grand Finale)',
      eventDate: now.add(const Duration(days: 3)),
      eventDay: 'Saturday',
      description: 'National level hackathon hosted by AICTE & Ministry of Education. Our team qualified for the hardware edition in Bengaluru.',
      status: 'APPROVED',
      advisorRemarks: 'Verified student academic standing (CGPA > 8.5) and attendance (> 85%). Highly recommended for college representation.',
      advisorName: 'Dr. K. Senthil (Advisor IT-III-A)',
      advisorTimestamp: now.subtract(const Duration(days: 2)),
      hodRemarks: 'Approved for 3 days OD with travel allowance consideration. Best wishes for the team!',
      hodName: 'Dr. R. RAJU (HOD/IT)',
      hodTimestamp: now.subtract(const Duration(days: 1)),
      attachmentName: 'SIH_Shortlist_Letter.pdf',
      createdAt: now.subtract(const Duration(days: 3)),
    );

    final req2 = ODRequest(
      id: 'OD-2026-002',
      studentName: 'Karthik R',
      rollNumber: '21IT115',
      department: 'Information Technology',
      year: 3,
      section: 'A',
      submissionType: 'SOLO',
      teamMembers: [],
      eventType: 'Internship',
      eventName: 'TCS iON Industry Training on Cloud Computing',
      eventDate: now.add(const Duration(days: 7)),
      eventDay: 'Friday',
      description: 'Selected for 2-week hands-on industrial immersion on AWS and DevSecOps at TCS Siruseri campus.',
      status: 'FORWARDED_HOD',
      advisorRemarks: 'Offer letter verified with TCS HR portal. Academic schedule checked. Forwarded for HOD clearance.',
      advisorName: 'Dr. K. Senthil (Advisor IT-III-A)',
      advisorTimestamp: now.subtract(const Duration(hours: 4)),
      attachmentName: 'TCS_Selection_Email.pdf',
      createdAt: now.subtract(const Duration(days: 1)),
    );

    final req3 = ODRequest(
      id: 'OD-2026-003',
      studentName: 'Sneha M',
      rollNumber: '21IT142',
      department: 'Information Technology',
      year: 3,
      section: 'A',
      submissionType: 'TEAM',
      teamMembers: ['Sneha M (21IT142)', 'Divya S (21IT143)'],
      eventType: 'Paper Presentation',
      eventName: 'IEEE International Conference on AI & IoT (ICAIoT 2026)',
      eventDate: now.add(const Duration(days: 12)),
      eventDay: 'Wednesday',
      description: 'Our research paper titled "Edge AI for Predictive Crop Irrigation" has been accepted for oral presentation in Pondicherry University.',
      status: 'PENDING_ADVISOR',
      attachmentName: 'IEEE_Acceptance_Notice.pdf',
      createdAt: now.subtract(const Duration(hours: 2)),
    );

    _requests.addAll([req1, req2, req3]);

    _auditLogs.addAll([
      AuditEntry(
        id: 'AUD-1',
        requestId: 'OD-2026-001',
        action: 'CREATED',
        performedBy: 'Aravindhan S (21IT101)',
        role: 'STUDENT',
        details: 'Submitted OD request for Smart India Hackathon',
        timestamp: now.subtract(const Duration(days: 3)),
      ),
      AuditEntry(
        id: 'AUD-2',
        requestId: 'OD-2026-001',
        action: 'FORWARDED',
        performedBy: 'Dr. K. Senthil',
        role: 'ADVISOR',
        details: 'Class Advisor reviewed and forwarded to HOD with recommendation',
        timestamp: now.subtract(const Duration(days: 2)),
      ),
      AuditEntry(
        id: 'AUD-3',
        requestId: 'OD-2026-001',
        action: 'APPROVED',
        performedBy: 'Dr. R. RAJU',
        role: 'HOD',
        details: 'HOD granted final OD approval with digital sign',
        timestamp: now.subtract(const Duration(days: 1)),
      ),
    ]);

    _notifications.addAll([
      AppNotification(
        id: 'NOTIF-1',
        title: 'OD Approved',
        message: 'Your OD request for Smart India Hackathon has been APPROVED by HOD Dr. R. RAJU.',
        targetRole: 'STUDENT',
        targetRollNumber: '21IT101',
        timestamp: now.subtract(const Duration(days: 1)),
      ),
      AppNotification(
        id: 'NOTIF-2',
        title: 'New OD Request to Review 📋',
        message: 'Sneha M (21IT142) submitted an OD request for IEEE ICAIoT 2026.',
        targetRole: 'ADVISOR',
        timestamp: now.subtract(const Duration(hours: 2)),
      ),
      AppNotification(
        id: 'NOTIF-3',
        title: 'OD Forwarded for Decision ⚡',
        message: 'Advisor Dr. K. Senthil forwarded TCS Internship request for Karthik R (21IT115).',
        targetRole: 'HOD',
        timestamp: now.subtract(const Duration(hours: 4)),
      ),
    ]);
  }

  // Student Submits
  ODRequest submitRequest({
    required String studentName,
    required String rollNumber,
    required int year,
    required String section,
    required String submissionType,
    required List<String> teamMembers,
    required String eventType,
    required String eventName,
    required DateTime eventDate,
    required String eventDay,
    required String description,
    required String attachmentName,
  }) {
    final now = DateTime.now();
    final newId = 'OD-${now.year}-${(_requests.length + 1).toString().padLeft(3, '0')}';

    final req = ODRequest(
      id: newId,
      studentName: studentName,
      rollNumber: rollNumber,
      year: year,
      section: section,
      submissionType: submissionType,
      teamMembers: teamMembers,
      eventType: eventType,
      eventName: eventName,
      eventDate: eventDate,
      eventDay: eventDay,
      description: description,
      status: 'PENDING_ADVISOR',
      attachmentName: attachmentName,
      createdAt: now,
    );

    _requests.insert(0, req);

    _auditLogs.insert(0, AuditEntry(
      id: 'AUD-${now.millisecondsSinceEpoch}',
      requestId: newId,
      action: 'CREATED',
      performedBy: '$studentName ($rollNumber)',
      role: 'STUDENT',
      details: 'Created OD request for $eventName',
      timestamp: now,
    ));

    _notifications.insert(0, AppNotification(
      id: 'NOTIF-${now.millisecondsSinceEpoch}',
      title: 'New Request from $studentName',
      message: '$studentName submitted OD for $eventName ($eventType). Please review.',
      targetRole: 'ADVISOR',
      timestamp: now,
    ));

    notifyListeners();
    return req;
  }

  // Advisor Forwards to HOD
  bool forwardToHod(String requestId, String remarks, String advisorName) {
    final idx = _requests.indexWhere((r) => r.id == requestId);
    if (idx == -1) return false;

    final now = DateTime.now();
    final req = _requests[idx];
    req.status = 'FORWARDED_HOD';
    req.advisorRemarks = remarks;
    req.advisorName = advisorName;
    req.advisorTimestamp = now;

    _auditLogs.insert(0, AuditEntry(
      id: 'AUD-${now.millisecondsSinceEpoch}',
      requestId: requestId,
      action: 'FORWARDED',
      performedBy: advisorName,
      role: 'ADVISOR',
      details: 'Reviewed and forwarded to HOD with remarks: $remarks',
      timestamp: now,
    ));

    _notifications.insert(0, AppNotification(
      id: 'NOTIF-HOD-${now.millisecondsSinceEpoch}',
      title: 'Request Forwarded by Advisor',
      message: '$advisorName forwarded ${req.studentName}\'s request for ${req.eventName}.',
      targetRole: 'HOD',
      timestamp: now,
    ));

    _notifications.insert(0, AppNotification(
      id: 'NOTIF-STU-${now.millisecondsSinceEpoch}',
      title: 'Advisor Reviewed Your Request ✅',
      message: 'Your OD request for ${req.eventName} was approved by Class Advisor and forwarded to HOD.',
      targetRole: 'STUDENT',
      targetRollNumber: req.rollNumber,
      timestamp: now,
    ));

    notifyListeners();
    return true;
  }

  // Advisor Rejects
  bool rejectByAdvisor(String requestId, String remarks, String advisorName) {
    final idx = _requests.indexWhere((r) => r.id == requestId);
    if (idx == -1) return false;

    final now = DateTime.now();
    final req = _requests[idx];
    req.status = 'REJECTED_ADVISOR';
    req.advisorRemarks = remarks;
    req.advisorName = advisorName;
    req.advisorTimestamp = now;

    _auditLogs.insert(0, AuditEntry(
      id: 'AUD-${now.millisecondsSinceEpoch}',
      requestId: requestId,
      action: 'REJECTED_BY_ADVISOR',
      performedBy: advisorName,
      role: 'ADVISOR',
      details: 'Rejected by Class Advisor: $remarks',
      timestamp: now,
    ));

    _notifications.insert(0, AppNotification(
      id: 'NOTIF-STU-${now.millisecondsSinceEpoch}',
      title: 'OD Request Not Approved ⚠️',
      message: 'Class Advisor did not approve your OD request for ${req.eventName}. Reason: $remarks',
      targetRole: 'STUDENT',
      targetRollNumber: req.rollNumber,
      timestamp: now,
    ));

    notifyListeners();
    return true;
  }

  // HOD Approves
  bool approveByHod(String requestId, String remarks, String hodName) {
    final idx = _requests.indexWhere((r) => r.id == requestId);
    if (idx == -1) return false;

    final now = DateTime.now();
    final req = _requests[idx];
    req.status = 'APPROVED';
    req.hodRemarks = remarks.isNotEmpty ? remarks : 'Officially sanctioned by Head of Department.';
    req.hodName = hodName;
    req.hodTimestamp = now;

    _auditLogs.insert(0, AuditEntry(
      id: 'AUD-${now.millisecondsSinceEpoch}',
      requestId: requestId,
      action: 'APPROVED_BY_HOD',
      performedBy: hodName,
      role: 'HOD',
      details: 'HOD granted final On-Duty approval: ${req.hodRemarks}',
      timestamp: now,
    ));

    _notifications.insert(0, AppNotification(
      id: 'NOTIF-STU-${now.millisecondsSinceEpoch}',
      title: '🎉 OD Granted by HOD!',
      message: 'Your OD request for ${req.eventName} has been approved by HOD. You can now download the OD slip and submit post-event results later.',
      targetRole: 'STUDENT',
      targetRollNumber: req.rollNumber,
      timestamp: now,
    ));

    notifyListeners();
    return true;
  }

  // HOD Rejects
  bool rejectByHod(String requestId, String remarks, String hodName) {
    final idx = _requests.indexWhere((r) => r.id == requestId);
    if (idx == -1) return false;

    final now = DateTime.now();
    final req = _requests[idx];
    req.status = 'REJECTED_HOD';
    req.hodRemarks = remarks;
    req.hodName = hodName;
    req.hodTimestamp = now;

    _auditLogs.insert(0, AuditEntry(
      id: 'AUD-${now.millisecondsSinceEpoch}',
      requestId: requestId,
      action: 'REJECTED_BY_HOD',
      performedBy: hodName,
      role: 'HOD',
      details: 'Rejected by HOD: $remarks',
      timestamp: now,
    ));

    _notifications.insert(0, AppNotification(
      id: 'NOTIF-STU-${now.millisecondsSinceEpoch}',
      title: 'OD Request Denied by HOD',
      message: 'Your OD request for ${req.eventName} was rejected by HOD. Reason: $remarks',
      targetRole: 'STUDENT',
      targetRollNumber: req.rollNumber,
      timestamp: now,
    ));

    notifyListeners();
    return true;
  }

  // Post Event Result Submission
  bool submitResult(String requestId, String projectName, String desc, String resultStatus, String certName) {
    final idx = _requests.indexWhere((r) => r.id == requestId);
    if (idx == -1) return false;

    final now = DateTime.now();
    final req = _requests[idx];
    req.resultStatus = resultStatus;
    req.resultProjectName = projectName;
    req.resultDescription = desc;
    req.resultCertificateName = certName;

    _auditLogs.insert(0, AuditEntry(
      id: 'AUD-${now.millisecondsSinceEpoch}',
      requestId: requestId,
      action: 'RESULT_SUBMITTED',
      performedBy: req.studentName,
      role: 'STUDENT',
      details: 'Post-event result submitted: $resultStatus for $projectName',
      timestamp: now,
    ));

    notifyListeners();
    return true;
  }
}
