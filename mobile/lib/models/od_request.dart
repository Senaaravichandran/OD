class ODRequest {
  final String id;
  final String studentName;
  final String rollNumber;
  final String department;
  final int year;
  final String section;
  final String submissionType; // 'SOLO' or 'TEAM'
  final List<String> teamMembers;
  final String eventType; // 'Hackathon', 'Internship', 'Paper Presentation', 'Workshop', 'Sports', 'Other'
  final String eventName;
  final DateTime eventDate;
  final String eventDay;
  final String description;
  String status; // 'PENDING_ADVISOR', 'FORWARDED_HOD', 'APPROVED', 'REJECTED_ADVISOR', 'REJECTED_HOD'
  String? advisorRemarks;
  String? advisorName;
  DateTime? advisorTimestamp;
  String? hodRemarks;
  String? hodName;
  DateTime? hodTimestamp;
  final String attachmentName;
  String resultStatus; // 'PENDING', 'PARTICIPATION', 'WON'
  String? resultProjectName;
  String? resultDescription;
  String? resultCertificateName;
  final DateTime createdAt;

  ODRequest({
    required this.id,
    required this.studentName,
    required this.rollNumber,
    this.department = 'Information Technology',
    required this.year,
    required this.section,
    required this.submissionType,
    required this.teamMembers,
    required this.eventType,
    required this.eventName,
    required this.eventDate,
    required this.eventDay,
    required this.description,
    this.status = 'PENDING_ADVISOR',
    this.advisorRemarks,
    this.advisorName,
    this.advisorTimestamp,
    this.hodRemarks,
    this.hodName,
    this.hodTimestamp,
    this.attachmentName = 'brochure.pdf',
    this.resultStatus = 'PENDING',
    this.resultProjectName,
    this.resultDescription,
    this.resultCertificateName,
    required this.createdAt,
  });

  String get statusDisplay {
    switch (status) {
      case 'PENDING_ADVISOR':
        return 'Submitted to Advisor';
      case 'FORWARDED_HOD':
        return 'Forwarded to HOD';
      case 'APPROVED':
        return 'OD Approved (HOD)';
      case 'REJECTED_ADVISOR':
        return 'Rejected by Advisor';
      case 'REJECTED_HOD':
        return 'Rejected by HOD';
      default:
        return status;
    }
  }

  int get currentStepIndex {
    switch (status) {
      case 'PENDING_ADVISOR':
        return 1;
      case 'FORWARDED_HOD':
        return 2;
      case 'APPROVED':
        return 3;
      case 'REJECTED_ADVISOR':
      case 'REJECTED_HOD':
        return -1;
      default:
        return 0;
    }
  }
}
