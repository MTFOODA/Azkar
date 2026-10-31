import 'package:azkar/features/memorial/domain/page_slug.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes a valid public slug without changing its identity', () {
    expect(PageSlug.normalize('  AZKAR-a7f29c82  '), 'azkar-a7f29c82');
    expect(PageSlug.validate('azkar-a7f29c82'), isNull);
  });

  test('rejects invalid and reserved route slugs', () {
    expect(PageSlug.validate('azkar/name'), isNotNull);
    expect(PageSlug.validate('m'), isNotNull);
    expect(PageSlug.validate('a' * 41), isNotNull);
  });
}
