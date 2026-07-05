import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';

const _uuid = Uuid();

class PaymentMethodRepository {
  PaymentMethodRepository(this._db);

  final AppDatabase _db;

  Future<List<PaymentMethod>> listAll() {
    return (_db.select(_db.paymentMethods)
          ..orderBy([(p) => OrderingTerm(expression: p.position)]))
        .get();
  }

  Future<String> create({required String name, String? icon}) async {
    final id = _uuid.v4();
    final all = await listAll();
    await _db.into(_db.paymentMethods).insert(
          PaymentMethodsCompanion.insert(
            id: id,
            name: name,
            icon: Value(icon),
            position: Value(all.length),
          ),
        );
    return id;
  }

  Future<void> rename(String id, String newName) async {
    await (_db.update(_db.paymentMethods)..where((p) => p.id.equals(id))).write(
      PaymentMethodsCompanion(
        name: Value(newName),
        isDefault: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateIcon(String id, String? icon) async {
    await (_db.update(_db.paymentMethods)..where((p) => p.id.equals(id))).write(
      PaymentMethodsCompanion(icon: Value(icon), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.paymentMethods)..where((p) => p.id.equals(id))).go();
  }

  Future<void> reorder(List<String> orderedIds) async {
    await _db.batch((batch) {
      for (var i = 0; i < orderedIds.length; i++) {
        batch.update(
          _db.paymentMethods,
          PaymentMethodsCompanion(position: Value(i)),
          where: (p) => p.id.equals(orderedIds[i]),
        );
      }
    });
  }
}
