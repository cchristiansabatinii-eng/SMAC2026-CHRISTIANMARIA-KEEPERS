import 'package:flutter/material.dart';
import 'package:keepers/theme/keepers_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Mark(),
                  const SizedBox(height: 48),
                  KeepersText(
                    'Every family has a keeper.',
                    style: KeepersType.heading.copyWith(
                      color: textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 18),
                  KeepersText(
                    'This week is still yours. Bring your family together '
                    'to unlock what everyone chose to share.',
                    style: textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 36),
                  const _StatusCard(),
                  const SizedBox(height: 56),
                  KeepersText(
                    'No cloud. No feed. The memories arrive when the family does.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
}

class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.lock_rounded, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        KeepersText(
          'KEEPERS',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 2.4),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      label: 'Weekly reveal locked',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.family_restroom_rounded,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KeepersText(
                    'Weekly reveal',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  KeepersText('Locked until your family gathers'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
