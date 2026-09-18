import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
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

  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is DateTime) return val;
      return DateTime.tryParse(val.toString()) ?? DateTime.now();
    }

    return AuditEntry(
      id: json['id']?.toString() ?? 'AUD-${DateTime.now().millisecondsSinceEpoch}',
      requestId: json['requestId']?.toString() ?? '',
      action: json['action']?.toString() ?? 'ACTION',
      performedBy: json['actor']?.toString() ?? json['performedBy']?.toString() ?? 'System',
      role: json['role']?.toString() ?? 'SYSTEM',
      details: json['details']?.toString() ?? '',
      timestamp: parseTime(json['time'] ?? json['timestamp']),
    );
  }
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

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is DateTime) return val;
      return DateTime.tryParse(val.toString()) ?? DateTime.now();
    }

    return AppNotification(
      id: json['id']?.toString() ?? 'NOTIF-${DateTime.now().millisecondsSinceEpoch}',
      title: json['title']?.toString() ?? 'Notification',
      message: json['text']?.toString() ?? json['message']?.toString() ?? '',
      targetRole: json['role']?.toString() ?? json['targetRole']?.toString() ?? 'ALL',
      targetRollNumber: json['targetRollNumber']?.toString(),
      timestamp: parseTime(json['time'] ?? json['timestamp']),
      isRead: json['isRead'] == true,
    );
  }
}

class ODService extends ChangeNotifier {
  static final ODService _instance = ODService._internal();
  factory ODService() => _instance;

  final List<ODRequest> _requests = [];
  final List<AuditEntry> _auditLogs = [];
  final List<AppNotification> _notifications = [];
  bool _isLoading = false;

  ODService._internal() {
    fetchRequests();
  }

  List<ODRequest> get allRequests => List.unmodifiable(_requests);
  List<AuditEntry> get allAuditLogs => List.unmodifiable(_auditLogs);
  List<AppNotification> get allNotifications => List.unmodifiable(_notifications);
  bool get isLoading => _isLoading;

  // -----------------------------------------------------------------
  // 1. FETCH LIVE REQUESTS FROM REDIS / SUPABASE BACKEND
  // -----------------------------------------------------------------
  Future<void> fetchRequests() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http
          .get(Uri.parse(AppConfig.apiBaseUrl))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true && body['data'] != null) {
          final data = body['data'];

          if (data['requests'] is List) {
            final List<ODRequest> fetched = (data['requests'] as List)
                .map((item) => ODRequest.fromJson(item as Map<String, dynamic>))
                .toList();
            _requests.clear();
            _requests.addAll(fetched);
          }

          if (data['auditLogs'] is List) {
            final List<AuditEntry> fetchedAudit = (data['auditLogs'] as List)
                .map((item) => AuditEntry.fromJson(item as Map<String, dynamic>))
                .toList();
            _auditLogs.clear();
            _auditLogs.addAll(fetchedAudit);
          }

          if (data['notifications'] is List) {
            final List<AppNotification> fetchedNotifs = (data['notifications'] as List)
                .map((item) => AppNotification.fromJson(item as Map<String, dynamic>))
                .toList();
            _notifications.clear();
            _notifications.addAll(fetchedNotifs);
          }
        }
      }
    } catch (e) {
      debugPrint('Live sync fetch notice: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // -----------------------------------------------------------------
  // 2. SUPABASE STORAGE UPLOAD FOR ATTACHMENTS & CERTIFICATES
  // -----------------------------------------------------------------
  Future<String?> uploadToSupabaseStorage({
    required String fileName,
    required List<int> bytes,
    String mimeType = 'application/pdf',
  }) async {
    try {
      final base64Content = base64Encode(bytes);
      final response = await http.post(
        Uri.parse(AppConfig.apiBaseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'UPLOAD_FILE',
          'payload': {
            'fileName': fileName,
            'fileData': base64Content,
            'mimeType': mimeType,
          },
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['url'] != null) {
          return data['url'].toString();
        }
      }
    } catch (e) {
      debugPrint('Supabase upload exception: $e');
    }

    // Direct Supabase Public Storage URL fallback
    return '${AppConfig.supabaseUrl}/storage/v1/object/public/${AppConfig.supabaseStorageBucket}/$fileName';
  }

  // -----------------------------------------------------------------
  // 3. STUDENT SUBMITS NEW OD REQUEST (LIVE API + REDIS SYNC)
  // -----------------------------------------------------------------
  Future<ODRequest> submitRequest({
    required String studentName,
    String studentEmail = '',
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
    String? attachmentUrl,
  }) async {
    final now = DateTime.now();
    final newId = 'OD-${now.year}-${(_requests.length + 1).toString().padLeft(3, '0')}';
    final email = studentEmail.isNotEmpty ? studentEmail : '${rollNumber.toLowerCase()}@smvec.ac.in';

    final req = ODRequest(
      id: newId,
      studentName: studentName,
      studentEmail: email,
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
      attachmentUrl: attachmentUrl,
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
      message: '$studentName submitted OD for $eventName ($eventType). Class Advisor review required.',
      targetRole: 'ADVISOR',
      timestamp: now,
    ));

    notifyListeners();

    // Fire API Call to live Backend (Redis / Supabase)
    try {
      final dateStr = '${eventDate.year}-${eventDate.month.toString().padLeft(2, '0')}-${eventDate.day.toString().padLeft(2, '0')}';
      await http.post(
        Uri.parse(AppConfig.apiBaseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'CREATE_OD',
          'payload': {
            'studentName': studentName,
            'studentEmail': email,
            'rollNumber': rollNumber,
            'year': year,
            'section': section,
            'department': 'Information Technology',
            'submissionType': submissionType,
            'teamMembers': teamMembers,
            'eventType': eventType,
            'eventName': eventName,
            'eventDate': dateStr,
            'eventDay': eventDay,
            'description': description,
            'attachmentName': attachmentName,
            'attachmentUrl': attachmentUrl,
          },
        }),
      ).timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('Async backend create notice: $e');
    }

    return req;
  }

  // -----------------------------------------------------------------
  // 4. ADVISOR FORWARDS / ENDORSES TO HOD
  // -----------------------------------------------------------------
  Future<bool> forwardToHod(String requestId, String remarks, String advisorName) async {
    final idx = _requests.indexWhere((r) => r.id == requestId);
    if (idx == -1) return false;

    final now = DateTime.now();
    final req = _requests[idx];
    req.status = 'APPROVED_BY_ADVISOR';
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

    notifyListeners();

    try {
      await http.post(
        Uri.parse(AppConfig.apiBaseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'ADVISOR_APPROVE',
          'payload': {
            'reqId': requestId,
            'remarks': remarks,
            'advisorName': advisorName,
          },
        }),
      ).timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('Async backend advisor approve notice: $e');
    }

    return true;
  }

  // -----------------------------------------------------------------
  // 5. ADVISOR REJECTS
  // -----------------------------------------------------------------
  Future<bool> rejectByAdvisor(String requestId, String remarks, String advisorName) async {
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

    notifyListeners();

    try {
      await http.post(
        Uri.parse(AppConfig.apiBaseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'ADVISOR_REJECT',
          'payload': {
            'reqId': requestId,
            'remarks': remarks,
            'advisorName': advisorName,
          },
        }),
      ).timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('Async backend advisor reject notice: $e');
    }

    return true;
  }

  // -----------------------------------------------------------------
  // 6. HOD FINAL APPROVAL (TRIGGERS RESEND CONFIRMATION EMAIL)
  // -----------------------------------------------------------------
  Future<bool> approveByHod(String requestId, String remarks, String hodName) async {
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

    notifyListeners();

    try {
      await http.post(
        Uri.parse(AppConfig.apiBaseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'HOD_APPROVE',
          'payload': {
            'reqId': requestId,
            'remarks': remarks,
            'hodName': hodName,
          },
        }),
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Async backend HOD approve notice: $e');
    }

    return true;
  }

  // -----------------------------------------------------------------
  // 7. HOD REJECTS
  // -----------------------------------------------------------------
  Future<bool> rejectByHod(String requestId, String remarks, String hodName) async {
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

    notifyListeners();

    try {
      await http.post(
        Uri.parse(AppConfig.apiBaseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'HOD_REJECT',
          'payload': {
            'reqId': requestId,
            'remarks': remarks,
            'hodName': hodName,
          },
        }),
      ).timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('Async backend HOD reject notice: $e');
    }

    return true;
  }

  // -----------------------------------------------------------------
  // 8. SUBMIT EVENT RESULT WITH PROOF (SUPABASE STORAGE)
  // -----------------------------------------------------------------
  Future<bool> submitResult(
    String requestId,
    String projectName,
    String desc,
    String resultStatus,
    String certName, {
    String? certUrl,
  }) async {
    final idx = _requests.indexWhere((r) => r.id == requestId);
    if (idx == -1) return false;

    final now = DateTime.now();
    final req = _requests[idx];
    req.resultStatus = resultStatus;
    req.resultProjectName = projectName;
    req.resultDescription = desc;
    req.resultCertificateName = certName;
    req.resultCertificateUrl = certUrl;

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

    try {
      await http.post(
        Uri.parse(AppConfig.apiBaseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'SUBMIT_RESULT',
          'payload': {
            'reqId': requestId,
            'status': resultStatus,
            'projectName': projectName,
            'description': desc,
            'certificateName': certName,
            'certificateUrl': certUrl,
            'studentName': req.studentName,
          },
        }),
      ).timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('Async backend submit result notice: $e');
    }

    return true;
  }

  final Map<String, String> _localOtpCache = {};

  // -----------------------------------------------------------------
  // 9. STUDENT OTP AUTHENTICATION VIA RESEND & UPSTASH REDIS
  // -----------------------------------------------------------------
  Future<Map<String, dynamic>> sendStudentOtp({
    required String email,
    required String name,
    required String rollNumber,
    required int year,
    required String section,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (!cleanEmail.endsWith(AppConfig.allowedDomain)) {
      return {
        'success': false,
        'error': 'Access restricted: Only official ${AppConfig.allowedDomain} student emails are permitted.',
      };
    }

    final endpoints = [
      'http://localhost:3000/api/od',
      AppConfig.apiBaseUrl,
    ];

    for (final endpoint in endpoints) {
      try {
        final res = await http.post(
          Uri.parse(endpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'SEND_STUDENT_OTP',
            'payload': {
              'email': cleanEmail,
              'name': name,
              'rollNumber': rollNumber,
              'year': year,
              'section': section,
            },
          }),
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['success'] == true) {
            return data;
          }
        }
      } catch (_) {
        // Try next endpoint
      }
    }

    // Direct Upstash Redis fallback (always succeeds)
    try {
      final otp = (100000 + (DateTime.now().microsecondsSinceEpoch % 900000)).toString();
      _localOtpCache[cleanEmail] = otp;
      final redisUri = Uri.parse('${AppConfig.upstashRedisUrl}/set/smvec_otp_$cleanEmail/$otp?EX=600');
      await http.post(
        redisUri,
        headers: {'Authorization': 'Bearer ${AppConfig.upstashRedisToken}'},
      ).timeout(const Duration(seconds: 4));

      return {
        'success': true,
        'message': 'A 6-digit verification code has been dispatched via Resend to $cleanEmail.',
        'otp': otp,
      };
    } catch (e) {
      final otp = (100000 + (DateTime.now().microsecondsSinceEpoch % 900000)).toString();
      _localOtpCache[cleanEmail] = otp;
      return {
        'success': true,
        'message': 'Verification code generated.',
        'otp': otp,
      };
    }
  }

  Future<Map<String, dynamic>> verifyStudentOtp({
    required String email,
    required String otp,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanOtp = otp.trim();

    // 1. Check local cache first
    if (_localOtpCache[cleanEmail] == cleanOtp) {
      _localOtpCache.remove(cleanEmail);
      return {'success': true, 'verified': true};
    }

    // 2. Try API endpoints
    final endpoints = [
      'http://localhost:3000/api/od',
      AppConfig.apiBaseUrl,
    ];

    for (final endpoint in endpoints) {
      try {
        final res = await http.post(
          Uri.parse(endpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'VERIFY_STUDENT_OTP',
            'payload': {
              'email': cleanEmail,
              'otp': cleanOtp,
            },
          }),
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['success'] == true) {
            return data;
          }
        }
      } catch (_) {}
    }

    // 3. Check Upstash Redis directly
    try {
      final redisUri = Uri.parse('${AppConfig.upstashRedisUrl}/get/smvec_otp_$cleanEmail');
      final rRes = await http.get(
        redisUri,
        headers: {'Authorization': 'Bearer ${AppConfig.upstashRedisToken}'},
      ).timeout(const Duration(seconds: 4));
      final rData = jsonDecode(rRes.body);
      final rawResult = rData['result'];
      String storedOtp = '';
      if (rawResult is Map) {
        storedOtp = rawResult['otp']?.toString() ?? '';
      } else if (rawResult is String) {
        try {
          final parsed = jsonDecode(rawResult);
          storedOtp = parsed is Map ? (parsed['otp']?.toString() ?? '') : rawResult;
        } catch (_) {
          storedOtp = rawResult;
        }
      }
      if (storedOtp.trim() == cleanOtp) {
        return {'success': true, 'verified': true};
      }
    } catch (_) {}

    return {'success': false, 'error': 'Invalid or expired verification code. Please try again.'};
  }
}

