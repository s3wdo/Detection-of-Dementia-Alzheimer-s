import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/data/repository_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../appointments_providers.dart';
import '../data/appointments_repository.dart';
import '../../../core/data/user_facing_error.dart';

/// Patient asks for an appointment. The doctor confirms it later.
class AppointmentRequestScreen extends ConsumerStatefulWidget {
  const AppointmentRequestScreen({super.key});

  @override
  ConsumerState<AppointmentRequestScreen> createState() => _AppointmentRequestScreenState();
}

class _AppointmentRequestScreenState extends ConsumerState<AppointmentRequestScreen> {
  static const reasons = ['Results discussion', 'Follow-up review', 'Neurology consultation', 'Other question'];
  static const slots = [
    TimeOfDay(hour: 9, minute: 0),
    TimeOfDay(hour: 10, minute: 30),
    TimeOfDay(hour: 13, minute: 0),
    TimeOfDay(hour: 15, minute: 30)
  ];

  String? _reason;
  DateTime? _date;
  TimeOfDay? _slot;
  final _notes = TextEditingController();
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 1)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 120)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _submit() async {
    final patientId = ref.read(sessionControllerProvider)?.patientId;
    if (patientId == null) return;
    if (_date == null || _slot == null) {
      setState(
          () => _errors = {'startsAt': 'Choose a date and a time.', if (_reason == null) 'reason': 'Choose a reason.'});
      return;
    }
    final request = AppointmentRequest(
      patientId: patientId,
      reason: _reason ?? '',
      startsAt: DateTime(_date!.year, _date!.month, _date!.day, _slot!.hour, _slot!.minute),
      notes: _notes.text,
    );
    final errors = request.validate(DateTime.now());
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    setState(() => _saving = true);
    try {
      await ref.read(appointmentsRepositoryProvider).request(request);
      refreshAppointments(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Request sent. Your doctor will confirm the appointment.')));
      context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userMessage(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book appointment')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
        children: [
          const Text('With Dr. Ahmed Khan · Neurology', style: AppTextStyles.bodySmall),
          const SizedBox(height: AppSpacing.xl),
          DropdownButtonFormField<String>(
            key: const Key('reason'),
            initialValue: _reason,
            decoration: InputDecoration(labelText: 'Reason', errorText: _errors['reason']),
            isExpanded: true,
            items: [
              for (final r in reasons) DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _reason = v),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            key: const Key('pickDate'),
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(_date == null ? 'Choose a date' : Fmt.weekday(_date!)),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text('Preferred time', style: AppTextStyles.label),
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            for (final s in slots)
              ChoiceChip(
                label: Text(s.format(context)),
                selected: _slot == s,
                onSelected: (_) => setState(() => _slot = s),
                showCheckmark: false,
              ),
          ]),
          if (_errors['startsAt'] != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_errors['startsAt']!, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Notes for the clinic (optional)'),
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppButton(key: const Key('sendRequest'), label: 'Send request', loading: _saving, onPressed: _submit),
          const SizedBox(height: AppSpacing.md),
          const Text('This is a request. The appointment is booked once your doctor confirms it.',
              style: AppTextStyles.caption, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
