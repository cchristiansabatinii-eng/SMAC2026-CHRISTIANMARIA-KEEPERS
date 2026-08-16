import 'package:flutter/material.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/members/presentation/avatar_editor_screen.dart';
import 'package:keepers/features/members/presentation/widgets/keepers_avatar.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/keepers_bottom_nav.dart';
import 'package:keepers/ui/keepers_destination_scaffold.dart';

final class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.identity,
    required this.onDestinationSelected,
    this.onCapture,
    super.key,
  });

  final LocalIdentity identity;
  final VoidCallback? onCapture;
  final ValueChanged<KeepersNavDestination> onDestinationSelected;

  @override
  Widget build(BuildContext context) => KeepersDestinationScaffold(
    destination: KeepersNavDestination.settings,
    kicker: 'YOU',
    title: 'Settings',
    onCapture: onCapture,
    onDestinationSelected: onDestinationSelected,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        const _SectionLabel('Your identity'),
        const SizedBox(height: 8),
        _IdentityRow(
          key: const ValueKey('settings-identity'),
          identity: identity,
        ),
        const SizedBox(height: 4),
        _InformationRow(
          key: const ValueKey('settings-family'),
          icon: Icons.group_outlined,
          title: identity.familyName,
          detail: 'Family space',
        ),
        const _SectionDivider(),
        const _SectionLabel('Privacy on this device'),
        const SizedBox(height: 8),
        const _InformationRow(
          key: ValueKey('settings-privacy'),
          icon: Icons.lock_outline_rounded,
          title: 'Encrypted memories',
          detail: 'Memories are encrypted before local storage.',
        ),
        const _SectionDivider(),
        const _InformationRow(
          key: ValueKey('settings-accessibility'),
          icon: Icons.accessibility_new_rounded,
          title: 'Accessibility',
          detail: 'Motion follows the device setting.',
        ),
      ],
    ),
  );
}

final class _IdentityRow extends StatelessWidget {
  const _IdentityRow({required this.identity, super.key});

  final LocalIdentity identity;

  Future<void> _openEditor(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AvatarEditorScreen(identity: identity),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        Theme.of(context)
            .extension<ObservatoryTokens>()
            ?.memberColor(identity.colorToken) ??
        KeepersColors.homeGold;
    return Semantics(
      button: true,
      label: 'Edit avatar for ${identity.memberName}',
      onTap: () => _openEditor(context),
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openEditor(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    KeepersAvatarSurface(
                      size: 48,
                      accent: accent,
                      padding: 4,
                      child: KeepersAvatar(
                        config: identity.avatar,
                        size: 40,
                        crop: KeepersAvatarCrop.compact,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          KeepersText(
                            identity.memberName,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: KeepersColors.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          KeepersText(
                            'Edit avatar',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: KeepersColors.inkMuted,
                                  height: 1.4,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: KeepersColors.inkMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: KeepersText(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: KeepersColors.ink.withValues(alpha: .64),
        fontWeight: FontWeight.w700,
        letterSpacing: .4,
      ),
    ),
  );
}

final class _InformationRow extends StatelessWidget {
  const _InformationRow({
    required this.icon,
    required this.title,
    required this.detail,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(icon, color: KeepersColors.inkMuted, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KeepersText(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: KeepersColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                KeepersText(
                  detail,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: KeepersColors.inkMuted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

final class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 25, color: KeepersColors.ink.withValues(alpha: .12));
}
