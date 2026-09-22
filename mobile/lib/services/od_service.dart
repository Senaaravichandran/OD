import 'package:flutter/foundation.dart';

import '../models/od_request.dart';
import '../models/user.dart';
import 'api_client.dart';
import 'notification_service.dart';

/// Holds everything the signed-in user is allowed to see.
///
/// The server is the source of truth. Every change is sent to the API and the
/// record it returns replaces the local copy, so the app never guesses what
/// the new state should be.
class ODService extends ChangeNotifier {
  static final ODService _instance = ODService._internal();
  factory ODService() => _instance;
  ODService._internal();

  AppUser? _user;
  final List<ODRequest> _requests = [];
  final List<AuditEntry> _auditLogs = [];
  final List<AppNotification> _notifications = [];
  List<ClassYear> _classes = [];
  bool _isLoading = false;
  String? _lastError;
  bool _firstSync = true;

  /// Called when the server rejects the session.
  VoidCallback? onSessionExpired;

  AppUser? get user => _user;
  List<ODRequest> get allRequests => List.unmodifiable(_requests);
  List<AuditEntry> get allAuditLogs => List.unmodifiable(_auditLogs);
  List<AppNotification> get allNotifications => List.unmodifiable(_notifications);
  List<ClassYear> get classes => List.unmodifiable(_classes);
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  void setUser(AppUser? user) {
    _user = user;
    ApiClient.setStaffToken(user?.staffToken);
    _requests.clear();
    _auditLogs.clear();
    _notifications.clear();
    _classes = [];
    _lastError = null;
    _firstSync = true;
    notifyListeners();
    if (user != null) refresh();
  }

  void updateUser(AppUser user) {
    _user = user;
    notifyListeners();
  }

  Future<Map<String, dynamic>> _call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    try {
      return await ApiClient.call(action, payload: payload);
    } on ApiException catch (e) {
      if (e.isAuthError) onSessionExpired?.call();
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Sync
  // -------------------------------------------------------------------------

  Future<void> refresh() async {
    if (_user == null || _isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      final res = await _call('SYNC');
      final data = res['data'] as Map<String, dynamic>? ?? {};

      _requests
        ..clear()
        ..addAll((data['requests'] as List? ?? [])
            .map((e) => ODRequest.fromJson(e as Map<String, dynamic>)));
      _auditLogs
        ..clear()
        ..addAll((data['auditLogs'] as List? ?? [])
            .map((e) => AuditEntry.fromJson(e as Map<String, dynamic>)));
      _notifications
        ..clear()
        ..addAll((data['notifications'] as List? ?? [])
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>)));
      _lastError = null;

      // Anything new since last time is raised on the device. The first sync
      // after signing in is silent, so a new user is not buried under their
      // whole history.
      await NotificationService.showNew(
        [
          for (final n in _notifications)
            (id: n.id, title: n.title, body: n.message),
        ],
        silent: _firstSync,
      );
      _firstSync = false;
    } on ApiException catch (e) {
      _lastError = e.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// The department's class structure. Public, so it works before a student
  /// has a profile.
  Future<List<ClassYear>> loadClasses({bool force = false}) async {
    if (_classes.isNotEmpty && !force) return _classes;
    final res = await ApiClient.callPublic('CLASSES');
    _classes = (res['classes'] as List? ?? [])
        .map((e) => ClassYear.fromJson(e as Map<String, dynamic>))
        .toList();
    notifyListeners();
    return _classes;
  }

  Future<void> markNotificationsRead() async {
    if (unreadCount == 0) return;
    try {
      await _call('MARK_READ');
      await refresh();
    } on ApiException {
      // Not worth interrupting anyone over.
    }
  }

  Future<void> registerDevice(String fcmToken) async {
    try {
      await _call('REGISTER_DEVICE', {'fcmToken': fcmToken});
    } on ApiException catch (e) {
      debugPrint('could not register device for push: ${e.message}');
    }
  }

  // -------------------------------------------------------------------------
  // Student
  // -------------------------------------------------------------------------

  Future<AppUser> completeProfile({
    required String name,
    required String registerNumber,
    required int year,
    required String section,
  }) async {
    final res = await _call('REGISTER', {
      'name': name,
      'registerNumber': registerNumber,
      'year': year,
      'section': section,
    });
    final updated = AppUser.fromJson(
      res['user'] as Map<String, dynamic>,
      staffToken: _user?.staffToken,
    );
    _user = updated;
    notifyListeners();
    await refresh();
    return updated;
  }

  Future<AppUser> changeClass({required int year, required String section}) async {
    final res = await _call('CHANGE_CLASS', {'year': year, 'section': section});
    final updated = AppUser.fromJson(
      res['user'] as Map<String, dynamic>,
      staffToken: _user?.staffToken,
    );
    _user = updated;
    notifyListeners();
    return updated;
  }

  /// The date the API wants: plain yyyy-MM-dd, with no timezone to shift it
  /// across midnight.
  static String _ymd(DateTime d) => '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<ODRequest> createOd({
    required String eventType,
    required String eventName,
    required DateTime eventDate,
    required DateTime eventEndDate,
    required int dayCount,
    required String eventDay,
    required String description,
    required String submissionType,
    required List<String> teamMembers,
  }) async {
    final res = await _call('CREATE_OD', {
      'eventType': eventType,
      'eventName': eventName,
      'eventDate': _ymd(eventDate),
      'eventEndDate': _ymd(eventEndDate),
      'dayCount': dayCount,
      'eventDay': eventDay,
      'description': description,
      'submissionType': submissionType,
      'teamMembers': teamMembers,
    });
    return _upsert(res['request'] as Map<String, dynamic>);
  }

  Future<ODRequest> submitResult({
    required String requestId,
    required String status, // WON | PARTICIPATED
    required String projectName,
    String? prize,
    String? prizeDetails,
    String? description,
    /// One entry per team member: {'id': ..., 'contribution': ...}. The server
    /// refuses a team result with anyone unaccounted for.
    List<Map<String, String>> teamContributions = const [],
  }) async {
    final res = await _call('SUBMIT_RESULT', {
      'reqId': requestId,
      'status': status,
      'projectName': projectName,
      if (prize != null) 'prize': prize,
      if (prizeDetails != null) 'prizeDetails': prizeDetails,
      if (description != null) 'description': description,
      if (teamContributions.isNotEmpty) 'teamContributions': teamContributions,
    });
    return _upsert(res['request'] as Map<String, dynamic>);
  }

  // -------------------------------------------------------------------------
  // Advisor and HOD
  // -------------------------------------------------------------------------

  Future<ODRequest> advisorDecide({
    required String requestId,
    required bool approve,
    required String remarks,
  }) async {
    final res = await _call('ADVISOR_DECIDE', {
      'reqId': requestId,
      'approve': approve,
      'remarks': remarks,
    });
    return _upsert(res['request'] as Map<String, dynamic>);
  }

  Future<ODRequest> hodDecide({
    required String requestId,
    required bool approve,
    required String remarks,
  }) async {
    final res = await _call('HOD_DECIDE', {
      'reqId': requestId,
      'approve': approve,
      'remarks': remarks,
    });
    return _upsert(res['request'] as Map<String, dynamic>);
  }

  ODRequest _upsert(Map<String, dynamic> json) {
    final req = ODRequest.fromJson(json);
    final idx = _requests.indexWhere((r) => r.id == req.id);
    if (idx == -1) {
      _requests.insert(0, req);
    } else {
      _requests[idx] = req;
    }
    notifyListeners();
    return req;
  }

  // -------------------------------------------------------------------------
  // Derived views
  // -------------------------------------------------------------------------

  List<ODRequest> get activeRequests =>
      _requests.where((r) => !r.isClosed).toList();

  List<ODRequest> get closedRequests =>
      _requests.where((r) => r.isClosed).toList();

  List<ODRequest> get awaitingMyReview =>
      _requests.where((r) => r.isPendingAdvisor).toList();

  List<ODRequest> get awaitingHod =>
      _requests.where((r) => r.isPendingHod).toList();

  /// Distinct students visible to the caller, newest activity first. Used by
  /// the advisor and HOD student lists.
  List<StudentSummary> get students {
    final byReg = <String, StudentSummary>{};
    for (final r in _requests) {
      final existing = byReg[r.registerNumber];
      if (existing == null) {
        byReg[r.registerNumber] = StudentSummary(
          name: r.studentName,
          registerNumber: r.registerNumber,
          email: r.studentEmail,
          year: r.year,
          section: r.section,
          advisorName: r.advisorName,
          total: 1,
          approved: r.isApproved ? 1 : 0,
          won: r.won ? 1 : 0,
        );
      } else {
        byReg[r.registerNumber] = existing.copyWith(
          total: existing.total + 1,
          approved: existing.approved + (r.isApproved ? 1 : 0),
          won: existing.won + (r.won ? 1 : 0),
        );
      }
    }
    final list = byReg.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<ODRequest> requestsFor(String registerNumber) =>
      _requests.where((r) => r.registerNumber == registerNumber).toList();
}

class StudentSummary {
  final String name;
  final String registerNumber;
  final String email;
  final int year;
  final String section;
  final String advisorName;
  final int total;
  final int approved;
  final int won;

  const StudentSummary({
    required this.name,
    required this.registerNumber,
    required this.email,
    required this.year,
    required this.section,
    required this.advisorName,
    required this.total,
    required this.approved,
    required this.won,
  });

  StudentSummary copyWith({int? total, int? approved, int? won}) =>
      StudentSummary(
        name: name,
        registerNumber: registerNumber,
        email: email,
        year: year,
        section: section,
        advisorName: advisorName,
        total: total ?? this.total,
        approved: approved ?? this.approved,
        won: won ?? this.won,
      );

  String get classDisplay => 'Year $year · Section $section';
}
