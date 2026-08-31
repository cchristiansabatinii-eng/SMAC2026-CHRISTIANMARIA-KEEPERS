import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:keepers/theme/keepers_theme.dart';

final class VaultList extends StatelessWidget {
  const VaultList({required this.entries, required this.onOpen, super.key});

  final List<VaultEntryMetadata> entries;
  final ValueChanged<VaultEntryMetadata> onOpen;

  @override
  Widget build(BuildContext context) {
    final ordered = List<VaultEntryMetadata>.of(entries)
      ..sort((left, right) {
        final byDate = right.createdAt.compareTo(left.createdAt);
        return byDate != 0 ? byDate : right.id.compareTo(left.id);
      });
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeepersText(
            'Vault',
            style: KeepersType.heading.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          KeepersText(
            'Encrypted memories on this device',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          if (ordered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: KeepersText('No memories yet.'),
            )
          else
            ...ordered.indexed.map((indexed) {
              final (index, entry) = indexed;
              return Semantics(
                sortKey: OrdinalSortKey(index.toDouble()),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      minTileHeight: 64,
                      leading: Icon(_formatIcon(entry.format)),
                      title: KeepersText(entry.format.vaultLabel),
                      subtitle: KeepersText(
                        '${_formatDate(entry.createdAt)} · ${entry.privacy.vaultLabel}',
                      ),
                      trailing: Icon(_privacyIcon(entry.privacy), size: 20),
                      onTap: () => onOpen(entry),
                    ),
                    if (index < ordered.length - 1) const Divider(height: 1),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

IconData _formatIcon(MemoryFormat format) => switch (format) {
  MemoryFormat.photo => Icons.photo_rounded,
  MemoryFormat.voice => Icons.graphic_eq_rounded,
  MemoryFormat.text => Icons.notes_rounded,
};

IconData _privacyIcon(PrivacyTier privacy) => switch (privacy) {
  PrivacyTier.journal => Icons.person_rounded,
  PrivacyTier.reveal => Icons.lock_clock_rounded,
  PrivacyTier.capsule => Icons.lock_outline_rounded,
};
