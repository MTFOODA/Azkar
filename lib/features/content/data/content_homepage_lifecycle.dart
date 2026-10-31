import '../../../core/utils/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../../home/data/homepage_repository.dart';
import '../data/content_repository.dart';
import '../domain/content_item.dart';

/// Coordinates content creation with its page-scoped homepage reference.
class ContentHomepageLifecycle {
  const ContentHomepageLifecycle({
    required this._contentRepository,
    required this._homepageRepository,
  });

  final ContentRepository _contentRepository;
  final HomepageRepository _homepageRepository;

  Future<ContentItem> saveNew(ContentItem item) async {
    return _saveAndLink(await _contentRepository.save(item));
  }

  Future<ContentItem> duplicate(ContentItem item) async {
    return _saveAndLink(await _contentRepository.duplicate(item));
  }

  Future<ContentItem> _saveAndLink(ContentItem savedItem) async {
    try {
      await _homepageRepository.add(
        contentType: savedItem.type,
        contentId: savedItem.id,
      );
      return savedItem;
    } catch (error, stackTrace) {
      AppLogger.error(
        'Content saved but homepage linking failed',
        error,
        stackTrace,
      );
      throw ContentHomepageLinkException(savedItem, error);
    }
  }
}

class ContentHomepageLinkException extends AppException {
  ContentHomepageLinkException(this.savedItem, Object cause)
    : super(
        'تم حفظ المحتوى، لكن تعذرت إضافته إلى الرئيسية. '
        'يمكنك إضافته من إعدادات ترتيب الرئيسية.',
        cause: cause,
      );

  final ContentItem savedItem;
}
