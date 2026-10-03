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

## Migraciones posteriores a la baseline

| Versión | Cambio |
|---|---|
| v10 | `profile.favorite_payment_method_id` (BL-024). Columna nueva, declarada en `columnsAddedInVersion`. |
| v11 | Fechas contables como fecha/hora civil (BL-042). Sin columnas nuevas: paso de datos `_convertToCivilDates`. |

### Fechas contables (v11, BL-042)

Las columnas de `AppDatabase.civilDateColumns` (`expenses.date`,
`recurrings.start_date/next_date/end_date`, `recurring_occurrences.due_date`,
`events`/`projects.starts_at/ends_at`, `savings_goals.deadline`) usan
`CivilDateTimeType` (`lib/data/civil_date_time.dart`): siguen siendo INTEGER en
segundos, pero guardan los componentes de reloj local (año…segundo)
codificados como si fueran UTC, y se leen como un `DateTime` local con esos
mismos componentes. Así un movimiento de las 00:30 en Madrid sigue siendo de
ese día (y mes) aunque el móvil esté en otra zona horaria.

- El paso v11 reescribe los valores antiguos (instantes) con la hora de pared
  que tenían en la zona del dispositivo al migrar. Lo precede el auto-backup
  `pre_migration`, como toda migración.
- `created_at`, `updated_at` y `recurrings.last_posted_at` son instantes y
  mantienen el `dateTime()` de drift.
- Las consultas del query builder (`isBiggerOrEqualValue`, `equals`…) ya
  vinculan los valores con el tipo civil. En SQL crudo (`customSelect`) hay que
  usar `civilVariable(fecha)`, **nunca** `Variable<DateTime>(fecha)`.
- Una columna de fecha contable nueva se declara con
  `customType(civilDateTimeType)` y se añade a `civilDateColumns`.

## Reglas para futuras migraciones

1. Cada cambio de esquema sube `schemaVersion` y añade en el mismo cambio un
   paso acumulativo `if (from < N)` en `onUpgrade` (ver comentarios en
   `database.dart` y `tables.dart`).
2. **No** subas `baselineSchemaVersion` mientras pueda existir una instalación
   en una versión anterior. Al subirla, borra los pasos que queden por debajo
   y actualiza este documento y `test/data/migration_test.dart`.
3. Las columnas nuevas en tablas existentes se declaran en
   `AppDatabase.columnsAddedInVersion` (versión → tabla → columnas). `onUpgrade`
   añade esas columnas a partir de ese mapa, y la validación de backups lo usa
   para saber qué columnas debe tener un fichero de cada versión
   (`AppDatabase.schemaColumnsAt`).
4. Los backups de una versión anterior a la baseline (o posterior a
   `AppDatabase.currentSchemaVersion`) no se pueden restaurar:
   `BackupService.validateBackup` los rechaza antes de reemplazar la BD.

## Restaurar un backup: columnas

`BackupService.validateBackup` compara las columnas de cada tabla del backup con
las que corresponden a su `user_version`:

| Caso | Qué pasa |
|---|---|
| Columnas exactas de su versión | Se restaura; si la versión es antigua, `onUpgrade` migra al reabrir. |
| Faltan columnas que añade algún paso de migración (p. ej. dice v10 pero no tiene `profile.favorite_payment_method_id`) | Se restaura y la **copia restaurada** (no el fichero elegido) se marca con la versión que sus columnas cumplen de verdad, así que `onUpgrade` añade las que faltan al reabrir. |
| Columnas de más (`extraColumns`) | Se rechaza sin tocar nada, con un mensaje que lista `tabla.columna`. |
| Faltan columnas que ninguna migración añade (`missingColumns`) | Se rechaza sin tocar nada, con un mensaje que lista `tabla.columna`. |
