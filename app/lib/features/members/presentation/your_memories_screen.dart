import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:keepers/theme/keepers_theme.dart';

@immutable
final class YourMemorySummary {
  const YourMemorySummary({
    required this.id,
    required this.title,
    required this.formatLabel,
    required this.privacyLabel,
    required this.statusLabel,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String formatLabel;
  final String privacyLabel;
  final String statusLabel;
  final DateTime createdAt;
}

final class YourMemoriesScreen extends StatefulWidget {
  const YourMemoriesScreen({
    required this.memberName,
    required this.memories,
    required this.onOpenMemory,
    super.key,
  });

  final String memberName;
  final List<YourMemorySummary> memories;
  final ValueChanged<YourMemorySummary> onOpenMemory;

  @override
  State<YourMemoriesScreen> createState() => _YourMemoriesScreenState();
}

final class _YourMemoriesScreenState extends State<YourMemoriesScreen> {
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark,
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: KeepersColors.auraGround.withValues(alpha: .9),
              surfaceTintColor: Colors.transparent,
              foregroundColor: KeepersColors.ink,
              title: const KeepersText('Your memories'),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 40),
              sliver: SliverList.list(
                children: [
                  KeepersText(
                    'YOUR VAULT',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: KeepersColors.inkMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  KeepersText(
                    '${widget.memberName}’s kept moments',
                    style: KeepersType.heading.copyWith(
                      color: KeepersColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const KeepersText(
                    'Everything you have kept lives here, including memories waiting for a reveal or milestone.',
                    style: TextStyle(
                      color: KeepersColors.inkMuted,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (widget.memories.isEmpty)
                    const _EmptyVault()
                  else
                    for (final memory in widget.memories)
                      _MemoryCard(
                        memory: memory,
                        onTap: () => widget.onOpenMemory(memory),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.memory, required this.onTap});

  final YourMemorySummary memory;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      key: Key('your-memory-${memory.id}'),
      color: KeepersColors.auraIvory.withValues(alpha: .82),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: KeepersColors.auraBlush.withValues(alpha: .72),
                  shape: BoxShape.circle,
                ),
                child: Icon(_formatIcon(memory.formatLabel)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KeepersText(
                      memory.title,
                      style: const TextStyle(
                        color: KeepersColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      children: [
                        _StatusChip(label: memory.privacyLabel, strong: true),
                        _StatusChip(label: memory.statusLabel),
                      ],
                    ),
                    const SizedBox(height: 7),
                    KeepersText(
                      '${memory.formatLabel} · ${_date(memory.createdAt)}',
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

final class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, this.strong = false});

  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: strong
          ? KeepersColors.ink
          : KeepersColors.auraBlush.withValues(alpha: .56),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(
        color: KeepersColors.ink.withValues(alpha: strong ? 1 : .12),
      ),
    ),
    child: KeepersText(
      label,
      style: TextStyle(
        color: strong ? KeepersColors.auraIvory : KeepersColors.ink,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

final class _EmptyVault extends StatelessWidget {
  const _EmptyVault();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
    decoration: BoxDecoration(
      color: KeepersColors.auraIvory.withValues(alpha: .76),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: KeepersColors.ink.withValues(alpha: .1)),
    ),
    child: Column(
      children: [
        const Icon(Icons.auto_stories_outlined, size: 38),
        const SizedBox(height: 14),
        KeepersText(
          'No memories kept yet',
          style: KeepersType.heading.copyWith(color: KeepersColors.ink),
        ),
        const SizedBox(height: 7),
        const KeepersText(
          'Use the + button on the main navigation to keep your first memory.',
          textAlign: TextAlign.center,
          style: TextStyle(color: KeepersColors.inkMuted, height: 1.4),
        ),
      ],
    ),
  );
}

IconData _formatIcon(String label) {
  if (label.startsWith('Photo')) return Icons.photo_outlined;
  if (label.startsWith('Voice')) return Icons.graphic_eq_rounded;
  return Icons.notes_rounded;
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
