import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/data/user_facing_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/state_views.dart';

/// An account as the admin sees it. Admins see no clinical data.
class AdminUser {
  const AdminUser({
    required this.id,
    required this.displayId,
    required this.role,
    required this.fullName,
    required this.email,
    this.doctorDisplayId,
    this.doctorName,
    this.patientCount,
  });

  final String id;
  final String displayId;
  final String role;
  final String fullName;
  final String email;
  final String? doctorDisplayId;
  final String? doctorName;
  final int? patientCount;

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: json['id'] as String,
        displayId: json['display_id'] as String? ?? '',
        role: json['role'] as String,
        fullName: json['full_name'] as String,
        email: json['email'] as String,
        doctorDisplayId: json['doctor_display_id'] as String?,
        doctorName: json['doctor_name'] as String?,
        patientCount: json['patient_count'] as int?,
      );
}

final adminUsersProvider = FutureProvider.autoDispose<List<AdminUser>>((ref) async {
  final rows = await ref.watch(apiClientProvider).getList('/admin/users');
  return rows.map(AdminUser.fromJson).toList();
});

/// The admin's only screen: every account with its ID, and "New account".
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final users = ref.watch(adminUsersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            key: const Key('adminLogout'),
            tooltip: 'Log out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => ref.read(sessionControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: AsyncValueView<List<AdminUser>>(
        value: users,
        onRetry: () => ref.invalidate(adminUsersProvider),
        data: (all) {
          List<AdminUser> of(String role) => all.where((u) => u.role == role).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
            children: [
              if (session != null) Text('${session.fullName} · ${session.subtitle}', style: AppTextStyles.caption),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                key: const Key('newAccount'),
                label: 'New account',
                icon: Icons.person_add_alt_1_rounded,
                onPressed: () async {
                  final created = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => NewAccountScreen(doctors: of('doctor'))),
                  );
                  if (created == true) ref.invalidate(adminUsersProvider);
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              for (final (title, role) in const [('DOCTORS', 'doctor'), ('PATIENTS', 'patient'), ('ADMINS', 'admin')])
                if (of(role).isNotEmpty) ...[
                  RowGroup(title: '$title (${of(role).length})', children: [
                    for (final user in of(role))
                      ListRowTile(
                        title: user.fullName,
                        subtitle: [
                          user.displayId,
                          user.email,
                          if (user.doctorDisplayId != null) 'Doctor ${user.doctorDisplayId} · ${user.doctorName}',
                          if (user.patientCount != null)
                            '${user.patientCount} ${user.patientCount == 1 ? 'patient' : 'patients'}',
                        ].join('\n'),
                      ),
                  ]),
                  const SizedBox(height: AppSpacing.xl),
                ],
            ],
          );
        },
      ),
    );
  }
}

/// Creates an account of any role. The server assigns the ID.
class NewAccountScreen extends ConsumerStatefulWidget {
  const NewAccountScreen({super.key, required this.doctors});

  final List<AdminUser> doctors;

  @override
  ConsumerState<NewAccountScreen> createState() => _NewAccountScreenState();
}

class _NewAccountScreenState extends ConsumerState<NewAccountScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _specialty = TextEditingController();
  String _role = 'patient';
  String _sex = 'female';
  String? _doctorId;
  DateTime? _birth;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.doctors.isNotEmpty) _doctorId = widget.doctors.first.displayId;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _specialty.dispose();
    super.dispose();
  }

  String? _check() {
    if (_name.text.trim().length < 2) return 'Enter the full name.';
    if (!_email.text.contains('@')) return 'Enter a valid email.';
    if (_password.text.length < 8) return 'The password needs at least 8 characters.';
    if (_role == 'patient' && _doctorId == null) return 'Create a doctor first: every patient has a doctor.';
    if (_role == 'patient' && _birth == null) return 'Choose the date of birth.';
    return null;
  }

  Future<void> _save() async {
    final problem = _check();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await ref.read(apiClientProvider).postJson('/admin/users', body: {
        'role': _role,
        'full_name': _name.text.trim(),
        'email': _email.text.trim(),
        'password': _password.text,
        if (_role == 'doctor') 'specialty': _specialty.text.trim(),
        if (_role == 'patient') ...{
          'doctor_display_id': _doctorId,
          'date_of_birth': DateFormat('yyyy-MM-dd').format(_birth!),
          'sex': _sex,
        },
      });
      if (!mounted) return;
      setState(() => _saving = false);
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Account created'),
          content: Text('${created['full_name']}\nID ${created['display_id']}\n\n'
              'They can log in with this ID or their email.'),
          actions: [TextButton(onPressed: () => Navigator.of(dialog).pop(), child: const Text('Done'))],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _choice(String label, List<(String, String)> options, String selected, ValueChanged<String> onPick) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.label),
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: AppSpacing.sm, children: [
            for (final (value, text) in options)
              ChoiceChip(
                key: Key('choice-$value'),
                label: Text(text),
                selected: selected == value,
                onSelected: (_) => onPick(value),
              ),
          ]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpacing.lg);
    return Scaffold(
      appBar: AppBar(title: const Text('New account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
          children: [
            _choice('Role', const [('patient', 'Patient'), ('doctor', 'Doctor'), ('admin', 'Admin')], _role,
                (v) => setState(() => _role = v)),
            gap,
            AppTextField(label: 'Full name', controller: _name, textInputAction: TextInputAction.next),
            gap,
            AppTextField(
              label: 'Email',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            gap,
            AppTextField(label: 'Password', controller: _password, hint: 'At least 8 characters'),
            if (_role == 'doctor') ...[
              gap,
              AppTextField(label: 'Specialty', controller: _specialty, hint: 'e.g. Neurologist'),
            ],
            if (_role == 'patient') ...[
              gap,
              const Text('Assigned doctor', style: AppTextStyles.label),
              const SizedBox(height: AppSpacing.sm),
              if (widget.doctors.isEmpty)
                const Text('No doctors yet. Create a doctor first.', style: AppTextStyles.bodySmall)
              else
                DropdownButtonFormField<String>(
                  key: const Key('doctorPicker'),
                  initialValue: _doctorId,
                  isExpanded: true,
                  items: [
                    for (final d in widget.doctors)
                      DropdownMenuItem(value: d.displayId, child: Text('${d.displayId} · ${d.fullName}')),
                  ],
                  onChanged: (v) => setState(() => _doctorId = v),
                ),
              gap,
              const Text('Date of birth', style: AppTextStyles.label),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                key: const Key('birthPicker'),
                label: _birth == null ? 'Choose date' : DateFormat('d MMM yyyy').format(_birth!),
                icon: Icons.calendar_today_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _birth ?? DateTime(1955),
                    firstDate: DateTime(1900),
                    lastDate: now,
                  );
                  if (picked != null) setState(() => _birth = picked);
                },
              ),
              gap,
              _choice('Sex', const [('female', 'Female'), ('male', 'Male')], _sex, (v) => setState(() => _sex = v)),
            ],
            gap,
            if (_error != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            AppButton(key: const Key('createAccount'), label: 'Create account', loading: _saving, onPressed: _save),
            const SizedBox(height: AppSpacing.md),
            const Text('The ID is assigned automatically: A- for admins, D- for doctors, P- for patients.',
                style: AppTextStyles.caption),
          ],
        ),
      ),
    );
  }
}
