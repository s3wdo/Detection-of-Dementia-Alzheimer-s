import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/data/repository_providers.dart';
import '../../../core/data/user_facing_error.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../dashboard/dashboard_providers.dart';
import '../../notifications/notifications_providers.dart';
import '../../patients/patients_providers.dart';
import '../data/models/message.dart';
import '../messages_providers.dart';

/// A conversation between a patient and their doctor. Patients get the
/// "Ask My Doctor" layout (design section 20); doctors get a chat thread.
/// For patients the patient id comes from the session, so they can only open their own thread.
class MessageThreadScreen extends ConsumerStatefulWidget {
  const MessageThreadScreen.doctor({super.key, required String this.patientId}) : asDoctor = true;
  const MessageThreadScreen.patient({super.key})
      : patientId = null,
        asDoctor = false;

  final String? patientId;
  final bool asDoctor;

  @override
  ConsumerState<MessageThreadScreen> createState() => _MessageThreadScreenState();
}

class _MessageThreadScreenState extends ConsumerState<MessageThreadScreen> {
  final _text = TextEditingController();
  bool _sending = false;

  /// Patients can attach their latest released analysis to the message.
  bool _linkAnalysis = true;

  String? get _patientId => widget.patientId ?? ref.read(sessionControllerProvider)?.patientId;

  @override
  void initState() {
    super.initState();
    // Opening the conversation marks the other side's messages as read.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final id = _patientId;
      if (id == null) return;
      await ref.read(messagesRepositoryProvider).markThreadRead(id, readerIsDoctor: widget.asDoctor);
      ref.invalidate(doctorThreadsProvider);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send({String? linkedTo}) async {
    final id = _patientId;
    final session = ref.read(sessionControllerProvider);
    if (id == null || session == null || _text.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(messagesRepositoryProvider).send(
            patientId: id,
            body: _text.text,
            fromDoctor: widget.asDoctor,
            senderName: session.fullName,
            linkedTo: linkedTo,
          );
      _text.clear();
      ref.invalidate(threadProvider(id));
      ref.invalidate(doctorThreadsProvider);
      ref.invalidate(notificationsProvider);
      if (mounted && !widget.asDoctor) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message sent to your care team.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Not sent: ${userMessage(e)}')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.patientId ?? ref.watch(sessionControllerProvider)?.patientId;
    if (id == null) return const SizedBox.shrink();
    final thread = ref.watch(threadProvider(id));
    return widget.asDoctor ? _doctorView(id, thread) : _patientView(id, thread);
  }

  // ---------------------------------------------------------------- doctor

  Widget _doctorView(String id, AsyncValue<List<Message>> thread) {
    final patient = ref.watch(patientProvider(id)).value;
    return Scaffold(
      appBar: AppBar(
        title: PageTitle(patient?.fullName ?? 'Conversation', subtitle: 'Secure message · ${patient?.mrn ?? ''}'),
      ),
      body: Column(children: [
        Expanded(
          child: AsyncValueView<List<Message>>(
            value: thread,
            onRetry: () => ref.invalidate(threadProvider(id)),
            isEmpty: (l) => l.isEmpty,
            empty: const EmptyState(icon: Icons.forum_outlined, title: 'No messages yet'),
            data: (list) => ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(AppSpacing.screen),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final m = list[list.length - 1 - i];
                return Align(
                  alignment: m.fromDoctor ? Alignment.centerRight : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: _MessageCard(message: m, mine: m.fromDoctor),
                  ),
                );
              },
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
            child: Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('messageInput'),
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Write a message…'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                key: const Key('sendMessage'),
                tooltip: 'Send',
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // --------------------------------------------------------------- patient

  Widget _patientView(String id, AsyncValue<List<Message>> thread) {
    final latest = ref.watch(patientDashboardProvider).value?.latestReleased;
    final link = latest == null ? null : 'MRI analysis · ${Fmt.shortDate(latest.createdAt)}';
    return Scaffold(
      appBar: AppBar(title: const PageTitle('Ask My Doctor', subtitle: 'Secure message')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
        children: [
          const Row(children: [
            AppAvatar(name: 'Dr. Ahmed Khan', size: 44, background: AppColors.doctorTint, foreground: AppColors.doctor),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Dr. Ahmed Khan', style: AppTextStyles.headline),
                Text('Neurology · Usually replies within 2 working days', style: AppTextStyles.caption),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'This message goes directly to your care team, not to the AI assistant (NeuroSense Support).',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xl),
          const Text('Your message', style: AppTextStyles.label),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('messageInput'),
            controller: _text,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(hintText: 'Write your question for your doctor…'),
          ),
          if (link != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: _linkAnalysis
                  ? InputChip(
                      avatar: const Icon(Icons.link_rounded, size: 18),
                      label: Text('Linked: $link'),
                      onDeleted: () => setState(() => _linkAnalysis = false),
                      deleteButtonTooltipMessage: 'Remove link',
                    )
                  : TextButton.icon(
                      onPressed: () => setState(() => _linkAnalysis = true),
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('Link my latest MRI analysis'),
                    ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const Key('sendMessage'),
            label: 'Send message',
            icon: Icons.send_outlined,
            loading: _sending,
            onPressed: () => _send(linkedTo: _linkAnalysis ? link : null),
          ),
          const SizedBox(height: AppSpacing.xxl),
          AsyncValueView<List<Message>>(
            value: thread,
            onRetry: () => ref.invalidate(threadProvider(id)),
            isEmpty: (l) => l.isEmpty,
            empty: const Text('No previous messages.', style: AppTextStyles.bodySmall),
            data: (list) => RowGroup(title: 'Previous messages', children: [
              for (final m in list.reversed) _MessageRow(message: m, mine: !m.fromDoctor),
            ]),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text('Not for urgent matters. In an emergency, call your local emergency number.',
              style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

/// A message bubble in the doctor's conversation view.
class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.mine});

  final Message message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: mine ? AppColors.primaryTint : AppColors.surface,
        border: mine ? null : Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(message.body, style: AppTextStyles.body.copyWith(color: AppColors.ink)),
        if (message.linkedTo != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text('Linked: ${message.linkedTo}', style: AppTextStyles.caption),
        ],
        const SizedBox(height: 2),
        Text('${mine ? 'You' : message.senderName} · ${Fmt.shortDate(message.sentAt)} ${Fmt.time(message.sentAt)}',
            style: AppTextStyles.caption),
      ]),
    );
  }
}

/// A message in the patient's "Previous messages" list: sender, date, body.
class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.message, required this.mine});

  final Message message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return GroupRow(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(mine ? 'You' : message.senderName,
                style: AppTextStyles.label.copyWith(color: mine ? AppColors.navy : AppColors.doctor)),
          ),
          Text('${Fmt.shortDate(message.sentAt)} · ${Fmt.time(message.sentAt)}', style: AppTextStyles.caption),
        ]),
        const SizedBox(height: AppSpacing.xs),
        Text(message.body, style: AppTextStyles.body.copyWith(color: AppColors.ink)),
        if (message.linkedTo != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(children: [
            const Icon(Icons.link_rounded, size: 16, color: AppColors.muted),
            const SizedBox(width: 4),
            Flexible(child: Text('Linked: ${message.linkedTo}', style: AppTextStyles.caption)),
          ]),
        ],
      ]),
    );
  }
}
