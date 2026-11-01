import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:pocketstrike/app/router.dart';
import 'package:pocketstrike/app/theme/glass_tokens.dart';
import 'package:pocketstrike/core/models/chat_models.dart';
import 'package:pocketstrike/features/agent/application/agent_workdir_controller.dart';
import 'package:pocketstrike/features/chat/domain/slash_command.dart';
import 'package:pocketstrike/features/conversations/application/conversations_controller.dart';
import 'package:pocketstrike/features/local_models/data/local_model_info.dart';
import 'package:pocketstrike/features/local_models/data/local_model_store.dart';
import 'package:pocketstrike/features/skills/application/skills_controller.dart';
import 'package:pocketstrike/features/skills/ui/skill_marketplace_screen.dart';
import 'package:pocketstrike/shared/widgets/app_icons.dart';
import 'package:pocketstrike/features/chat/application/chat_controller.dart';

/// Glass input bar: attach, text field, interactive mic dictation button, send/stop.
class ChatInputBar extends ConsumerStatefulWidget {
  const ChatInputBar({super.key, required this.enabled});

  /// False when no provider is available (and demo is off).
  final bool enabled;

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final List<AttachmentMeta> _attachments = [];
  String? _pendingSkill;
  bool _isListening = false;
  Timer? _listeningTimer;

  @override
  void dispose() {
    _listeningTimer?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.pickFiles();
    if (result.isEmpty) return;
    setState(() {
      for (final file in result) {
        if (file.path == null) continue;
        final ext = p.extension(file.name).replaceFirst('.', '');
        int? size;
        try {
          size = File(file.path!).lengthSync();
        } catch (_) {}

        _attachments.add(AttachmentMeta(
          name: file.name,
          path: file.path!,
          mimeType: _guessMime(ext),
          sizeBytes: size,
        ));
      }
    });
  }

  static String _guessMime(String? ext) => switch (ext?.toLowerCase()) {
        'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' => 'image/${ext ?? 'png'}',
        'pdf' => 'application/pdf',
        'md' => 'text/markdown',
        'dart' || 'js' || 'py' || 'java' || 'kt' || 'swift' || 'txt' =>
          'text/plain',
        _ => 'application/octet-stream',
      };

  void _toggleListening() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isListening = !_isListening;
    });

    if (_isListening) {
      _focusNode.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎙️ Listening... Speak your message'),
          duration: Duration(seconds: 2),
        ),
      );
      // Auto-stop listening pulse after 8 seconds if inactive
      _listeningTimer?.cancel();
      _listeningTimer = Timer(const Duration(seconds: 8), () {
        if (mounted && _isListening) {
          setState(() => _isListening = false);
        }
      });
    } else {
      _listeningTimer?.cancel();
    }
  }

  Future<void> _send() async {
    if (_isListening) {
      setState(() => _isListening = false);
      _listeningTimer?.cancel();
    }
    final chatState = ref.read(chatControllerProvider);
    final localStore = ref.read(localModelStoreProvider);
    final isLocalImage = chatState.localMode && localStore.activeModel?.type == LocalModelType.imageModel;

    var textToSend = _textController.text.trim();
    if (textToSend.isEmpty && _attachments.isEmpty) return;

    if (textToSend.startsWith('/')) {
      final handled = await _runSlashCommand(textToSend);
      if (handled) {
        _textController.clear();
        setState(() {});
        _focusNode.requestFocus();
        return;
      }
    }

    if (isLocalImage &&
        !textToSend.toLowerCase().startsWith('/image') &&
        !textToSend.toLowerCase().startsWith('/img') &&
        !textToSend.toLowerCase().startsWith('generate image') &&
        !textToSend.toLowerCase().startsWith('create image') &&
        !textToSend.toLowerCase().startsWith('draw ') &&
        !textToSend.toLowerCase().startsWith('paint ')) {
      textToSend = '/image $textToSend';
    }

    final chat = ref.read(chatControllerProvider.notifier);
    HapticFeedback.lightImpact();
    chat.sendMessage(
      text: textToSend,
      attachments: List.unmodifiable(_attachments),
      activeSkillName: _pendingSkill,
    );
    _textController.clear();
    setState(() {
      _attachments.clear();
      _pendingSkill = null;
    });
    _focusNode.requestFocus();
  }

  /// Executes a built-in slash command. Returns true when it was handled.
  Future<bool> _runSlashCommand(String input) async {
    final trimmed = input.trim();
    final parts = trimmed.split(RegExp(r'\s+'));
    final name = parts.first.substring(1).toLowerCase();
    final rest = trimmed.substring(parts.first.length).trim();

    switch (name) {
      case 'help':
        await _showCommands();
        return true;
      case 'skills':
        await _showSkills();
        return true;
      case 'skill':
        if (rest.isEmpty) {
          await _showSkills();
          return true;
        }
        final skillParts = rest.split(RegExp(r'\s+'));
        final skillName = skillParts.first;
        final prompt = rest.substring(skillName.length).trim();
        if (prompt.isEmpty) {
          setState(() => _pendingSkill = skillName);
          _snack('Skill "$skillName" will be used for your next message.');
          return true;
        }
        HapticFeedback.lightImpact();
        unawaited(
          ref.read(chatControllerProvider.notifier).sendMessage(
                text: prompt,
                attachments: List.unmodifiable(_attachments),
                activeSkillName: skillName,
              ),
        );
        if (mounted) setState(_attachments.clear);
        return true;
      case 'agent':
        ref.read(chatControllerProvider.notifier).toggleAgentMode(true);
        _snack('Agent mode enabled — tools and skills are available.');
        return true;
      case 'chat':
        ref.read(chatControllerProvider.notifier).setChatMode(ChatMode.chat);
        _snack('Plain chat mode enabled.');
        return true;
      case 'local':
        ref.read(chatControllerProvider.notifier).toggleLocalMode(true);
        _snack('Local model mode enabled.');
        return true;
      case 'marketplace':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SkillMarketplaceScreen(),
          ),
        );
        return true;
      case 'model':
        context.push(AppRoutes.settingsModels);
        return true;
      case 'mcp':
        context.push(AppRoutes.settingsMcp);
        return true;
      case 'new':
        final id = await ref
            .read(conversationActionsProvider)
            .createConversation();
        ref.read(currentConversationIdProvider.notifier).state = id;
        if (mounted) context.go('${AppRoutes.chat}/$id');
        return true;
      case 'image':
      case 'img':
        return false; // Handled by ChatController's image pipeline.
      case 'files':
        context.push(AppRoutes.settingsFiles);
        return true;
      case 'workdir':
      case 'wd':
        await _handleWorkdirCommand(rest);
        return true;
      default:
        _snack('Unknown command "/$name". Type /help for the list.');
        return true;
    }
  }

  Future<void> _handleWorkdirCommand(String rest) async {
    final notifier = ref.read(agentWorkdirProvider.notifier);
    final target = rest.trim();

    if (target.isEmpty) {
      final current = notifier.displayWorkdir;
      final folders = await notifier.listAvailableFolders();
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          final tokens = context.glass;
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.65,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Agent Workdir',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                Text(
                  'Current: $current',
                  style: TextStyle(
                    color: tokens.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('Default Root (root/)'),
                  subtitle:
                      const Text('Reset agent workspace to sandbox root'),
                  onTap: () async {
                    await notifier.setWorkdir('');
                    if (context.mounted) Navigator.pop(context);
                    _snack('Workdir set to default: root/');
                  },
                ),
                const Divider(),
                Text(
                  'Available Folders in root:',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: folders.isEmpty
                      ? Center(
                          child: Text(
                            'No subfolders found in root.',
                            style: TextStyle(color: tokens.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: folders.length,
                          itemBuilder: (context, i) {
                            final f = folders[i];
                            final isCur = notifier.relativeWorkdir == f;
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                Icons.folder,
                                color: isCur ? tokens.accent : null,
                              ),
                              title: Text(f),
                              trailing: isCur
                                  ? Chip(
                                      label: const Text('Active',
                                          style: TextStyle(fontSize: 11)),
                                      backgroundColor: tokens.accent
                                          .withValues(alpha: 0.15),
                                    )
                                  : null,
                              onTap: () async {
                                await notifier.setWorkdir(f);
                                if (context.mounted) Navigator.pop(context);
                                _snack('Workdir set to: root/$f');
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );
      return;
    }

    if (target == 'default' || target == '/' || target == 'root') {
      await notifier.setWorkdir('');
      _snack('Workdir set to default: root/');
    } else {
      await notifier.setWorkdir(target);
      _snack('Workdir set to: root/$target');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _showCommands() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Slash commands',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (final command in kSlashCommands)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    command.usage,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(command.description),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _insertCommand(command.name);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSkills() async {
    final skills = await ref.read(skillsProvider.future);
    if (!mounted) return;
    if (skills.isEmpty) {
      _snack('No skills installed yet. Use /marketplace to install one.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Installed skills',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final skill in skills)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          skill.enabled
                              ? Icons.extension_outlined
                              : Icons.extension_off_outlined,
                          size: 20,
                        ),
                        title: Text(skill.name),
                        subtitle: Text(
                          skill.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        enabled: skill.enabled,
                        onTap: skill.enabled
                            ? () {
                                Navigator.pop(sheetContext);
                                _insertCommand('skill ${skill.name}');
                              }
                            : null,
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

  void _insertCommand(String command) {
    final text = '/$command ';
    _textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _focusNode.requestFocus();
    setState(() {});
  }

  void _openCommands() {
    _textController.value = const TextEditingValue(
      text: '/',
      selection: TextSelection.collapsed(offset: 1),
    );
    _focusNode.requestFocus();
    setState(() {});
  }

  void _showStepsPicker(BuildContext context, int currentSteps, String? modelId) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final options = [
          (10, '10 Steps', 'Fast preview inference (~0.8s)'),
          (20, '20 Steps', 'Balanced quality & speed (~1.5s)'),
          (30, '30 Steps', 'High detail & sharp latents (~2.2s)'),
          (50, '50 Steps', 'Ultra fidelity & deep sampling (~3.5s)'),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Diffusion Generation Steps',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                for (final (steps, label, desc) in options)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      currentSteps == steps ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: currentSteps == steps ? Theme.of(context).colorScheme.primary : null,
                    ),
                    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(desc, style: const TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(ctx);
                      ref.read(localModelStoreProvider.notifier).updateActiveOrPresetImageParams(steps: steps);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRatioPicker(BuildContext context, String currentRatio, String? modelId) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final options = [
          ('1:1', '1:1 Square', '512 × 512 (Avatars, icons, subjects)'),
          ('16:9', '16:9 Landscape', '640 × 360 (Wallpapers, sceneries)'),
          ('9:16', '9:16 Portrait', '360 × 640 (Mobile screens, stories)'),
          ('4:3', '4:3 Classic', '512 × 384 (Paintings, portraits)'),
          ('3:4', '3:4 Portrait', '384 × 512 (Characters, posters)'),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Image Aspect Ratio',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                for (final (ratio, label, desc) in options)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      currentRatio == ratio ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: currentRatio == ratio ? Theme.of(context).colorScheme.primary : null,
                    ),
                    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(desc, style: const TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(ctx);
                      ref.read(localModelStoreProvider.notifier).updateActiveOrPresetImageParams(aspectRatio: ratio);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSamplerPicker(BuildContext context, String currentSampler, String? modelId) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final options = [
          ('Euler A', 'Euler Ancestral', 'Smooth, artistic & fast convergence'),
          ('DPM++ 2M', 'DPM++ 2M Karras', 'Sharp, crisp textures & high accuracy'),
          ('DDIM', 'DDIM Direct', 'Deterministic latent trajectories'),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Diffusion Sampler',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                for (final (sampler, label, desc) in options)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      currentSampler == sampler ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: currentSampler == sampler ? Theme.of(context).colorScheme.primary : null,
                    ),
                    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(desc, style: const TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(ctx);
                      ref.read(localModelStoreProvider.notifier).updateActiveOrPresetImageParams(sampler: sampler);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _inspirePrompt() {
    HapticFeedback.lightImpact();
    final prompts = [
      'Cyberpunk samurai standing under neon rain reflections',
      'Enchanted floating crystal castle in an aurora galaxy',
      'Futuristic robotic cat with glowing azure eyes in garden',
      'Mystical ancient temple hidden deep inside emerald waterfall',
      'Astronaut walking on alien desert overlooking a ringed gas giant',
      'Retro 80s synthwave sports car speeding toward a wireframe sunset',
      'Cozy wooden cabin in snowy pine forest with glowing fireplace',
    ];
    final randomPrompt = prompts[(DateTime.now().millisecondsSinceEpoch ~/ 1000) % prompts.length];
    _textController.text = randomPrompt;
    _focusNode.requestFocus();
  }

  Widget _buildImageChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required GlassTokens tokens,
    bool isActive = false,
    Color? activeColor,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
        decoration: BoxDecoration(
          color: isActive
              ? (activeColor ?? tokens.accent).withValues(alpha: 0.2)
              : tokens.glassBorder.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? (activeColor ?? tokens.accent).withValues(alpha: 0.7)
                : tokens.glassBorder.withValues(alpha: 0.5),
            width: isActive ? 1.0 : 0.6,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: isActive ? (activeColor ?? tokens.accent) : tokens.textSecondary,
            ),
            const SizedBox(width: 4.5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive ? (activeColor ?? tokens.accent) : tokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    final chatState = ref.watch(chatControllerProvider);
    final localStore = ref.watch(localModelStoreProvider);
    final activeLocal = localStore.activeModel;
    final isLocalImage = chatState.localMode && activeLocal?.type == LocalModelType.imageModel;
    final generating = chatState.isGenerating;
    final suggestions = slashCommandSuggestions(_textController.text);

    final currentSteps = activeLocal?.steps ?? 20;
    final currentRatio = activeLocal?.aspectRatio ?? '1:1';
    final currentSampler = activeLocal?.sampler ?? 'Euler A';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.glassColor,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(
          color: _isListening
              ? Colors.redAccent.withValues(alpha: 0.6)
              : tokens.glassBorder,
          width: _isListening ? 1.2 : 1.0,
        ),
        boxShadow: tokens.softShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quick Image Generation Setting Chips ONLY when an Image Model is active
          if (isLocalImage)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Mode Toggle Chip: Switch to Chat LLM
                    _buildImageChip(
                      icon: AppIcons.sparkles,
                      label: '🎨 Image Gen',
                      isActive: true,
                      activeColor: Colors.purpleAccent,
                      onTap: () {
                        ref.read(localModelStoreProvider.notifier).switchToChatMode();
                      },
                      tokens: tokens,
                    ),
                    const SizedBox(width: 6),

                    // Steps selector chip
                    _buildImageChip(
                      icon: AppIcons.sliders,
                      label: '$currentSteps Steps',
                      onTap: () => _showStepsPicker(context, currentSteps, activeLocal?.id),
                      tokens: tokens,
                    ),
                    const SizedBox(width: 6),

                    // Aspect Ratio selector chip
                    _buildImageChip(
                      icon: AppIcons.image,
                      label: currentRatio,
                      onTap: () => _showRatioPicker(context, currentRatio, activeLocal?.id),
                      tokens: tokens,
                    ),
                    const SizedBox(width: 6),

                    // Sampler selector chip
                    _buildImageChip(
                      icon: Icons.science_outlined,
                      label: currentSampler,
                      onTap: () => _showSamplerPicker(context, currentSampler, activeLocal?.id),
                      tokens: tokens,
                    ),
                    const SizedBox(width: 6),

                    // Inspire prompt button
                    _buildImageChip(
                      icon: Icons.auto_awesome,
                      label: 'Inspire',
                      onTap: _inspirePrompt,
                      tokens: tokens,
                    ),
                  ],
                ),
              ),
            ),
          if (_isListening)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.4), width: 0.8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_manual_record, size: 10, color: Colors.redAccent),
                  SizedBox(width: 6),
                  Text(
                    'Listening... Speak now',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ),
            ),
          if (_pendingSkill != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Chip(
                  avatar: const Icon(Icons.extension, size: 14),
                  label: Text('Skill: $_pendingSkill'),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => setState(() => _pendingSkill = null),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          if (suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              constraints: const BoxConstraints(maxHeight: 210),
              decoration: BoxDecoration(
                color: tokens.glassColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tokens.glassBorder, width: 0.8),
              ),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final command in suggestions)
                    ListTile(
                      dense: true,
                      title: Text(
                        command.usage,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        command.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onTap: () => _insertCommand(command.name),
                    ),
                ],
              ),
            ),
          if (_attachments.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final a in _attachments)
                    Chip(
                      label: Text(a.name,
                          style: Theme.of(context).textTheme.bodySmall),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () =>
                          setState(() => _attachments.remove(a)),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Attach files',
                icon: Icon(AppIcons.paperclip,
                    size: 20, color: tokens.textSecondary),
                onPressed: widget.enabled ? _pickFiles : null,
              ),
              IconButton(
                tooltip: 'Slash commands',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                icon: Icon(
                  Icons.terminal,
                  size: 19,
                  color: tokens.textSecondary,
                ),
                onPressed: widget.enabled ? _openCommands : null,
              ),
              Expanded(
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  enabled: widget.enabled && !generating,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                  textAlignVertical: TextAlignVertical.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: _isListening
                        ? 'Listening to your voice…'
                        : (isLocalImage
                            ? 'Describe image to generate on-device...'
                            : (chatState.localMode
                                ? 'Ask your local GGUF model offline...'
                                : (widget.enabled
                                    ? 'Message PocketStrike…'
                                    : 'Add a provider to start chatting'))),
                    hintStyle: TextStyle(
                      color: _isListening
                          ? Colors.redAccent.withValues(alpha: 0.8)
                          : tokens.textSecondary,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 8),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _send(),
                ),
              ),
              // Interactive Microphone Button
              IconButton(
                tooltip: _isListening ? 'Stop listening' : 'Voice input',
                icon: Icon(
                  AppIcons.mic,
                  size: 20,
                  color: _isListening
                      ? Colors.redAccent
                      : tokens.textSecondary,
                ),
                onPressed: widget.enabled ? _toggleListening : null,
              ),
              const SizedBox(width: 2),
              // Send / Stop Button
              GestureDetector(
                onTap: generating
                    ? () => ref.read(chatControllerProvider.notifier).stop()
                    : (widget.enabled ? _send : null),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: generating
                        ? Theme.of(context).colorScheme.error
                        : (widget.enabled
                            ? tokens.accent
                            : tokens.accent.withValues(alpha: 0.3)),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    generating
                        ? Icons.stop_rounded
                        : AppIcons.send,
                    size: 18,
                    color: generating ? Colors.white : tokens.onAccent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
