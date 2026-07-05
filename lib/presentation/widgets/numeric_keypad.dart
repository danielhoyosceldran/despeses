import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Money-entry keypad (plan §3.1): digits, `00`, comma, backspace, `Next`.
///
/// Amounts accumulate as cents (POS-style: each digit shifts the existing
/// value left and appends), which makes "max 2 decimals" automatic without
/// tracking cursor/decimal-point position. The `,` key is therefore a no-op
/// on the value itself (the web's `-` key is documented as vestigial in the
/// same way — plan §8) but is kept in the layout since users expect to see it.
class NumericKeypad extends StatelessWidget {
  const NumericKeypad({
    super.key,
    required this.amountCents,
    required this.onAmountChanged,
    required this.onNext,
    this.currency = 'EUR',
    this.nextLabel = 'Next',
  });

  final int amountCents;
  final ValueChanged<int> onAmountChanged;
  final VoidCallback onNext;
  final String currency;
  final String nextLabel;

  static const _maxCents = 99999999; // 999,999.99

  void _appendDigit(int digit) {
    final next = amountCents * 10 + digit;
    if (next > _maxCents) return;
    onAmountChanged(next);
  }

  void _appendDouble() {
    final next = amountCents * 100;
    if (next > _maxCents) return;
    onAmountChanged(next);
  }

  void _backspace() {
    onAmountChanged(amountCents ~/ 10);
  }

  String get _formattedAmount {
    final format = NumberFormat.currency(locale: 'en_US', symbol: '', decimalDigits: 2);
    return '${format.format(amountCents / 100)} $currency';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(_formattedAmount, style: Theme.of(context).textTheme.displaySmall),
              ),
              _KeypadGrid(
                onDigit: _appendDigit,
                onDouble: _appendDouble,
                onComma: () {},
                onBackspace: _backspace,
              ),
            ],
          ),
        ),
        SizedBox(
          width: 56,
          child: FilledButton(
            style: FilledButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: amountCents > 0 ? onNext : null,
            child: RotatedBox(
              quarterTurns: 1,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(nextLabel),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward, size: 16),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _KeypadGrid extends StatelessWidget {
  const _KeypadGrid({
    required this.onDigit,
    required this.onDouble,
    required this.onComma,
    required this.onBackspace,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onDouble;
  final VoidCallback onComma;
  final VoidCallback onBackspace;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    [',', '0', '00'],
    ['⌫'],
  ];

  void _handle(String key) {
    switch (key) {
      case ',':
        onComma();
      case '00':
        onDouble();
      case '⌫':
        onBackspace();
      default:
        onDigit(int.parse(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _rows)
          Row(
            children: [
              for (final key in row)
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: TextButton(
                      key: ValueKey('keypad_$key'),
                      onPressed: () => _handle(key),
                      child: Text(key, style: Theme.of(context).textTheme.headlineSmall),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
