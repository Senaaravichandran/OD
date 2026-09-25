/// A class advisor as the HOD sees them on the roster screen.
///
/// Never carries a password or a digest - the server does not send one, and
/// there is nothing here that could be turned back into one.
class ClassAdvisor {
  final String id;
  final String name;
  final String email;
  final bool isHod;

  /// False once the HOD has removed them. The row stays, because the ODs they
  /// approved still name them.
  final bool isActive;

  final DateTime? retiredAt;
  final List<AdvisorClassRef> classes;

  /// How many OD requests they have handled, which is what makes removing
  /// them a retirement rather than a deletion.
  final int requestCount;

  /// How many students would need a new advisor if they were removed.
  final int studentCount;

  const ClassAdvisor({
    required this.id,
    required this.name,
    required this.email,
    required this.isHod,
    required this.isActive,
    required this.classes,
    required this.requestCount,
    required this.studentCount,
    this.retiredAt,
  });

  factory ClassAdvisor.fromJson(Map<String, dynamic> json) => ClassAdvisor(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        isHod: json['isHod'] == true,
        isActive: json['isActive'] != false,
        retiredAt: json['retiredAt'] == null
            ? null
            : DateTime.tryParse(json['retiredAt'].toString())?.toLocal(),
        classes: (json['classes'] as List? ?? [])
            .map((e) => AdvisorClassRef.fromJson(e as Map<String, dynamic>))
            .toList(),
        requestCount: (json['requestCount'] as num?)?.toInt() ?? 0,
        studentCount: (json['studentCount'] as num?)?.toInt() ?? 0,
      );

  String get classesLabel => classes.isEmpty
      ? 'No class assigned'
      : classes.map((c) => '${c.year}-${c.section}').join(', ');
}

/// One class an advisor holds.
class AdvisorClassRef {
  final int year;
  final String section;

  const AdvisorClassRef({required this.year, required this.section});

  factory AdvisorClassRef.fromJson(Map<String, dynamic> json) => AdvisorClassRef(
        year: (json['year'] as num?)?.toInt() ?? 0,
        section: json['section']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {'year': year, 'section': section};

  String get key => '$year-$section';

  @override
  bool operator ==(Object other) =>
      other is AdvisorClassRef && other.year == year && other.section == section;

  @override
  int get hashCode => Object.hash(year, section);
}

/// What came back from removing an advisor: who is now without one, so the HOD
/// can chase them rather than wait for complaints.
class AdvisorRemoval {
  final List<String> releasedClasses;
  final List<String> studentsToReassign;

  const AdvisorRemoval({
    required this.releasedClasses,
    required this.studentsToReassign,
  });

  factory AdvisorRemoval.fromJson(Map<String, dynamic> json) => AdvisorRemoval(
        releasedClasses: (json['releasedClasses'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
        studentsToReassign: (json['studentsToReassign'] as List? ?? [])
            .map((e) {
              final m = e as Map<String, dynamic>;
              final reg = m['registerNumber']?.toString() ?? '';
              final name = m['name']?.toString() ?? '';
              return reg.isEmpty ? name : '$name ($reg)';
            })
            .toList(),
      );
}
