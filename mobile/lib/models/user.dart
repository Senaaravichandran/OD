enum UserRole { student, advisor, hod }

/// One class an advisor holds. An advisor may hold more than one.
class AdvisorClass {
  final int year;
  final String section;
  final String label;
  final String? batch;

  const AdvisorClass({
    required this.year,
    required this.section,
    required this.label,
    this.batch,
  });

  factory AdvisorClass.fromJson(Map<String, dynamic> json) => AdvisorClass(
        year: (json['year'] as num?)?.toInt() ?? 0,
        section: json['section']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        batch: json['batch']?.toString(),
      );

  Map<String, dynamic> toJson() =>
      {'year': year, 'section': section, 'label': label, 'batch': batch};

  String get display => 'Year $year · Section $section';
}

class AppUser {
  final String name;
  final String email;
  final UserRole role;
  final String department;

  // Students
  final String? registerNumber;
  final int? year;
  final String? section;
  final String? advisorName;
  final String? advisorEmail;
  final String? photoUrl;

  // Staff
  final List<AdvisorClass> classes;

  /// Only set for a staff password session. Students authenticate with their
  /// Firebase token on every call, so they have none.
  final String? staffToken;

  const AppUser({
    required this.name,
    required this.email,
    required this.role,
    this.department = 'Information Technology',
    this.registerNumber,
    this.year,
    this.section,
    this.advisorName,
    this.advisorEmail,
    this.photoUrl,
    this.classes = const [],
    this.staffToken,
  });

  static UserRole roleFromString(String? role) {
    switch (role) {
      case 'HOD':
        return UserRole.hod;
      case 'STAFF':
      case 'ADVISOR':
        return UserRole.advisor;
      default:
        return UserRole.student;
    }
  }

  factory AppUser.fromJson(Map<String, dynamic> json, {String? staffToken}) {
    return AppUser(
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: roleFromString(json['role']?.toString()),
      department: json['department']?.toString() ?? 'Information Technology',
      registerNumber: json['registerNumber']?.toString(),
      year: (json['year'] as num?)?.toInt(),
      section: json['section']?.toString(),
      advisorName: json['advisorName']?.toString(),
      advisorEmail: json['advisorEmail']?.toString(),
      photoUrl: json['photoUrl']?.toString(),
      classes: (json['classes'] as List? ?? [])
          .map((e) => AdvisorClass.fromJson(e as Map<String, dynamic>))
          .toList(),
      staffToken: staffToken,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'role': roleString,
        'department': department,
        'registerNumber': registerNumber,
        'year': year,
        'section': section,
        'advisorName': advisorName,
        'advisorEmail': advisorEmail,
        'photoUrl': photoUrl,
        'classes': classes.map((c) => c.toJson()).toList(),
      };

  AppUser copyWith({
    String? name,
    int? year,
    String? section,
    String? advisorName,
    String? advisorEmail,
    String? staffToken,
  }) =>
      AppUser(
        name: name ?? this.name,
        email: email,
        role: role,
        department: department,
        registerNumber: registerNumber,
        year: year ?? this.year,
        section: section ?? this.section,
        advisorName: advisorName ?? this.advisorName,
        advisorEmail: advisorEmail ?? this.advisorEmail,
        photoUrl: photoUrl,
        classes: classes,
        staffToken: staffToken ?? this.staffToken,
      );

  String get roleString => switch (role) {
        UserRole.student => 'STUDENT',
        UserRole.advisor => 'ADVISOR',
        UserRole.hod => 'HOD',
      };

  String get roleDisplay => switch (role) {
        UserRole.student => 'Student',
        UserRole.advisor => 'Class Advisor',
        UserRole.hod => 'Head of Department',
      };

  String get classDisplay =>
      year == null ? '' : 'Year $year · Section ${section ?? "-"}';

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
