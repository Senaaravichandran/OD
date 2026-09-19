enum UserRole { student, advisor, hod }

class AppUser {
  final String name;
  final String email;
  final UserRole role;
  final String? rollNumber;
  final int? year;
  final String? section;
  final String? batch; // Staff only, e.g. "2023-2027"
  final String department;
  final String token;

  AppUser({
    required this.name,
    required this.email,
    required this.role,
    required this.token,
    this.rollNumber,
    this.year,
    this.section,
    this.batch,
    this.department = 'Information Technology',
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

  factory AppUser.fromJson(Map<String, dynamic> json, String token) {
    return AppUser(
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: roleFromString(json['role']?.toString()),
      token: token,
      rollNumber: json['rollNumber']?.toString(),
      year: (json['year'] as num?)?.toInt(),
      section: json['section']?.toString(),
      batch: json['batch']?.toString(),
      department: json['department']?.toString() ?? 'Information Technology',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'role': roleString,
        'rollNumber': rollNumber,
        'year': year,
        'section': section,
        'batch': batch,
        'department': department,
      };

  AppUser copyWith({int? year, String? section, String? batch}) => AppUser(
        name: name,
        email: email,
        role: role,
        token: token,
        rollNumber: rollNumber,
        year: year ?? this.year,
        section: section ?? this.section,
        batch: batch ?? this.batch,
        department: department,
      );

  String get roleString {
    switch (role) {
      case UserRole.student:
        return 'STUDENT';
      case UserRole.advisor:
        return 'STAFF';
      case UserRole.hod:
        return 'HOD';
    }
  }

  String get roleDisplay {
    switch (role) {
      case UserRole.student:
        return 'Student';
      case UserRole.advisor:
        return 'Class Advisor';
      case UserRole.hod:
        return 'Head of Department (HOD)';
    }
  }
}
