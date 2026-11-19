import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SessionCodeInput extends StatelessWidget {
  const SessionCodeInput({
    required this.onChanged,
    this.errorText,
    this.enabled = true,
    super.key,
  });

  final ValueChanged<String> onChanged;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      enabled: enabled,
      textCapitalization: TextCapitalization.characters,
      autocorrect: false,
      enableSuggestions: false,
      maxLength: 6,
      inputFormatters: [_SessionCodeTextFormatter()],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: 'Session code',
        hintText: 'FE237F',
        counterText: '',
        prefixIcon: const Icon(Icons.tag_rounded),
        errorText: errorText,
      ),
    );
  }
}

// Flutter appends its LengthLimitingTextInputFormatter (from `maxLength`)
// AFTER this widget's own inputFormatters, so it truncates on raw character
// count before we ever see the string. If we only upper-cased here, a pasted
// code like "SR-4F8K" (7 raw characters) would be cut to "SR-4F8" before the
// separator could be stripped, leaving a 5-character code that the backend's
// six-alphanumeric contract always rejects. Stripping non-alphanumerics here,
// before maxLength runs, ensures the length limiter counts only the
// characters the server actually cares about.
class _SessionCodeTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
