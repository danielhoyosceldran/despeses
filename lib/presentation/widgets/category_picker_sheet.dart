import 'package:flutter/material.dart';

import '../../core/i18n/display_name.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database.dart';
import '../../domain/repositories/category_repository.dart';

/// Drill-down category picker (plan §3.1): a leaf (no children) selects and
/// closes immediately; a branch descends into its children with a breadcrumb.
Future<Category?> showCategoryPickerSheet(
  BuildContext context, {
  required CategoryRepository repository,
  required Translations translations,
}) {
  return showModalBottomSheet<Category>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: CategoryPickerContent(
          repository: repository,
          translations: translations,
          onSelected: (category) => Navigator.of(context).pop(category),
        ),
      ),
    ),
  );
}

/// Embeddable body of the category picker, usable inside a [BottomActionPanel]
/// or a modal sheet.
class CategoryPickerContent extends StatefulWidget {
  const CategoryPickerContent({
    super.key,
    required this.repository,
    required this.translations,
    required this.onSelected,
  });

  final CategoryRepository repository;
  final Translations translations;
  final ValueChanged<Category> onSelected;

  @override
  State<CategoryPickerContent> createState() => _CategoryPickerContentState();
}

class _CategoryPickerContentState extends State<CategoryPickerContent> {
  final List<Category> _breadcrumb = [];
  List<Category> _children = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final children = await widget.repository.listChildren(_breadcrumb.isEmpty ? null : _breadcrumb.last.id);
    if (!mounted) return;
    setState(() {
      _children = children;
      _loading = false;
    });
  }

  String _label(Category c) => displayNameFor(widget.translations, name: c.name, isDefault: c.isDefault);

  Future<void> _tap(Category category) async {
    final children = await widget.repository.listChildren(category.id);
    if (children.isEmpty) {
      widget.onSelected(category);
      return;
    }
    setState(() => _breadcrumb.add(category));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).brightness == Brightness.dark ? AppColors.dark : AppColors.light;
    return Column(
      children: [
        if (_breadcrumb.isNotEmpty)
          ListTile(
            leading: Icon(Icons.arrow_back, color: colors.text),
            title: Text(_breadcrumb.map(_label).join(' > ')),
            onTap: () {
              setState(() => _breadcrumb.removeLast());
              _load();
            },
          ),
        if (_breadcrumb.isNotEmpty)
          ListTile(
            title: Text('Use "${_label(_breadcrumb.last)}" directly'),
            onTap: () => widget.onSelected(_breadcrumb.last),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _children.length,
                  itemBuilder: (context, index) {
                    final category = _children[index];
                    return ListTile(
                      title: Text(_label(category)),
                      trailing: Icon(Icons.chevron_right, color: colors.accent),
                      onTap: () => _tap(category),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
