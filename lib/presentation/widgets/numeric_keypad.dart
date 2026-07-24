import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Money-entry keypad (plan §3.1 redesign): 4x4 grid with digits, `00`, `,`,
/// backspace, and `Next` spanning the last two rows.
///
/// Amounts are entered as euros by default; tapping `,` switches into cents
/// mode for up to two more digits. `amountCents` is always the derived total
/// (`whole * 100 + cents`), so callers keep working in cents unchanged.
class NumericKeypad extends StatefulWidget {
  const NumericKeypad({
    super.key,
    required this.amountCents,
    required this.onAmountChanged,
    required this.onNext,
    this.nextLabel = 'Next',
    this.onKeyTap,
  });

  final int amountCents;
  final ValueChanged<int> onAmountChanged;
  final VoidCallback onNext;
  final String nextLabel;

  /// Fired on every physical key press (before the action runs). Callers use it
  /// for haptic feedback via `HapticsService`; keep the keypad platform-free.
  final VoidCallback? onKeyTap;

  @override
  State<NumericKeypad> createState() => _NumericKeypadState();
}

class _NumericKeypadState extends State<NumericKeypad> {
  static const _maxWholeDigits = 6; // up to 999,999
  String _whole = '';
  String _cents = '';
  bool _hasComma = false;

  @override
  void initState() {
    super.initState();
    _whole = (widget.amountCents ~/ 100).toString();
    if (_whole == '0') _whole = '';
  }

  void _emit() {
    final whole = _whole.isEmpty ? 0 : int.parse(_whole);
    final cents = _cents.padRight(2, '0');
    widget.onAmountChanged(whole * 100 + int.parse(cents.isEmpty ? '0' : cents));
  }

  void _digit(int d) {
    if (_hasComma) {
      if (_cents.length >= 2) return;
      setState(() => _cents += '$d');
    } else {
      if (_whole.length >= _maxWholeDigits) return;
      setState(() => _whole += '$d');
    }
    _emit();
  }

  void _double() {
    _digit(0);
    _digit(0);
  }

  void _comma() {
    if (_hasComma) return;
    setState(() => _hasComma = true);
  }

  void _backspace() {
    if (_hasComma) {
      if (_cents.isNotEmpty) {
        setState(() => _cents = _cents.substring(0, _cents.length - 1));
      } else {
        setState(() => _hasComma = false);
      }
    } else if (_whole.isNotEmpty) {
      setState(() => _whole = _whole.substring(0, _whole.length - 1));
    }
    _emit();
  }

  /// Fire the caller's key-tap feedback, then run the key's action.
  void _tap(VoidCallback action) {
    widget.onKeyTap?.call();
    action();
  }

  @override
  Widget build(BuildContext context) {
    // Fill the panel height (matching the calendar / picker panels) instead of
    // a fixed height, so keys grow taller when there's room.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          Expanded(child: _KeyColumn(labels: const ['1', '4', '7', '00'], onTap: (l) => _tap(() => l == '00' ? _double() : _digit(int.parse(l))))),
          Expanded(child: _KeyColumn(labels: const ['2', '5', '8', '0'], onTap: (l) => _tap(() => _digit(int.parse(l))))),
          Expanded(child: _KeyColumn(labels: const ['3', '6', '9', ','], onTap: (l) => _tap(() => l == ',' ? _comma() : _digit(int.parse(l))))),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  flex: 2,
                  child: _Key(key: const ValueKey('keypad_⌫'), onTap: () => _tap(_backspace), child: const Text('⌫')),
                ),
                Expanded(
                  flex: 2,
                  child: _Key(
                    key: const ValueKey('keypad_next'),
                    onTap: () => _tap(widget.onNext),
                    accent: true,
                    child: Semantics(
                      label: widget.nextLabel,
                      button: true,
                      child: const Icon(LucideIcons.arrowRight300),
                    ),
                  ),
                ),
              ],
            ),
          ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KeyColumn extends StatelessWidget {
  const _KeyColumn({required this.labels, required this.onTap});

  final List<String> labels;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final label in labels)
          Expanded(child: _Key(key: ValueKey('keypad_$label'), child: Text(label), onTap: () => onTap(label))),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({super.key, required this.child, required this.onTap, this.accent = false});

  final Widget child;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: SizedBox.expand(
        child: TextButton(
          style: TextButton.styleFrom(
            backgroundColor: accent ? colors.accent : null,
            foregroundColor: accent ? colors.onAccent : colors.text,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimens.radiusButton)),
          ),
          onPressed: onTap,
          child: DefaultTextStyle.merge(
            style: Theme.of(context)
                .textTheme
                .headlineSmall!
                .copyWith(color: accent ? colors.onAccent : colors.text),
            child: child,
          ),
        ),
      ),
    );
  }
}
