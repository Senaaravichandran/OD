import 'package:flutter/foundation.dart';
import '../models/od_request.dart';
import '../models/user.dart';
import 'api_client.dart';

class AuditEntry {
  final String id;
  final String requestId;
  final String action;
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

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        id: json['id']?.toString() ?? '',
        requestId: json['requestId']?.toString() ?? '',
        action: json['action']?.toString() ?? '',
        performedBy: json['actor']?.toString() ?? 'System',
        role: json['role']?.toString() ?? '',
        details: json['details']?.toString() ?? '',
        timestamp: DateTime.tryParse(json['time']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      );
}

class AppNotification {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Notification',
        message: json['text']?.toString() ?? '',
        timestamp: DateTime.tryParse(json['time']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      );
}

/// Holds the signed-in user's data. The server is the source of truth:
/// every change is sent to the API and the returned record replaces the local copy.
class ODService extends ChangeNotifier {
  static final ODService _instance = ODService._internal();
  factory ODService() => _instance;
  ODService._internal();

  AppUser? _user;
  final List<ODRequest> _requests = [];
  final List<AuditEntry> _auditLogs = [];
  final List<AppNotification> _notifications = [];
  List<AdvisorInfo>? _advisors;
  bool _isLoading = false;
  String? _lastError;

  /// Called when the server rejects the session token (expired / invalid).
  VoidCallback? onSessionExpired;

  List<ODRequest> get allRequests => List.unmodifiable(_requests);
  List<AuditEntry> get allAuditLogs => List.unmodifiable(_auditLogs);
  List<AppNotification> get allNotifications => List.unmodifiable(_notifications);
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  void setUser(AppUser? user) {
    _user = user;
    _requests.clear();
    _auditLogs.clear();
    _notifications.clear();
    _advisors = null;
    _lastError = null;
    notifyListeners();
    if (user != null) refresh();
  }

  Future<Map<String, dynamic>> _call(String action, [Map<String, dynamic> payload = const {}]) async {
    final user = _user;
    if (user == null) throw ApiException('Not signed in.', 401);
    try {
      return await ApiClient.call(action, payload: payload, token: user.token);
    } on ApiException catch (e) {
      if (e.isAuthError) onSessionExpired?.call();
      rethrow;
    }
  }

  void _upsert(Map<String, dynamic> json) {
    final req = ODRequest.fromJson(json);
    final idx = _requests.indexWhere((r) => r.id == req.id);
    if (idx == -1) {
      _requests.insert(0, req);
    } else {
      _requests[idx] = req;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Sync (one request returns everything this user is allowed to see)
  // ---------------------------------------------------------------------------
  Future<void> refresh() async {
    if (_user == null || _isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      final res = await _call('SYNC');
      final data = res['data'] as Map<String, dynamic>? ?? {};
      _requests
        ..clear()
        ..addAll((data['requests'] as List? ?? []).map((e) => ODRequest.fromJson(e as Map<String, dynamic>)));
      _auditLogs
        ..clear()
        ..addAll((data['auditLogs'] as List? ?? []).map((e) => AuditEntry.fromJson(e as Map<String, dynamic>)));
      _notifications
        ..clear()
        ..addAll((data['notifications'] as List? ?? []).map((e) => AppNotification.fromJson(e as Map<String, dynamic>)));
      _lastError = null;
    } on ApiException catch (e) {
      _lastError = e.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Student
  // ---------------------------------------------------------------------------
  Future<List<AdvisorInfo>> fetchAdvisors({bool force = false}) async {
    if (_advisors != null && !force) return _advisors!;
    final res = await _call('ADVISORS');
    _advisors = (res['advisors'] as List? ?? [])
        .map((e) => AdvisorInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    return _advisors!;
  }

  Future<void> submitRequest({
    required String advisorEmail,
    required String submissionType,
    required List<String> teamMembers,
    required String eventType,
    required String eventName,
    required DateTime eventDate,
    required String eventDay,
    required String description,
  }) async {
    final dateStr = '${eventDate.year}-${eventDate.month.toString().padLeft(2, '0')}-${eventDate.day.toString().padLeft(2, '0')}';
    final res = await _call('CREATE_OD', {
      'advisorEmail': advisorEmail,
      'submissionType': submissionType,
      'teamMembers': teamMembers,
      'eventType': eventType,
      'eventName': eventName,
      'eventDate': dateStr,
      'eventDay': eventDay,
      'description': description,
    });
    _upsert(res['request'] as Map<String, dynamic>);
  }

  Future<void> submitResult(String requestId, String projectName, String desc, String resultStatus) async {
    final res = await _call('SUBMIT_RESULT', {
      'reqId': requestId,
      'projectName': projectName,
      'description': desc,
      'status': resultStatus,
    });
    _upsert(res['request'] as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------------------
  // Class Advisor
  // ---------------------------------------------------------------------------
  Future<void> advisorDecide(String requestId, {required bool approve, required String remarks}) async {
    final res = await _call('ADVISOR_DECIDE', {'reqId': requestId, 'approve': approve, 'remarks': remarks});
    _upsert(res['request'] as Map<String, dynamic>);
  }

  Future<AppUser> updateClass({required int year, required String section, required String batch}) async {
    await _call('UPDATE_CLASS', {'year': year, 'section': section, 'batch': batch});
    _user = _user!.copyWith(year: year, section: section, batch: batch);
    notifyListeners();
    return _user!;
  }

  // ---------------------------------------------------------------------------
  // HOD
  // ---------------------------------------------------------------------------
  Future<void> hodDecide(String requestId, {required bool approve, required String remarks}) async {
    final res = await _call('HOD_DECIDE', {'reqId': requestId, 'approve': approve, 'remarks': remarks});
    _upsert(res['request'] as Map<String, dynamic>);
  }
}
