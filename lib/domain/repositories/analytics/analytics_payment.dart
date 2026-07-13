import '../../../data/database.dart';
import 'analytics_math.dart';
import 'analytics_query.dart';

/// Payment-method analytics (Analytics › Métodos de pago, section A5). Spend is
/// measured on `expense` transactions grouped by `paymentMethodId`.
class PaymentAnalytics {
  PaymentAnalytics(this._db);

  final AppDatabase _db;

  Future<List<Expense>> _spendTxns(DateRange range, String currency) async {
    final all = await expensesInRange(_db, range, currency);
    return all.where((e) => e.type == 'expense').toList();
  }

  /// A5.1 — total spend per payment method (null id = no method assigned).
  Future<Map<String?, int>> byMethod(DateRange range, String currency) async {
    final txns = await _spendTxns(range, currency);
    final result = <String?, int>{};
    for (final e in txns) {
      result[e.paymentMethodId] = (result[e.paymentMethodId] ?? 0) + e.amount;
    }
    return result;
  }

  /// A5.2 — average ticket per payment method.
  Future<Map<String?, double>> ticketByMethod(DateRange range, String currency) async {
    final txns = await _spendTxns(range, currency);
    final sums = <String?, int>{};
    final counts = <String?, int>{};
    for (final e in txns) {
      sums[e.paymentMethodId] = (sums[e.paymentMethodId] ?? 0) + e.amount;
      counts[e.paymentMethodId] = (counts[e.paymentMethodId] ?? 0) + 1;
    }
    return {for (final id in sums.keys) id: sums[id]! / counts[id]!};
  }

  /// A5.3 — share of spend that used [methodId] (e.g. the cash method). 0..1.
  Future<double> share(DateRange range, String currency, String methodId) async {
    final byMethod = await this.byMethod(range, currency);
    final total = byMethod.values.fold<int>(0, (s, v) => s + v);
    if (total == 0) return 0;
    return (byMethod[methodId] ?? 0) / total;
  }

  /// A5.4 — spend cross-tabbed method × category: `methodId → (categoryId → cents)`.
  Future<Map<String?, Map<String?, int>>> methodByCategory(DateRange range, String currency) async {
    final txns = await _spendTxns(range, currency);
    final result = <String?, Map<String?, int>>{};
    for (final e in txns) {
      final row = result.putIfAbsent(e.paymentMethodId, () => {});
      row[e.categoryId] = (row[e.categoryId] ?? 0) + e.amount;
    }
    return result;
  }
}
