import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:keepers/features/members/domain/avatar_catalog.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/members/presentation/widgets/keepers_avatar.dart';
import 'package:keepers/theme/keepers_theme.dart';

/// A presentation-only Humation picker. It changes a caller-owned draft and
/// never reaches a repository or controller that can persist a member row.
final class AvatarDraftPicker extends StatefulWidget {
  const AvatarDraftPicker({
    super.key,
    required this.config,
    required this.enabled,
    required this.onSelected,
    this.initialCategory = AvatarCategory.head,
  });

  final AvatarConfig config;
  final bool enabled;
  final ValueChanged<AvatarOption> onSelected;
  final AvatarCategory initialCategory;

  @override
  State<AvatarDraftPicker> createState() => _AvatarDraftPickerState();
}

final class _AvatarDraftPickerState extends State<AvatarDraftPicker> {
  late AvatarCategory _category;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: avatarCatalog.categories
            .map(
              (category) => SizedBox(
                key: Key('avatar-category-${category.name}'),
                height: 44,
                child: ChoiceChip(
                  label: KeepersText(_categoryTitle(category)),
                  selected: _category == category,
                  onSelected: widget.enabled
                      ? (_) => setState(() => _category = category)
                      : null,
                  backgroundColor: KeepersColors.auraIvory,
                  selectedColor: KeepersColors.ink,
                  labelStyle: TextStyle(
                    color: _category == category
                        ? KeepersColors.auraIvory
                        : KeepersColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                  side: const BorderSide(color: KeepersColors.homeLine),
                  shape: const StadiumBorder(),
                  showCheckmark: false,
                ),
              ),
            )
            .toList(growable: false),
      ),
      const SizedBox(height: 20),
      KeepersText(
        _categoryTitle(_category),
        style: KeepersType.heading.copyWith(color: KeepersColors.ink),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = math.max(1, constraints.maxWidth ~/ 100);
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: avatarCatalog
                .optionsFor(_category)
                .map((option) {
                  final selected = option.isSelected(widget.config);
                  final width = math.min(
                    96.0,
                    (constraints.maxWidth - 8 * (columns - 1)) / columns,
                  );
                  return _DraftOption(
                    option: option,
                    preview: avatarCatalog.sanitize(
                      option.apply(widget.config),
                      fallbackSeed: widget.config.seed,
                    ),
                    selected: selected,
                    enabled: widget.enabled,
                    width: width,
                    onSelected: () => widget.onSelected(option),
                  );
                })
                .toList(growable: false),
          );
        },
      ),
    ],
  );
}

final class _DraftOption extends StatefulWidget {
  const _DraftOption({
    required this.option,
    required this.preview,
    required this.selected,
    required this.enabled,
    required this.width,
    required this.onSelected,
  });

  final AvatarOption option;
  final AvatarConfig preview;
  final bool selected;
  final bool enabled;
  final double width;
  final VoidCallback onSelected;

  @override
  State<_DraftOption> createState() => _DraftOptionState();
}

final class _DraftOptionState extends State<_DraftOption> {
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'avatar option ${widget.option.id}',
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: widget.enabled,
    selected: widget.selected,
    label: '${widget.option.label} avatar option',
    onTap: widget.enabled ? widget.onSelected : null,
    child: SizedBox(
      key: Key('avatar-option-${widget.option.id}'),
      width: widget.width,
      height: widget.width,
      child: Material(
        color: widget.selected ? KeepersColors.ink : KeepersColors.auraIvory,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: widget.selected ? KeepersColors.ink : KeepersColors.homeLine,
            width: widget.selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('avatar-option-focus-${widget.option.id}'),
          focusNode: _focusNode,
          onTap: widget.enabled ? widget.onSelected : null,
          child: ExcludeSemantics(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 7,
                  child: widget.option.category == AvatarCategory.colors
                      ? _ColorSwatch(option: widget.option)
                      : KeepersAvatar(
                          config: widget.preview,
                          size: widget.width >= 92 ? 54 : 48,
                          crop: KeepersAvatarCrop.detail,
                        ),
                ),
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 6,
                  child: KeepersText(
                    widget.option.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: widget.selected
                          ? KeepersColors.auraIvory
                          : KeepersColors.ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                    ),
                  ),
                ),
                if (widget.selected)
                  const Positioned(
                    top: 6,
                    right: 6,
                    child: Icon(
                      Icons.check_rounded,
                      color: KeepersColors.auraIvory,
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

final class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.option});
  final AvatarOption option;

  @override
  Widget build(BuildContext context) {
    final hex = option.id.split('-').last;
    return Container(
      key: Key('avatar-color-swatch-${option.id}'),
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Color(int.parse('FF$hex', radix: 16)),
        shape: BoxShape.circle,
        border: Border.all(color: KeepersColors.ink.withValues(alpha: .32)),
      ),
    );
  }
}

String _categoryTitle(AvatarCategory category) => switch (category) {
  AvatarCategory.head => 'Head',
  AvatarCategory.body => 'Body',
  AvatarCategory.bottom => 'Bottom',
  AvatarCategory.item => 'Item',
  AvatarCategory.glasses => 'Glasses',
  AvatarCategory.colors => 'Colors',
};
