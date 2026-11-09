import 'package:azkar/features/home/domain/memorial_link_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses full links, paths and bare slugs', () {
    expect(
      parseMemorialSlug(
        'https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev/m/gamal-fooda',
      ),
      'gamal-fooda',
    );
    expect(parseMemorialSlug('/m/Nadia-Fooda/'), 'nadia-fooda');
    expect(parseMemorialSlug(' gamal-fooda '), 'gamal-fooda');
  });

  test('rejects invalid input', () {
    expect(parseMemorialSlug(''), isNull);
    expect(parseMemorialSlug('https://example.com/'), isNull);
    expect(parseMemorialSlug('https://example.com/m/'), isNull);
    expect(parseMemorialSlug('a b'), isNull);
    expect(parseMemorialSlug('x/y'), isNull);
  });
}
