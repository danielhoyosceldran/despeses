import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/repositories/errors.dart';
import 'package:despeses/domain/repositories/payment_method_repository.dart';
import 'package:despeses/domain/repositories/profile_repository.dart';

void main() {
  late AppDatabase db;
  late PaymentMethodRepository methods;
  late ProfileRepository profile;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    methods = PaymentMethodRepository(db);
    profile = ProfileRepository(db);
  });
  tearDown(() => db.close());

  test('favorite: one at a time, cleared explicitly or when its method is deleted', () async {
    final a = await methods.create(name: 'A');
    final b = await methods.create(name: 'B');

    expect((await profile.get()).favoritePaymentMethodId, isNull);

    await profile.setFavoritePaymentMethod(a);
    expect((await profile.get()).favoritePaymentMethodId, a);

    await profile.setFavoritePaymentMethod(b);
    expect((await profile.get()).favoritePaymentMethodId, b);

    await profile.setFavoritePaymentMethod(null);
    expect((await profile.get()).favoritePaymentMethodId, isNull);

    await profile.setFavoritePaymentMethod(a);
    await methods.delete(a);
    expect((await profile.get()).favoritePaymentMethodId, isNull);
  });

  test('the last payment method cannot be deleted', () async {
    final all = await methods.listAll();
    for (final m in all.skip(1)) {
      await methods.delete(m.id);
    }
    final last = (await methods.listAll()).single;

    await expectLater(methods.delete(last.id), throwsA(isA<LastPaymentMethodException>()));
    expect((await methods.listAll()).single.id, last.id);
  });
}
