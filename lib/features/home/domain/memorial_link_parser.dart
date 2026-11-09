/// Extracts a memorial page slug from a pasted page link or a bare slug.
///
/// Published content is scoped to memorial pages (`/m/<slug>`). The browser
/// opens them from the address bar; native apps need an explicit entry point.
String? parseMemorialSlug(String input) {
  final value = input.trim();
  if (value.isEmpty) return null;

  final uri = Uri.tryParse(value);
  final segments = uri != null && uri.hasScheme
      ? uri.pathSegments
      : value.split('/');
  final cleaned = segments.where((segment) => segment.isNotEmpty).toList();
  if (cleaned.isEmpty) return null;

  final markerIndex = cleaned.indexOf('m');
  final slug = markerIndex >= 0
      ? (markerIndex + 1 < cleaned.length ? cleaned[markerIndex + 1] : null)
      : (cleaned.length == 1 ? cleaned.first : null);
  if (slug == null) return null;

  final normalized = slug.toLowerCase();
  return RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(normalized)
      ? normalized
      : null;
}
