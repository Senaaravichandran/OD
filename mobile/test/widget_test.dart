import 'package:flutter_test/flutter_test.dart';
import 'package:smvec_od/utils/validators.dart';

void main() {
  group('validateCollegeEmail', () {
    test('accepts official college emails', () {
      expect(validateCollegeEmail('student@smvec.ac.in'), isNull);
      expect(validateCollegeEmail('  Staff.IT@SMVEC.AC.IN '), isNull);
    });

    test('rejects other domains and empty input', () {
      expect(validateCollegeEmail(''), isNotNull);
      expect(validateCollegeEmail('someone@gmail.com'), isNotNull);
      expect(validateCollegeEmail('@smvec.ac.in'), isNotNull);
      expect(validateCollegeEmail('a b@smvec.ac.in'), isNotNull);
    });
  });

  group('validateBatch', () {
    test('accepts a four-year batch like 2023-2027', () {
      expect(validateBatch('2023-2027'), isNull);
      expect(validateBatch(' 2024-2028 '), isNull);
    });

    test('rejects wrong formats and spans', () {
      expect(validateBatch('2023-27'), isNotNull);
      expect(validateBatch('2023/2027'), isNotNull);
      expect(validateBatch('2023-2026'), isNotNull);
      expect(validateBatch('23-27'), isNotNull);
      expect(validateBatch(''), isNotNull);
    });
  });
}
