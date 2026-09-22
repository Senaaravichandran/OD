import 'package:flutter/material.dart';

/// A file attached to an OD result. The bytes live in Supabase Storage; this
/// carries only the object key and enough metadata to display it.
class ODFile {
  final String id;
  final String kind; // CERTIFICATE, WINNING_PHOTO, EVENT_PHOTO, SUPPORTING_DOCUMENT
  final String objectKey;
  final String fileName;
  final String mimeType;
  final int sizeBytes;

  const ODFile({
    required this.id,
    required this.kind,
    required this.objectKey,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
  });

  factory ODFile.fromJson(Map<String, dynamic> json) => ODFile(
        id: json['id']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'SUPPORTING_DOCUMENT',
        objectKey: json['objectKey']?.toString() ?? '',
        fileName: json['fileName']?.toString() ?? 'file',
        mimeType: json['mimeType']?.toString() ?? 'application/octet-stream',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      );

  bool get isImage => mimeType.startsWith('image/');

  String get kindLabel => switch (kind) {
        'CERTIFICATE' => 'Certificate',
        'WINNING_PHOTO' => 'Winning photo',
        'EVENT_PHOTO' => 'Event photo',
        _ => 'Document',
      };

  String get sizeLabel => sizeBytes < 1024 * 1024
      ? '${(sizeBytes / 1024).toStringAsFixed(0)} KB'
      : '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// One member of a team entry.
///
/// The contribution is filled in when the result is recorded, because that is
/// when the department needs to know who did what - recognition goes to
/// people, not to a row.
class TeamMember {
  final String id;
  final String name;
  final String? registerNumber;
  final String? contribution;

  const TeamMember({
    required this.id,
    required this.name,
    this.registerNumber,
    this.contribution,
  });

  factory TeamMember.fromJson(Map<String, dynamic> json) => TeamMember(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        registerNumber: json['registerNumber']?.toString(),
        contribution: json['contribution']?.toString(),
      );

  bool get hasContribution =>
      contribution != null && contribution!.trim().isNotEmpty;
}

class ODRequest {
  final String id;
  final String referenceNo;
  final String studentName;
  final String studentEmail;
  final String registerNumber;
  final String department;
  final int year;
  final String section;
  final String advisorName;
  final String advisorEmail;
  final String submissionType; // SOLO | TEAM
  final List<String> teamMembers;
  final List<TeamMember> team;
  final String eventType;
  final String eventName;
  final DateTime eventDate;
  final DateTime eventEndDate;
  final int dayCount;
  final String eventDay;
  final String description;

  /// PENDING_ADVISOR | APPROVED_BY_ADVISOR | REJECTED_ADVISOR | APPROVED | REJECTED_HOD
  final String status;
  final String? advisorRemarks;
  final String? hodRemarks;
  final DateTime? advisorTimestamp;
  final DateTime? hodTimestamp;
  final DateTime createdAt;

  final String resultStatus; // PENDING | PARTICIPATED | WON
  final String? resultProjectName;
  final String? resultPrize;
  final String? resultPrizeDetails;
  final String? resultDescription;
  final List<ODFile> files;

  const ODRequest({
    required this.id,
    required this.referenceNo,
    required this.studentName,
    required this.studentEmail,
    required this.registerNumber,
    required this.department,
    required this.year,
    required this.section,
    required this.advisorName,
    required this.advisorEmail,
    required this.submissionType,
    required this.teamMembers,
    required this.eventType,
    required this.eventName,
    required this.eventDate,
    required this.eventEndDate,
    required this.eventDay,
    this.team = const [],
    this.dayCount = 1,
    required this.description,
    required this.status,
    required this.resultStatus,
    required this.createdAt,
    this.advisorRemarks,
    this.hodRemarks,
    this.advisorTimestamp,
    this.hodTimestamp,
    this.resultProjectName,
    this.resultPrize,
    this.resultPrizeDetails,
    this.resultDescription,
    this.files = const [],
  });

  static DateTime _date(dynamic v) =>
      DateTime.tryParse(v?.toString() ?? '')?.toLocal() ?? DateTime.now();

  factory ODRequest.fromJson(Map<String, dynamic> json) => ODRequest(
        id: json['id']?.toString() ?? '',
        referenceNo: json['referenceNo']?.toString() ?? '',
        studentName: json['studentName']?.toString() ?? '',
        studentEmail: json['studentEmail']?.toString() ?? '',
        registerNumber: json['registerNumber']?.toString() ?? '',
        department: json['department']?.toString() ?? 'Information Technology',
        year: (json['year'] as num?)?.toInt() ?? 0,
        section: json['section']?.toString() ?? '',
        advisorName: json['advisorName']?.toString() ?? '',
        advisorEmail: json['advisorEmail']?.toString() ?? '',
        submissionType: json['submissionType']?.toString() ?? 'SOLO',
        teamMembers: (json['teamMembers'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
        team: (json['team'] as List? ?? [])
            .map((e) => TeamMember.fromJson(e as Map<String, dynamic>))
            .toList(),
        eventType: json['eventType']?.toString() ?? '',
        eventName: json['eventName']?.toString() ?? '',
        eventDate: _date(json['eventDate']),
        // An older server sends only the one date; treat that as a one-day OD
        // rather than showing nothing.
        eventEndDate: json['eventEndDate'] == null
            ? _date(json['eventDate'])
            : _date(json['eventEndDate']),
        dayCount: (json['dayCount'] as num?)?.toInt() ?? 1,
        eventDay: json['eventDay']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        status: json['status']?.toString() ?? 'PENDING_ADVISOR',
        advisorRemarks: json['advisorRemarks']?.toString(),
        hodRemarks: json['hodRemarks']?.toString(),
        advisorTimestamp: json['advisorTimestamp'] == null
            ? null
            : _date(json['advisorTimestamp']),
        hodTimestamp:
            json['hodTimestamp'] == null ? null : _date(json['hodTimestamp']),
        createdAt: _date(json['createdAt']),
        resultStatus: json['resultStatus']?.toString() ?? 'PENDING',
        resultProjectName: json['resultProjectName']?.toString(),
        resultPrize: json['resultPrize']?.toString(),
        resultPrizeDetails: json['resultPrizeDetails']?.toString(),
        resultDescription: json['resultDescription']?.toString(),
        files: (json['files'] as List? ?? [])
            .map((e) => ODFile.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  bool get isPendingAdvisor => status == 'PENDING_ADVISOR';
  bool get isPendingHod => status == 'APPROVED_BY_ADVISOR';
  bool get isApproved => status == 'APPROVED';
  bool get isRejectedByAdvisor => status == 'REJECTED_ADVISOR';
  bool get isRejectedByHod => status == 'REJECTED_HOD';
  bool get isRejected => isRejectedByAdvisor || isRejectedByHod;
  bool get isClosed => isApproved || isRejected;

  /// A result can only be recorded once the HOD has sanctioned the OD.
  bool get canSubmitResult => isApproved;

  bool get isSingleDay =>
      eventEndDate.difference(eventDate).inDays == 0;

  bool get spansDays => !isSingleDay;

  /// How long the OD runs, for a line of text: "1 day" or "3 days".
  String get durationLabel => dayCount == 1 ? '1 day' : '$dayCount days';

  /// The attachments a result has to be backed by. A supporting document is
  /// the one kind that stays optional. The server applies the same rule.
  static List<String> evidenceFor(String resultStatus) => resultStatus == 'WON'
      ? const ['CERTIFICATE', 'EVENT_PHOTO', 'WINNING_PHOTO']
      : const ['CERTIFICATE', 'EVENT_PHOTO'];

  /// Which required attachments are still missing for the given outcome.
  List<String> missingEvidenceFor(String resultStatus) {
    final have = files.map((f) => f.kind).toSet();
    return evidenceFor(resultStatus).where((k) => !have.contains(k)).toList();
  }

  bool hasEvidenceFor(String resultStatus) =>
      missingEvidenceFor(resultStatus).isEmpty;

  /// Team members still without a recorded contribution.
  List<TeamMember> get membersWithoutContribution =>
      team.where((m) => !m.hasContribution).toList();
  bool get hasResult => resultStatus != 'PENDING';
  bool get won => resultStatus == 'WON';

  bool get isTeam => submissionType == 'TEAM';

  String get statusDisplay => switch (status) {
        'PENDING_ADVISOR' => 'Pending advisor',
        'APPROVED_BY_ADVISOR' => 'Awaiting HOD',
        'REJECTED_ADVISOR' => 'Rejected by advisor',
        'APPROVED' => 'Approved',
        'REJECTED_HOD' => 'Rejected by HOD',
        _ => status,
      };

  Color get statusColor => switch (status) {
        'PENDING_ADVISOR' => const Color(0xFFD97706),
        'APPROVED_BY_ADVISOR' => const Color(0xFF2563EB),
        'APPROVED' => const Color(0xFF059669),
        _ => const Color(0xFFDC2626),
      };

  IconData get statusIcon => switch (status) {
        'PENDING_ADVISOR' => Icons.hourglass_top_rounded,
        'APPROVED_BY_ADVISOR' => Icons.forward_to_inbox_rounded,
        'APPROVED' => Icons.verified_rounded,
        _ => Icons.cancel_rounded,
      };

  String get resultDisplay => switch (resultStatus) {
        'WON' => resultPrize == null || resultPrize!.isEmpty
            ? 'Won'
            : 'Won · $resultPrize',
        'PARTICIPATED' => 'Participated',
        _ => 'Result pending',
      };

  /// How far through the approval chain this request is, 0-3.
  int get progressStep {
    if (isRejectedByAdvisor) return 1;
    if (isPendingAdvisor) return 1;
    if (isPendingHod || isRejectedByHod) return 2;
    return 3;
  }
}

/// One section of one year, and the advisor who holds it.
class ClassSection {
  final String section;
  final String advisorName;
  final String advisorEmail;

  const ClassSection({
    required this.section,
    required this.advisorName,
    required this.advisorEmail,
  });

  factory ClassSection.fromJson(Map<String, dynamic> json) => ClassSection(
        section: json['section']?.toString() ?? '',
        advisorName: json['advisorName']?.toString() ?? '',
        advisorEmail: json['advisorEmail']?.toString() ?? '',
      );
}

/// The sections that exist in one year. Years differ - year 2 runs A-D, the
/// others stop at C - so the app only ever offers classes that exist.
class ClassYear {
  final int year;
  final List<ClassSection> sections;

  const ClassYear({required this.year, required this.sections});

  factory ClassYear.fromJson(Map<String, dynamic> json) => ClassYear(
        year: (json['year'] as num?)?.toInt() ?? 0,
        sections: (json['sections'] as List? ?? [])
            .map((e) => ClassSection.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AdvisorInfo {
  final String email;
  final String name;
  final int year;
  final String section;
  final String? batch;

  const AdvisorInfo({
    required this.email,
    required this.name,
    required this.year,
    required this.section,
    this.batch,
  });

  factory AdvisorInfo.fromJson(Map<String, dynamic> json) => AdvisorInfo(
        email: json['email']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        year: (json['year'] as num?)?.toInt() ?? 0,
        section: json['section']?.toString() ?? '',
        batch: json['batch']?.toString(),
      );
}

class AuditEntry {
  final String id;
  final String action;
  final String actor;
  final String actorName;
  final String role;

  /// What happened, as a sentence, composed by the server where the event
  /// name and the person's name are both to hand.
  final String summary;

  /// The raw details, kept for the rare case someone needs the exact record.
  final String details;
  final DateTime timestamp;

  const AuditEntry({
    required this.id,
    required this.action,
    required this.actor,
    required this.actorName,
    required this.role,
    required this.summary,
    required this.details,
    required this.timestamp,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    final actor = json['actor']?.toString() ?? 'System';
    final name = json['actorName']?.toString();
    return AuditEntry(
      id: json['id']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      actor: actor,
      actorName: name == null || name.isEmpty ? actor.split('@').first : name,
      role: json['role']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      details: json['details']?.toString() ?? '',
      timestamp: ODRequest._date(json['time']),
    );
  }

  /// The line to show. Falls back to the action if an older server sent no
  /// sentence, so the screen never renders empty.
  String get line => summary.isNotEmpty
      ? summary
      : '$actorName - ${action.replaceAll('_', ' ').toLowerCase()}';

  String get actionLabel =>
      action.replaceAll('_', ' ').toLowerCase().replaceFirstMapped(
            RegExp(r'^\w'),
            (m) => m.group(0)!.toUpperCase(),
          );
}

class AppNotification {
  final String id;
  final String title;
  final String message;
  final bool isRead;
  final DateTime timestamp;

  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.isRead,
    required this.timestamp,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Notification',
        message: json['text']?.toString() ?? '',
        isRead: json['isRead'] == true,
        timestamp: ODRequest._date(json['time']),
      );
}
