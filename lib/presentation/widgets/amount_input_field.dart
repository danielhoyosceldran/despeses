import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';

/// Big amount hero edited with the device's own numeric keyboard.
///
/// Accepts `,` or `.` as decimal separator, up to 6 whole digits and 2
/// decimals. Callers keep working in cents: [onAmountChanged] always emits
/// `whole * 100 + cents`.
class AmountInputField extends StatefulWidget {
  const AmountInputField({
    super.key,
    required this.amountCents,
    required this.onAmountChanged,
    required this.focusNode,
    this.onSubmitted,
    this.currency,
    this.color,
  });

  final int amountCents;
  final ValueChanged<int> onAmountChanged;
  final FocusNode focusNode;

  /// Fired by the keyboard's action key (`Next`).
  final VoidCallback? onSubmitted;
  final String? currency;
  final Color? color;

  @override
  State<AmountInputField> createState() => _AmountInputFieldState();
}

class _AmountInputFieldState extends State<AmountInputField> {
  static const _maxWholeDigits = 6; // up to 999,999
  static final _pattern = RegExp(r'^\d{0,' '$_maxWholeDigits' r'}([.,]\d{0,2})?$');

  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.amountCents));
  }

  @override
  void didUpdateWidget(AmountInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Amount set from outside (edit mode loads the row after first build).
    if (widget.amountCents != _parse(_controller.text)) {
      _controller.text = _format(widget.amountCents);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _format(int cents) {
    if (cents == 0) return '';
    final whole = cents ~/ 100;
    final frac = cents % 100;
    if (frac == 0) return '$whole';
    return '$whole${decimalSeparatorFor()}${frac.toString().padLeft(2, '0')}';
  }

  static int _parse(String text) {
    if (text.isEmpty) return 0;
    final parts = text.split(RegExp('[.,]'));
    final whole = parts[0].isEmpty ? 0 : int.parse(parts[0]);
    final frac = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
    return whole * 100 + int.parse(frac);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final base = Theme.of(context).textTheme.displaySmall!.copyWith(
          color: widget.color ?? colors.text,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        IntrinsicWidth(
          child: TextField(
            controller: _controller,
            focusNode: widget.focusNode,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            textAlign: TextAlign.center,
            style: base,
            inputFormatters: [
              TextInputFormatter.withFunction(
                (oldValue, newValue) => _pattern.hasMatch(newValue.text) ? newValue : oldValue,
              ),
            ],
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: '0',
              hintStyle: base.copyWith(color: colors.textMuted),
            ),
            onChanged: (text) => widget.onAmountChanged(_parse(text)),
            onSubmitted: (_) => widget.onSubmitted?.call(),
          ),
        ),
        if (widget.currency != null) ...[
          const SizedBox(width: 6),
          Text(
            currencySymbolFor(widget.currency!),
            style: base.copyWith(color: colors.textMuted, fontSize: (base.fontSize ?? 32) * 0.55),
          ),
        ],
      ],
    );
  }
}
