import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketstrike/app/theme/glass_tokens.dart';
import 'package:pocketstrike/core/storage/app_sandbox.dart';
import 'package:pocketstrike/core/storage/prefs_provider.dart';
import 'package:pocketstrike/shared/widgets/app_icons.dart';
import 'package:pocketstrike/features/agent/domain/agent_tool.dart';

class StorageSettingsScreen extends ConsumerStatefulWidget {
  const StorageSettingsScreen({super.key});

  @override
  ConsumerState<StorageSettingsScreen> createState() =>
      _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends ConsumerState<StorageSettingsScreen> {
  late ConfirmationPolicy _policy = ConfirmationPolicy.destructiveOnly;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final prefs = ref.read(sharedPreferencesProvider);
    setState(() {
      _policy = ConfirmationPolicyX.fromId(prefs.getString('confirm_policy'));
    });
  }

  Future<void> _savePolicy(ConfirmationPolicy policy) async {
    setState(() => _policy = policy);
    await ref
        .read(sharedPreferencesProvider)
        .setString('confirm_policy', policy.id);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Storage & Permissions',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tokens.glassColor,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(color: tokens.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(AppIcons.shieldCheck, color: tokens.accent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'App Sandbox Only',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Vina Agent can only read, write, list, move and delete files '
                  'inside its private app sandbox. Device storage, /sdcard and '
                  'shared folders are never exposed to the agent.',
                  style: TextStyle(color: tokens.textSecondary, height: 1.45),
                ),
                const SizedBox(height: 12),
                FutureBuilder<String>(
                  future: AppSandbox.root().then((d) => d.path),
                  builder: (context, snapshot) {
                    final path = snapshot.data ?? 'Preparing sandbox…';
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: tokens.secondary.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        border: Border.all(
                          color: tokens.secondary.withValues(alpha: 0.55),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sandbox root',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: tokens.textSecondary,
                                ),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            path,
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  'Folders: Documents · Downloads · Artifacts · Exports · Skills',
                  style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'CONFIRMATION SAFETY LEVEL',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: tokens.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          for (final p in ConfirmationPolicy.values)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: _policy == p
                    ? tokens.accent.withValues(alpha: 0.12)
                    : tokens.glassColor,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(
                  color: _policy == p ? tokens.accent : tokens.glassBorder,
                ),
              ),
              child: ListTile(
                title: Text(p.label),
                subtitle: Text(
                  p.description,
                  style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                ),
                trailing: _policy == p
                    ? Icon(AppIcons.checkCircle2, color: tokens.accent)
                    : null,
                onTap: () => _savePolicy(p),
              ),
            ),
        ],
      ),
    );
  }
}
