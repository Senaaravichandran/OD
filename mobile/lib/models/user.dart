enum UserRole { student, advisor, hod }

class AppUser {
  final String id;
  final String name;
  final String email;
  final UserRole role;
  final String? rollNumber;
  final int? year;
  final String? section;
  final String department;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.rollNumber,
    this.year,
    this.section,
    this.department = 'IT',
  });

  String get roleString {
    switch (role) {
      case UserRole.student:
        return 'STUDENT';
      case UserRole.advisor:
        return 'ADVISOR';
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
