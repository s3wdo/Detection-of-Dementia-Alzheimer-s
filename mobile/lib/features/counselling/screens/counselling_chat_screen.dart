import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/neuro_logo.dart';
import '../../dashboard/dashboard_providers.dart';
import '../counselling_providers.dart';
import '../data/models/counselling_models.dart';

/// Counselling chat (design screen 10). PROTOTYPE: answers are predefined
/// examples chosen by keyword and safety rules — there is no AI language model yet.
class CounsellingChatScreen extends ConsumerStatefulWidget {
  const CounsellingChatScreen({super.key, this.initialQuestion});

  /// Asked automatically when the chat opens (e.g. "Explain my latest report").
  final String? initialQuestion;

  static const suggestions = [
    'What does my latest MRI result mean?',
    'Why does my doctor review my result?',
    'How can I support a family member?',
    'What should I ask my doctor?',
  ];

  @override
  ConsumerState<CounsellingChatScreen> createState() => _CounsellingChatScreenState();
}

class _CounsellingChatScreenState extends ConsumerState<CounsellingChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuestion;
    if (q != null && q.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(counsellingChatProvider).lastQuestion != q) _send(q);
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the newest message in view.
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _send([String? preset]) {
    final q = preset ?? _text.text;
    if (q.trim().isEmpty) return;
    _text.clear();
    ref.read(counsellingChatProvider.notifier).send(q);
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(counsellingChatProvider);
    ref.listen(counsellingChatProvider, (_, __) => _scrollToEnd());
    final largeText = MediaQuery.textScalerOf(context).scale(10) > 13;
    final released = ref.watch(patientDashboardProvider).value?.latestReleased;
    final asked = chat.entries.where((e) => e.fromPatient).map((e) => e.text).toSet();
    final followUps = CounsellingChatScreen.suggestions.where((s) => !asked.contains(s)).take(2).toList();
    final answered = chat.entries.any((e) => !e.fromPatient);
    return Scaffold(
      appBar: AppBar(
        title: const PageTitle('NeuroSense Support', subtitle: 'Educational support only'),
        actions: [
          IconButton(
            tooltip: 'Ask my doctor',
            onPressed: () => context.push(Routes.patientMessages),
            icon: const Icon(Icons.medical_services_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          // Persistent: stays visible however long the conversation gets.
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.sm),
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
            decoration: const BoxDecoration(
              color: AppColors.devTint,
              border: Border(left: BorderSide(color: AppColors.dev, width: 3)),
            ),
            // Shorter wording at very large text sizes so the chat still has room.
            child: Text(
              largeText
                  ? 'PROTOTYPE — not medical advice.'
                  : 'PROTOTYPE — answers are predefined examples, not medical advice. '
                      'For decisions about your health, talk to your doctor.',
              style: const TextStyle(fontSize: 12, color: AppColors.body, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(AppSpacing.screen),
              children: [
                if (released != null) ...[
                  Row(children: [
                    const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.doctor),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text('Using only your released report of ${Fmt.date(released.createdAt)}',
                          style: AppTextStyles.caption.copyWith(color: AppColors.doctor)),
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (chat.entries.isEmpty) ...[
                  RowGroup(title: 'Try asking', children: [
                    for (final s in CounsellingChatScreen.suggestions) ListRowTile(title: s, onTap: () => _send(s)),
                  ]),
                ],
                for (final e in chat.entries) _ChatBubble(entry: e),
                if (chat.sending)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Text('Preparing your answer…', style: AppTextStyles.caption),
                    ),
                  ),
                if (answered && !chat.sending) ...[
                  const Divider(),
                  ListRowTile(
                    key: const Key('chatAskDoctor'),
                    icon: Icons.mail_outline_rounded,
                    iconColor: AppColors.doctor,
                    title: 'Ask My Doctor',
                    subtitle: 'Treatment, medication and what the result means for you',
                    onTap: () => context.push(Routes.patientMessages),
                  ),
                  const Divider(),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                    for (final s in followUps) ActionChip(label: Text(s), onPressed: () => _send(s)),
                  ]),
                  const SizedBox(height: AppSpacing.md),
                  const Text('Answers may be incomplete. Always check with your care team.',
                      style: AppTextStyles.caption, textAlign: TextAlign.center),
                ],
                if (chat.error != null)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(color: AppColors.errorTint, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Expanded(child: Text(chat.error!, style: AppTextStyles.caption.copyWith(color: AppColors.error))),
                      TextButton(
                          onPressed: () => ref.read(counsellingChatProvider.notifier).retry(),
                          child: const Text('Retry')),
                    ]),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    key: const Key('chatInput'),
                    controller: _text,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(hintText: 'Ask a question…'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton.filled(
                  key: const Key('chatSend'),
                  tooltip: 'Send',
                  onPressed: chat.sending ? null : _send,
                  icon: const Icon(Icons.send_rounded),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.entry});

  final ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    if (entry.fromPatient) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.lg, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.card)),
          child: Text(entry.text, style: AppTextStyles.body.copyWith(color: AppColors.ink)),
        ),
      );
    }
    // Educational answers are plain text blocks, not chat bubbles; safety replies keep a tinted box.
    if (entry.kind == ReplyKind.answer) return _AnswerBlock(entry: entry);
    final (bg, border, icon, color) = switch (entry.kind) {
      ReplyKind.emergency => (AppColors.errorTint, AppColors.error, Icons.emergency_outlined, AppColors.error),
      ReplyKind.referral => (
          AppColors.doctorTint,
          const Color(0xFFBFE3D6),
          Icons.medical_services_outlined,
          AppColors.doctor
        ),
      ReplyKind.answer => (AppColors.surface, AppColors.border, Icons.psychology_alt_outlined, AppColors.navy),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
          color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(AppRadii.card)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          entry.kind == ReplyKind.answer ? const NeuroLogo(size: 30) : Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.sm),
          Text(
            switch (entry.kind) {
              ReplyKind.emergency => 'Important',
              ReplyKind.referral => 'Please ask your doctor',
              ReplyKind.answer => 'NeuroSense Support',
            },
            style: AppTextStyles.label.copyWith(color: color),
          ),
          const Spacer(),
          if (entry.kind == ReplyKind.answer) const Text('Educational answer', style: AppTextStyles.caption),
        ]),
        const SizedBox(height: AppSpacing.md),
        Text(entry.text, style: AppTextStyles.body.copyWith(color: AppColors.ink)),
        if (entry.sources.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          const Overline('Sources'),
          const SizedBox(height: AppSpacing.sm),
          for (final s in entry.sources)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.menu_book_outlined, size: 18, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(s, style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary))),
              ]),
            ),
        ],
        if (entry.kind == ReplyKind.referral) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Message my doctor',
            icon: Icons.mail_outline_rounded,
            variant: AppButtonVariant.secondary,
            expand: false,
            onPressed: () => context.push(Routes.patientMessages),
          ),
        ],
      ]),
    );
  }
}

/// An educational answer: label line, plain text and its sources, with no bubble.
class _AnswerBlock extends StatelessWidget {
  const _AnswerBlock({required this.entry});

  final ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('NeuroSense Support · predefined answer', style: AppTextStyles.caption.copyWith(color: AppColors.navy)),
        const SizedBox(height: AppSpacing.xs),
        Text(entry.text, style: AppTextStyles.body.copyWith(color: AppColors.ink)),
        if (entry.sources.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final s in entry.sources)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Source: $s', style: AppTextStyles.caption),
            ),
        ],
      ]),
    );
  }
}
