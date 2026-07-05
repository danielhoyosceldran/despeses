import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';

const _uuid = Uuid();

class EventRepository {
  EventRepository(this._db);

  final AppDatabase _db;

  Future<List<Event>> listAll() {
    return (_db.select(_db.events)..orderBy([(e) => OrderingTerm(expression: e.name)])).get();
  }

  Future<String> create({
    required String name,
    String? description,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    final id = _uuid.v4();
    await _db.into(_db.events).insert(
          EventsCompanion.insert(
            id: id,
            name: name,
            description: Value(description),
            startsAt: Value(startsAt),
            endsAt: Value(endsAt),
          ),
        );
    return id;
  }

  Future<void> update(
    String id, {
    String? name,
    String? description,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    await (_db.update(_db.events)..where((e) => e.id.equals(id))).write(
      EventsCompanion(
        name: name == null ? const Value.absent() : Value(name),
        description: Value(description),
        startsAt: Value(startsAt),
        endsAt: Value(endsAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> budgetCount(String id) async {
    final count = _db.budgets.id.count();
    final query = _db.selectOnly(_db.budgets)
      ..addColumns([count])
      ..where(_db.budgets.eventId.equals(id));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.events)..where((e) => e.id.equals(id))).go();
  }
}

class ProjectRepository {
  ProjectRepository(this._db);

  final AppDatabase _db;

  Future<List<Project>> listAll() {
    return (_db.select(_db.projects)..orderBy([(p) => OrderingTerm(expression: p.name)])).get();
  }

  Future<String> create({
    required String name,
    String? description,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    final id = _uuid.v4();
    await _db.into(_db.projects).insert(
          ProjectsCompanion.insert(
            id: id,
            name: name,
            description: Value(description),
            startsAt: Value(startsAt),
            endsAt: Value(endsAt),
          ),
        );
    return id;
  }

  Future<void> update(
    String id, {
    String? name,
    String? description,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    await (_db.update(_db.projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(
        name: name == null ? const Value.absent() : Value(name),
        description: Value(description),
        startsAt: Value(startsAt),
        endsAt: Value(endsAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> budgetCount(String id) async {
    final count = _db.budgets.id.count();
    final query = _db.selectOnly(_db.budgets)
      ..addColumns([count])
      ..where(_db.budgets.projectId.equals(id));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.projects)..where((p) => p.id.equals(id))).go();
  }
}
