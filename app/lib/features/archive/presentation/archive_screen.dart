import 'package:flutter/material.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/keepers_bottom_nav.dart';
import 'package:keepers/ui/keepers_destination_scaffold.dart';
import 'package:keepers/ui/kept_forever_summary.dart';

@immutable
final class ArchiveMemorySummary {
  const ArchiveMemorySummary({
    required this.id,
    required this.title,
    required this.authorName,
    required this.theme,
    required this.formatLabel,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String authorName;
  final String theme;
  final String formatLabel;
  final DateTime createdAt;
}

final class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({
    required this.familyName,
    required this.memories,
    required this.onDestinationSelected,
    required this.onOpenMemory,
    this.onCapture,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    super.key,
  });

  final String familyName;
  final List<ArchiveMemorySummary> memories;
  final ValueChanged<KeepersNavDestination> onDestinationSelected;
  final ValueChanged<ArchiveMemorySummary> onOpenMemory;
  final VoidCallback? onCapture;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

final class _ArchiveScreenState extends State<ArchiveScreen> {
  String? _person;
  String? _theme;

  List<ArchiveMemorySummary> get _filtered =>
      widget.memories
          .where((memory) => _person == null || memory.authorName == _person)
          .where((memory) => _theme == null || memory.theme == _theme)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  void _draw() {
    final memories = _filtered;
    if (memories.isEmpty) return;
    final daySeed = DateTime.now().day + DateTime.now().month;
    widget.onOpenMemory(memories[daySeed % memories.length]);
  }

  Widget _archiveBody(List<ArchiveMemorySummary> memories) {
    if (widget.loading) return const _ArchiveLoading();
    final error = widget.errorMessage;
    if (error != null) {
      return _ArchiveError(message: error, onRetry: widget.onRetry);
    }
    if (memories.isEmpty) {
      return _ArchiveEmpty(
        filtered: widget.memories.isNotEmpty,
        onClear: () => setState(() {
          _person = null;
          _theme = null;
        }),
      );
    }
    return _ArchiveTimeline(memories: memories, onOpen: widget.onOpenMemory);
  }

  @override
  Widget build(BuildContext context) {
    final people =
        widget.memories.map((memory) => memory.authorName).toSet().toList()
          ..sort();
    final themes =
        widget.memories.map((memory) => memory.theme).toSet().toList()..sort();
    final memories = _filtered;
    return KeepersDestinationScaffold(
      destination: KeepersNavDestination.archive,
      kicker: 'Kept memories',
      title: '${widget.familyName} archive',
      subtitle: 'Only memories the family chose to keep.',
      onDestinationSelected: widget.onDestinationSelected,
      onCapture: widget.onCapture,
      trailing: Semantics(
        label: 'Draw a memory',
        button: true,
        enabled: memories.isNotEmpty,
        onTap: memories.isEmpty ? null : _draw,
        child: ExcludeSemantics(
          child: IconButton.outlined(
            tooltip: 'DRAW A MEMORY',
            onPressed: memories.isEmpty ? null : _draw,
            icon: const Icon(Icons.casino_outlined),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.loading && widget.errorMessage == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
              child: KeptForeverSummary(count: widget.memories.length),
            ),
          if (widget.memories.isNotEmpty) ...[
            _FilterRail(
              label: 'Person',
              allLabel: 'All people',
              values: people,
              selected: _person,
              onSelected: (value) => setState(() => _person = value),
            ),
            _FilterRail(
              label: 'Theme',
              allLabel: 'All themes',
              values: themes,
              selected: _theme,
              onSelected: (value) => setState(() => _theme = value),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 10),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton.icon(
                    onPressed: memories.isEmpty ? null : _draw,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const KeepersText('Draw a memory'),
                  ),
                ],
              ),
            ),
          ],
          Expanded(child: _archiveBody(memories)),
        ],
      ),
    );
  }
}

final class _FilterRail extends StatelessWidget {
  const _FilterRail({
    required this.label,
    required this.allLabel,
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String allLabel;
  final List<String> values;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label filter',
    child: SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: KeepersText(allLabel),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final value in values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: KeepersText(value),
                selected: selected == value,
                onSelected: (_) => onSelected(value),
              ),
            ),
        ],
      ),
    ),
  );
}

final class _ArchiveLoading extends StatelessWidget {
  const _ArchiveLoading();

  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox(
      height: 150,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          KeepersText(
            'Opening family archive…',
            style: TextStyle(color: KeepersColors.inkMuted),
          ),
        ],
      ),
    ),
  );
}

final class _ArchiveError extends StatelessWidget {
  const _ArchiveError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 50,
            color: KeepersColors.inkMuted,
          ),
          const SizedBox(height: 16),
          KeepersText(
            'Archive unavailable',
            style: KeepersType.heading.copyWith(color: KeepersColors.ink),
          ),
          const SizedBox(height: 8),
          KeepersText(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: KeepersColors.inkMuted, height: 1.4),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onRetry,
              child: const KeepersText('Try again'),
            ),
          ],
        ],
      ),
    ),
  );
}

final class _ArchiveTimeline extends StatelessWidget {
  const _ArchiveTimeline({required this.memories, required this.onOpen});
  final List<ArchiveMemorySummary> memories;
  final ValueChanged<ArchiveMemorySummary> onOpen;

  @override
  Widget build(BuildContext context) {
    final years = <int, List<ArchiveMemorySummary>>{};
    for (final memory in memories) {
      years.putIfAbsent(memory.createdAt.year, () => []).add(memory);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      children: [
        for (final entry in years.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 10),
            child: KeepersText(
              '${entry.key}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: KeepersColors.ink,
                fontFamily: KeepersType.primary,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.3,
              ),
            ),
          ),
          for (final memory in entry.value)
            _ArchiveMemoryTile(memory: memory, onTap: () => onOpen(memory)),
        ],
      ],
    );
  }
}

final class _ArchiveMemoryTile extends StatelessWidget {
  const _ArchiveMemoryTile({required this.memory, required this.onTap});
  final ArchiveMemorySummary memory;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        KeepersColors.memberPalette[memory.authorName.hashCode.abs() %
            KeepersColors.memberPalette.length];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: KeepersColors.auraIvory.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: .16),
                    border: Border.all(color: color.withValues(alpha: .62)),
                  ),
                  child: Icon(
                    _formatIcon(memory.formatLabel),
                    color: KeepersColors.ink,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      KeepersText(
                        memory.title,
                        style: const TextStyle(
                          color: KeepersColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      KeepersText(
                        '${memory.authorName} · ${memory.theme} · ${_archiveDate(memory.createdAt)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: KeepersColors.inkMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: KeepersColors.inkMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _ArchiveEmpty extends StatelessWidget {
  const _ArchiveEmpty({required this.filtered, required this.onClear});
  final bool filtered;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.history_toggle_off_rounded,
            size: 54,
            color: KeepersColors.inkMuted,
          ),
          const SizedBox(height: 18),
          KeepersText(
            filtered ? 'No matches' : 'Nothing kept yet',
            style: KeepersType.heading.copyWith(color: KeepersColors.ink),
          ),
          const SizedBox(height: 9),
          KeepersText(
            filtered
                ? 'Try another person or theme.'
                : 'Released and still-sealed memories never appear here.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: KeepersColors.inkMuted, height: 1.4),
          ),
          if (filtered) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: onClear,
              child: const KeepersText('Clear filters'),
            ),
          ],
        ],
      ),
    ),
  );
}

IconData _formatIcon(String label) {
  final normalized = label.toLowerCase();
  if (normalized.contains('photo')) return Icons.photo_outlined;
  if (normalized.contains('voice')) return Icons.graphic_eq_rounded;
  return Icons.notes_rounded;
}

String _archiveDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
