import 'package:lucide_icons_flutter/lucide_icons.dart';
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
    final colors = context.appColors;
    return Column(
      children: [
        if (_breadcrumb.isNotEmpty)
          ListTile(
            dense: true,
            leading: Icon(LucideIcons.arrowLeft300, color: colors.text),
            title: Text(_breadcrumb.map(_label).join(' > ')),
            onTap: () {
              setState(() => _breadcrumb.removeLast());
              _load();
            },
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _children.length,
                  itemBuilder: (context, index) {
                    final category = _children[index];
                    return _BreadcrumbRow(
                      breadcrumbLabels: _breadcrumb.map(_label).toList(),
                      childLabel: _label(category),
                      colors: colors,
                      onBreadcrumbTap: (i) => widget.onSelected(_breadcrumb[i]),
                      onChildTap: () => _tap(category),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// One selectable row of the drill-down grid: a narrow column per already
/// chosen ancestor (breadcrumb), the most recent one highlighted, plus a wide
/// column for the current level's candidate.
class _BreadcrumbRow extends StatelessWidget {
  const _BreadcrumbRow({
    required this.breadcrumbLabels,
    required this.childLabel,
    required this.colors,
    required this.onBreadcrumbTap,
    required this.onChildTap,
  });

  final List<String> breadcrumbLabels;
  final String childLabel;
  final AppColors colors;
  final ValueChanged<int> onBreadcrumbTap;
  final VoidCallback onChildTap;

  @override
  Widget build(BuildContext context) {
    final lastIndex = breadcrumbLabels.length - 1;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          for (var i = 0; i < breadcrumbLabels.length; i++)
            SizedBox(
              width: 64,
              child: _Cell(
                label: breadcrumbLabels[i],
                highlighted: i == lastIndex,
                colors: colors,
                onTap: () => onBreadcrumbTap(i),
              ),
            ),
          Expanded(
            child: _Cell(label: childLabel, highlighted: false, colors: colors, onTap: onChildTap),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.highlighted, required this.colors, required this.onTap});

  final String label;
  final bool highlighted;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: highlighted ? colors.accent : colors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.smMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: highlighted ? colors.onAccent : colors.text),
            ),
          ),
        ),
      ),
    );
  }
}
