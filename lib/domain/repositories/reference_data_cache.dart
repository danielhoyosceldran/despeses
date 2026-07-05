import '../../data/database.dart';
import 'category_repository.dart';
import 'event_project_repository.dart';
import 'payment_method_repository.dart';
import 'tag_repository.dart';

/// In-memory cache of rarely-changing "configuration" data (categories, tags,
/// tag groups, payment methods, events, projects) — equivalent to `refDataCache`
/// in the web app. Any mutation through the taxonomy repositories must call
/// [invalidate] afterwards so the next read re-fetches from the database.
class ReferenceDataCache {
  ReferenceDataCache({
    required this._categories,
    required this._tags,
    required this._tagGroups,
    required this._paymentMethods,
    required this._events,
    required this._projects,
  });

  final CategoryRepository _categories;
  final TagRepository _tags;
  final TagGroupRepository _tagGroups;
  final PaymentMethodRepository _paymentMethods;
  final EventRepository _events;
  final ProjectRepository _projects;

  List<Category>? _categoriesCache;
  List<Tag>? _tagsCache;
  List<TagGroup>? _tagGroupsCache;
  List<PaymentMethod>? _paymentMethodsCache;
  List<Event>? _eventsCache;
  List<Project>? _projectsCache;

  Future<List<Category>> categories() async =>
      _categoriesCache ??= await _categories.listAll();

  Future<List<Tag>> tags() async => _tagsCache ??= await _tags.listAll();

  Future<List<TagGroup>> tagGroups() async =>
      _tagGroupsCache ??= await _tagGroups.listAll();

  Future<List<PaymentMethod>> paymentMethods() async =>
      _paymentMethodsCache ??= await _paymentMethods.listAll();

  Future<List<Event>> events() async => _eventsCache ??= await _events.listAll();

  Future<List<Project>> projects() async => _projectsCache ??= await _projects.listAll();

  /// Call after any create/update/delete/reorder on taxonomy entities.
  void invalidate() {
    _categoriesCache = null;
    _tagsCache = null;
    _tagGroupsCache = null;
    _paymentMethodsCache = null;
    _eventsCache = null;
    _projectsCache = null;
  }
}
