class ODRequest {
  final String id;
  final String studentName;
  final String studentEmail;
  final String rollNumber;
  final String department;
  final int year;
  final String section;
  final String advisorEmail;
  final String advisorName;
  final String submissionType; // 'SOLO' or 'TEAM'
  final List<String> teamMembers;
  final String eventType;
  final String eventName;
  final DateTime eventDate;
  final String eventDay;
  final String description;
  final String status; // PENDING_ADVISOR, APPROVED_BY_ADVISOR, REJECTED_ADVISOR, APPROVED, REJECTED_HOD
  final String? advisorRemarks;
  final String? hodRemarks;
  final String resultStatus; // PENDING, PARTICIPATION, WON
  final String? resultProjectName;
  final String? resultDescription;
  final DateTime createdAt;

  ODRequest({
    required this.id,
    required this.studentName,
    required this.studentEmail,
    required this.rollNumber,
    required this.department,
    required this.year,
    required this.section,
    required this.advisorEmail,
    required this.advisorName,
    required this.submissionType,
    required this.teamMembers,
    required this.eventType,
    required this.eventName,
    required this.eventDate,
    required this.eventDay,
    required this.description,
    required this.status,
    required this.resultStatus,
    required this.createdAt,
    this.advisorRemarks,
    this.hodRemarks,
    this.resultProjectName,
    this.resultDescription,
  });

  factory ODRequest.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) => DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();

    return ODRequest(
      id: json['id']?.toString() ?? '',
      studentName: json['studentName']?.toString() ?? '',
      studentEmail: json['studentEmail']?.toString() ?? '',
      rollNumber: json['rollNumber']?.toString() ?? '',
      department: json['department']?.toString() ?? 'Information Technology',
      year: (json['year'] as num?)?.toInt() ?? 0,
      section: json['section']?.toString() ?? '',
      advisorEmail: json['advisorEmail']?.toString() ?? '',
      advisorName: json['advisorName']?.toString() ?? 'Class Advisor',
      submissionType: json['submissionType']?.toString() ?? 'SOLO',
      teamMembers: (json['teamMembers'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      eventType: json['eventType']?.toString() ?? '',
      eventName: json['eventName']?.toString() ?? '',
      eventDate: parseDate(json['eventDate']),
      eventDay: json['eventDay']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      status: json['status']?.toString() ?? 'PENDING_ADVISOR',
      advisorRemarks: json['advisorRemarks']?.toString(),
      hodRemarks: json['hodRemarks']?.toString(),
      resultStatus: json['resultStatus']?.toString() ?? 'PENDING',
      resultProjectName: json['resultProjectName']?.toString(),
      resultDescription: json['resultDescription']?.toString(),
      createdAt: parseDate(json['createdAt']),
    );
  }

  bool get isPendingAdvisor => status == 'PENDING_ADVISOR';
  bool get isPendingHod => status == 'APPROVED_BY_ADVISOR';
  bool get isApproved => status == 'APPROVED';
  bool get isRejected => status == 'REJECTED_ADVISOR' || status == 'REJECTED_HOD';

  String get statusDisplay {
    switch (status) {
      case 'PENDING_ADVISOR':
        return 'Waiting for Advisor';
      case 'APPROVED_BY_ADVISOR':
        return 'Waiting for HOD';
      case 'APPROVED':
        return 'OD Approved';
      case 'REJECTED_ADVISOR':
        return 'Rejected by Advisor';
      case 'REJECTED_HOD':
        return 'Rejected by HOD';
      default:
        return status;
    }
  }
}

class AdvisorInfo {
  final String email;
  final String name;
  final int year;
  final String section;
  final String batch;

  AdvisorInfo({
    required this.email,
    required this.name,
    required this.year,
    required this.section,
    required this.batch,
  });

  factory AdvisorInfo.fromJson(Map<String, dynamic> json) => AdvisorInfo(
        email: json['email']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        year: (json['year'] as num?)?.toInt() ?? 0,
        section: json['section']?.toString() ?? '',
        batch: json['batch']?.toString() ?? '',
      );
}
