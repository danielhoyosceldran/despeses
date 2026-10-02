# Baseline del esquema de base de datos

**Baseline: schema v9** (`AppDatabase.baselineSchemaVersion` en `lib/data/database.dart`).
Fijada el 2026-10-02.

## Decisión

El estado actual de la base de datos (schema v9) es el punto de partida de
**todas** las instalaciones. No existe ninguna instalación con un esquema
anterior: la única instalación real (la del autor) ya está en v9. Se verificó
con su backup `despeses_backup_2026-10-02T13-37-58` (`PRAGMA user_version = 9`).
Su esquema coincide tabla a tabla y columna a columna con `lib/data/tables.dart`
y con los índices de `database.dart`.

Por eso se eliminaron de `onUpgrade` los pasos históricos:

- reconstrucción destructiva para `from < 7`,
- `from < 8`: creación de `recurrings`, `recurring_tags`, `recurring_occurrences` e índices,
- `from < 9`: creación de `savings_goals`.

## Comportamiento

| Caso | Qué pasa |
|---|---|
| Instalación nueva | `onCreate` construye el esquema actual completo + seed + índices. |
| Instalación en la baseline (v9) o superior | `onUpgrade` aplica solo los pasos `if (from < N)` con `N > 9`. |
| Fichero anterior a la baseline (p. ej. un backup antiguo restaurado) | Se hace el auto-backup `pre_migration` y se lanza `UnsupportedError`. El fichero no se modifica ni se borra. |

## Esquema v9 (referencia)

Tablas: `profile`, `tag_groups`, `tags`, `categories`, `payment_methods`,
`events`, `projects`, `expenses`, `expense_tags`, `budgets`, `recurrings`,
`recurring_tags`, `recurring_occurrences`, `savings_goals`.

Índices: `idx_expenses_date`, `idx_expenses_category`, `idx_recurrings_next`,
`idx_recurring_occ_due`.

La fuente de verdad de las columnas es `lib/data/tables.dart`.

### Columnas sin uso conservadas a propósito

- `profile.haptics_strength`: guardaba la intensidad de la vibración
  (0 suave, 1 media, 2 fuerte). La opción se retiró de la UI porque
  `HapticFeedback` no permite ajustar la intensidad, pero la columna **se
  conserva** (decisión 2026-10-02, BL-047): no se descarta recuperar esa
  configuración. **No** la elimines en una migración.

## Reglas para futuras migraciones

1. Cada cambio de esquema sube `schemaVersion` y añade en el mismo cambio un
   paso acumulativo `if (from < N)` en `onUpgrade` (ver comentarios en
   `database.dart` y `tables.dart`).
2. **No** subas `baselineSchemaVersion` mientras pueda existir una instalación
   en una versión anterior. Al subirla, borra los pasos que queden por debajo
   y actualiza este documento y `test/data/migration_test.dart`.
3. Los backups de una versión anterior a la baseline no se pueden restaurar
   (ver BL-030 en `docs/backlog.csv` para validarlo antes de reemplazar la BD).
