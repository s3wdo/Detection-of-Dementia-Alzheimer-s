import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/server_finder.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';

/// Lets the server address be typed or found on the phone's Wi-Fi.
/// Pops with the text to save, '' to reset, or null when dismissed.
class ServerAddressDialog extends ConsumerStatefulWidget {
  const ServerAddressDialog({super.key, required this.current, this.showFind = true});

  final String current;

  /// False in a browser, where the page's own server is used.
  final bool showFind;

  @override
  ConsumerState<ServerAddressDialog> createState() => _ServerAddressDialogState();
}

enum _FindState { idle, searching, found, notFound }

class _ServerAddressDialogState extends ConsumerState<ServerAddressDialog> {
  late final _field = TextEditingController(text: widget.current);
  _FindState _state = _FindState.idle;
  int _done = 0, _total = 0;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    setState(() {
      _state = _FindState.searching;
      _done = 0;
      _total = 0;
    });
    String? host;
    try {
      host = await ref.read(serverFinderProvider)((done, total) {
        if (mounted) setState(() { _done = done; _total = total; });
      });
    } catch (_) {
      host = null;
    }
    if (!mounted) return;
    setState(() {
      if (host != null) _field.text = host;
      _state = host == null ? _FindState.notFound : _FindState.found;
    });
  }

  @override
  Widget build(BuildContext context) {
    final searching = _state == _FindState.searching;
    return AlertDialog(
      title: const Text('Server address'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('serverAddressField'),
              controller: _field,
              enabled: !searching,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: '192.168.1.20'),
            ),
            if (widget.showFind) ...[
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                key: const Key('findServerButton'),
                label: searching ? 'Searching…' : 'Find server on this Wi-Fi',
                icon: Icons.wifi_find,
                variant: AppButtonVariant.secondary,
                loading: searching,
                onPressed: _find,
              ),
              const SizedBox(height: AppSpacing.md),
              _status(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: searching ? null : () => Navigator.of(context).pop(''), child: const Text('Reset')),
        TextButton(
          key: const Key('saveServerButton'),
          onPressed: searching ? null : () => Navigator.of(context).pop(_field.text),
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _status() {
    switch (_state) {
      case _FindState.idle:
        return const Text(
          'Looks for the NeuroSense server on the same Wi-Fi as this phone.',
          style: AppTextStyles.caption,
        );
      case _FindState.searching:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: _total == 0 ? null : _done / _total,
              backgroundColor: AppColors.surfaceAlt,
              color: AppColors.primary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _total == 0 ? 'Checking this Wi-Fi…' : 'Checked $_done of $_total addresses',
              style: AppTextStyles.caption,
            ),
          ],
        );
      case _FindState.found:
        return _note(
          key: const Key('serverFound'),
          icon: Icons.check_circle_outline,
          color: AppColors.success,
          text: 'Found NeuroSense at ${_field.text}. Tap Save to use it.',
        );
      case _FindState.notFound:
        return _note(
          key: const Key('serverNotFound'),
          icon: Icons.error_outline,
          color: AppColors.error,
          text: 'No NeuroSense server found. Check that the laptop is on this Wi-Fi '
              'and the server is running, or type its address.',
        );
    }
  }

  Widget _note({required Key key, required IconData icon, required Color color, required String text}) {
    return Row(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: AppTextStyles.caption.copyWith(color: color))),
      ],
    );
  }
}
