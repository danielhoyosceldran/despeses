import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:despeses/core/format/date.dart';

void main() {
  test('the cached yMd format matches DateFormat.yMd() and is reused', () {
    final d = DateTime(2026, 7, 24, 18, 30);
    expect(cachedDateFormat(DateFormat.YEAR_NUM_MONTH_DAY).format(d), DateFormat.yMd().format(d));
    expect(
      identical(cachedDateFormat(DateFormat.YEAR_NUM_MONTH_DAY), cachedDateFormat(DateFormat.YEAR_NUM_MONTH_DAY)),
      isTrue,
    );
  });
}
