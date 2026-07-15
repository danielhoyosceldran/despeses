# Auditoría del proyecto

> App: **despeses** (finanzas personales, uso individual) · Flutter · Riverpod · Drift · go_router · Material 3
> Fecha: 2026-07-15 · Alcance: `lib/` completo (77 archivos, ~12.200 LOC) + `test/` + configuración.
> Criterio: solo se listan problemas reales cuyo beneficio de arreglo supera al coste. Lo que ya está bien para el tamaño de la app no se menciona.

---

## Resumen ejecutivo

El proyecto está, en general, **bien construido para una app personal**: dinero en enteros (céntimos), no en `double`; repositorios con transacciones en las escrituras multi-fila; capas separadas (`data` / `domain` / `presentation` / `core`); estado con Riverpod sin sobreingeniería; y una base de tests razonable (621 LOC). `flutter analyze` sale casi limpio (5 avisos `info`).

Hay **dos problemas graves** que no son de estilo sino de **integridad de datos**, y que conviene resolver antes que nada porque afectan a datos financieros reales que ya usas:

1. **Cualquier cambio de esquema borra toda tu base de datos** (`onUpgrade` hace drop + reseed).
2. **El backup/restore no es seguro con WAL**: copia el `.sqlite` abierto sin checkpoint e ignora los ficheros `-wal`/`-shm`. La única red de seguridad que tienes puede perder las últimas transacciones o dejar la base corrupta al restaurar.

Después vienen mejoras de **rendimiento en analytics** (futures creados dentro de `build`, patrón N+1, índices ausentes), **formato de dinero** (no respeta el locale ni el símbolo de moneda, y está duplicado en 6+ sitios), **i18n incompleto** (cadenas en inglés incrustadas, y códigos internos tipo `A1.4` mostrados al usuario) y **duplicación de widgets/pantallas CRUD**.

Nada de esto requiere reescribir la arquitectura. Son arreglos localizados y de bajo riesgo, ordenados abajo por prioridad.

---

## Mejoras prioritarias

| # | Mejora | Área | Impacto | Dificultad | Tiempo | Prioridad |
|---|--------|------|:-------:|:----------:|:------:|:---------:|
| 1 | Migración que no borre los datos + auto-backup antes de migrar | Datos | 5 | 3 | 0.5–1 d | 🔴 Crítica |
| 2 | Backup/restore seguro con WAL (checkpoint + borrar sidecars) | Datos | 5 | 2 | 2–3 h | 🔴 Crítica |
| 3 | Sacar los `future:` de `build()` en analytics (tormenta de refetch al arrastrar) | Rendimiento | 4 | 3 | 3–4 h | 🟠 Alta |
| 4 | Manejar `snapshot.hasError` (spinner infinito ante error) | UX/Rob. | 3 | 2 | 2 h | 🟠 Alta |
| 5 | Formateador de dinero único, locale-aware (símbolo + separadores) | UI/Código | 3 | 2 | 2–3 h | 🟠 Alta |
| 6 | Matar el N+1 de analytics (`descendantIds`, `calculateProgress`) + índices | Rendimiento | 3 | 2 | 3 h | 🟠 Alta |
| 7 | `expense_entry`: rebuild por tecla y parpadeo de labels | Rendimiento/UX | 3 | 2 | 1–2 h | 🟡 Media |
| 8 | Completar i18n (cadenas en inglés) y quitar códigos `A1.4` de la UI | UI/i18n | 3 | 3 | 3–4 h | 🟡 Media |
| 9 | Unificar widgets duplicados (fila de gasto, progreso de presupuesto, empty state, pager de mes) | Código | 3 | 3 | 4–6 h | 🟡 Media |
| 10 | Rollback en borrados optimistas | Robustez | 2 | 2 | 1 h | 🟡 Media |
| 11 | Centralizar la lógica de signo por tipo (`refund` negativo) | Código | 2 | 2 | 1 h | 🟢 Baja |
| 12 | Formato de `month-key` único + comparación de meses robusta | Código | 2 | 2 | 1–2 h | 🟢 Baja |
| 13 | Limpieza: columna `hapticsStrength` muerta, `onReorder` deprecado, guardas de ciclo/scope | Deuda | 1 | 1 | 1 h | 🟢 Baja |

**Funcionalidad** (aparte de bugs): las carencias de finanzas personales con más valor real son **movimientos recurrentes** y **objetivos de ahorro** (ver sección Funcionalidades).

---

## Arquitectura

La estructura por capas es correcta y proporcionada; **no** recomiendo Clean Architecture formal (casos de uso, interfaces de repositorio, entidades de dominio separadas de las de Drift): el beneficio para una app de un solo usuario es marginal y añadiría mucha ceremonia. Los repositorios ya actúan de frontera y eso es suficiente.

Problemas que sí merece la pena tocar:

### A1. La migración destruye los datos del usuario 🔴

`lib/data/database.dart:75-83`

```dart
onUpgrade: (m, from, to) async {
  await customStatement('PRAGMA foreign_keys = OFF');
  for (final table in allTables) {
    await m.deleteTable(table.actualTableName);   // ← borra TODO
  }
  await m.createAll();
  await _seedDefaults(this);                        // ← reseed desde cero
  ...
},
```

- **Problema:** con `schemaVersion = 6` y cero migraciones reales, subir la versión del esquema borra la base entera y la re-siembra. Está comentado como "dev app", pero la app ya tiene función de backup, lo que implica datos reales que quieres conservar.
- **Por qué merece la pena:** es una pérdida total de datos silenciosa. En cuanto añadas una columna o una tabla (p. ej. recurrentes u objetivos de ahorro), la próxima apertura de la app te vacía todos los gastos.
- **Impacto:** 5 · **Dificultad:** 3 · **Tiempo:** 0,5–1 día.
- **Propuesta (mínima, sin sobreingeniería):**
  1. Crear una **auto-copia de seguridad antes de migrar** (reutiliza `BackupService.createBackup`) en `beforeOpen` cuando `details.hadUpgrade`.
  2. Escribir migraciones reales con `drift`'s `Migrator` (`m.addColumn`, `m.createTable`) en lugar del drop global. Para cambios de datos de seed usa un paso puntual, no un reseed total.
  3. Si de verdad quieres seguir reseeding en desarrollo, protégelo con un flag de build (`kDebugMode` o `FeatureFlags`) para que **nunca** ocurra en un binario de uso real.

### A2. `intl` está como dependencia pero no se usa para dinero/fechas

El `pubspec` incluye `intl`, pero el dinero se formatea a mano con `toStringAsFixed(2)` en 6+ sitios (ver C1) y no hay `NumberFormat`/`DateFormat` locale-aware. O se usa `intl`, o sobra en `pubspec`. Recomendado: usarlo (resuelve C1 y U-fechas de paso).

### A3. El `ReferenceDataCache` existe pero no se usa donde importa

`lib/domain/repositories/reference_data_cache.dart` cachea categorías, pero el camino caliente de analytics (`descendantIds()` → `listAll()`) va directo a la BD (ver R2). El caché que mataría el N+1 está ahí sin aprovechar. Enrutar analytics de categorías por el caché es la mejora de arquitectura con mejor relación beneficio/coste.

---

## Calidad del código

### C1. Formato de dinero duplicado y no locale-aware 🟠

Presente en `dashboard_screen.dart:544,596,698`, `expenses_screen.dart:237`, `budgets_screen.dart:174`, `charts/analytics_widgets.dart:7`, `export_service.dart:47`, `amount_text.dart:19`:

```dart
'$sign${(expense.amount / 100).toStringAsFixed(2)} ${expense.currency}'
```

- **Problema:** (a) misma lógica repetida en 6+ ficheros; (b) muestra `1234.56 EUR` en vez de `1.234,56 €` — sin separador de miles, con punto decimal fijo y el **código** de moneda en lugar del símbolo. La app soporta es/ca/fr/it, que usan coma decimal.
- **Impacto:** 3 · **Dificultad:** 2 · **Tiempo:** 2–3 h.
- **Propuesta:** un único helper y borrar las 6 copias.

```dart
// lib/core/format/money.dart
String formatMoney(int cents, String currency, String locale) =>
    NumberFormat.currency(locale: locale, name: currency).format(cents / 100);
```

`AmountText` puede seguir partiendo entero/decimales, pero tomando la cadena ya formateada de este helper.

### C2. Códigos internos de spec mostrados al usuario 🟡

`analytics_sections.dart` (líneas 114, 201, 216, 224, 307, 315, 332, 384, 445, 454, 462, 509, 548, 711, 718): subtítulos de `StatCard` como `'A1.4'`, `'A2.1'`, `'A7.1–A7.3'`. Son referencias internas del plan que se están **mostrando en pantalla**.
- **Impacto:** 2 · **Dificultad:** 1 · **Tiempo:** 20 min. Arreglo trivial y visible.

### C3. Lógica de signo por tipo duplicada

`type == 'refund' ? -amount : amount` reimplementado en `budget_repository.dart:145`, `analytics_timeseries.dart:79,95`, `analytics_events.dart:65`, `analytics_tags.dart:77`, aunque ya existe `analytics_math.dart:40 signedSpend`. Un cambio en las reglas contables (nuevo tipo) obliga a editar 5+ sitios. Centralizar en `analytics_math`.
- **Impacto:** 2 · **Dificultad:** 2.

### C4. Dos formatos de `month-key` conviviendo

`budget_repository.dart:9 monthKeyOf` produce `YYYY-MM` con cero a la izquierda; analytics usa `'${date.year}-${date.month}'` sin padding (`cashflow:39`, `timeseries:29`, `behavior:44`, `category:151`). Cada uno es internamente consistente (no es bug vivo), pero es frágil e invita al error de C5. Unificar en un único `monthKeyOf`.

### C5. Comparación de meses con `String.compareTo` asumiendo zero-padding

`budget_repository.dart:48,96-98,156-158` y `analytics_budgets.dart:52-55` comparan rangos `startsMonth`/`endsMonth` con `compareTo` y `split('-')`, asumiendo `YYYY-MM` padded. Si alguna vez se guarda `2026-3`, la comparación lexical se rompe (`'2026-3' > '2026-12'`). El formato lo pone el llamante y no está forzado.
- **Impacto:** 3 (condicional) · **Dificultad:** 2. Arreglo: comparar por `(year, month)` numérico o garantizar el padding en un único punto de escritura.

### C6. Lógica de dominio dentro de la UI

- `dashboard_screen.dart:227-249,535-572`: `_Totals.of` (reglas de signo de expense/refund/income), `_groupByDay`, `_signedCents` — agregación contable en el widget.
- `export_screen.dart:42-71`: `_buildRows` monta 5 mapas de lookup + joins de tags en la pantalla; es trabajo del `ExportService`.

No urge, pero mover esto al dominio facilita testear y evita divergencias (p. ej. dashboard y budgets calculan "progreso" distinto, ver R3).

### C7. `dynamic` que pierde tipado

`analytics_sections.dart:488 _BehaviorData.stats` es `dynamic`. Tipar la clase de stats de tickets. Impacto 1.

### C8. Código/columna muertos

- `Profile.hapticsStrength` (`tables.dart:9-10`) + `ProfileRepository.setHapticsStrength` (`:41-46`): la feature se retiró (confirmado en `haptics.dart:19`). Superficie muerta. Si no vas a reintroducir intensidad, elimínala en la próxima migración real (que hay que crear por A1 de todos modos).
- `test/widget_test.dart` (18 líneas) parece el test por defecto de Flutter; si es el contador plantilla, bórralo.

---

## Rendimiento

> Nota: el volumen de datos de una app personal es pequeño, así que nada de esto **crashea**. Pero son trabajos evitables y algunos causan parpadeos visibles.

### R1. Futures creados dentro de `build()` → refetch en cada frame de arrastre 🟠

`analytics_screen.dart:555,699` y `analytics_sections.dart` (90,147,185,297,373,428,505,537,643,691): cada sección hace `future: _load(ref)` **inline en `build`**.

- **Problema:** el future se recrea en cada rebuild y vuelve a lanzar la query + parpadea el spinner. Peor: el **arrastre de preview del FAB** llama a `setState` cada frame (`analytics_screen.dart:152-155`), que reconstruye el `itemBuilder` del `PageView` (`:211-214`) y **re-dispara todas las queries de la sección en cada frame del gesto**.
- **Impacto:** 4 · **Dificultad:** 3 · **Tiempo:** 3–4 h.
- **Propuesta:** convertir cada cálculo de sección en un `FutureProvider.family` cacheado por (mes, sección), o al menos memoizar el future en el `State` y recrearlo solo cuando cambie el mes. Riverpod ya cachea por argumentos, así que un `FutureProvider.family` es lo más natural aquí.

### R2. N+1 apilado en analytics de categorías y presupuestos 🟠

- `category_repository.dart:113-114 descendantIds` hace `await listAll()` (escaneo completo de categorías) **en cada llamada**, y se llama en bucle en `analytics_category.dart:60,82,118` (una vez por hijo/raíz).
- `budget_repository.dart:111-141 calculateProgress` **no acota por fecha**: un presupuesto `monthly` carga todo el histórico de su categoría y filtra a un mes en Dart (`:141`).
- `analytics_dashboard.dart:67-72` recorre los presupuestos activos y por cada uno llama `pace()` → `calculateProgress` (N+1) + `descendantIds` (otro N+1), en la pantalla más caliente.
- **Impacto:** 3 · **Dificultad:** 2 · **Propuesta:** (a) acotar `calculateProgress` por rango de fechas en SQL; (b) resolver `descendantIds` desde el `ReferenceDataCache` (A3) o cachear el árbol una vez por render.

### R3. Índices ausentes

`tables.dart:137-163 (Expenses)`: sin índice en `date`, `type`, `currency` ni en las FK (`categoryId`, `paymentMethodId`, `eventId`, `projectId`). Todas las queries de analytics/listado son table scans.
- **Impacto:** 2 · **Dificultad:** 2 · Añadir índices en `date` y `categoryId` (los más consultados) en la próxima migración.

### R4. `expense_entry`: rebuild por pulsación y parpadeo de labels 🟡

`expense_entry_screen.dart:74` hace `_descriptionController.addListener(() => setState((){}))` → reconstruye toda la pantalla en **cada tecla**, y `_buildFieldsView` crea `future: _resolveLabels()` inline en `build`. Mientras el future está pendiente, `snapshot.data` es null y los tiles de Categoría/Método/Evento/Proyecto **vuelven a su placeholder en cada tecla**. Solo el botón Guardar necesita el texto.
- **Impacto:** 3 · **Dificultad:** 2 · **Propuesta:** escuchar el controller solo para habilitar Guardar (`ValueListenableBuilder` sobre el botón), y resolver labels una vez fuera de `build`.

### R5. Otros N+1 menores

- `dashboard_screen.dart:665,709 _ExpenseRow`: un `FutureBuilder<String?>` por fila lee toda la lista de categorías del caché; resolver los labels una vez en la carga del mes.
- `export_screen.dart:57-59`: `for (final e in expenses) ... await expenseRepo.tagIdsOf(e.id)` → N+1 en exportaciones que pueden abarcar años. Batch en el repo.
- `dashboard_screen.dart:45,84-98,124-132`: caché de mes manual (`_expenseCache`) con invalidación a mano (hay que acordarse de `remove(_monthKey)` tras editar). Frágil; un `FutureProvider.family(mes)` lo da gratis.

### R6. `.select` en providers muy vigilados

`analytics_screen.dart:178-179` observa `profileStreamProvider` entero solo para leer `.currency`. Un `.select((p) => p.currency)` evita rebuilds por cambios de tema/idioma. Impacto 1 — solo si tocas ese fichero.

---

## UI

- **U1. i18n incompleto (cadenas en inglés incrustadas)** 🟡 — Muchas cadenas hardcodeadas conviviendo con `translations.t(...)`: `'Savings rate'`, `'Total Balance'`, `'No transactions'`, `'Delete "$label"?'`, `'Search budgets'`, `'Load more'`, `'Backup failed'`, etc. (`analytics_sections.dart` varias, `dashboard_screen.dart:282,303,312,445,552-554`, diálogos CRUD, `backup_screen.dart:36,53-56`). En una app multilingüe rompe la experiencia. Impacto 3, dificultad 3. Ir moviéndolas a los JSON de locale.
- **U2. Códigos `A1.4` visibles** — ya cubierto en C2. Es lo más chocante visualmente y lo más barato de arreglar.
- **U3. Accesibilidad: tamaños de fuente fijos** — `dashboard_screen.dart:678 (fontSize: 11)`, y varios `appDisplay(fontSize: …)` fijos no responden al ajuste de tamaño de texto del sistema. Para uso personal es menor, pero si algún día se publica, el texto de saldos no crece para baja visión. Impacto 2. No prioritario.
- **U4. Objetivos táctiles sin semántica** — `expense_entry_screen.dart:479-489,588-599`: selector de tipo/importe montado con `GestureDetector`+`Text` sin rol de botón ni `Semantics`, área de toque pequeña. Impacto 2.

El sistema de tema (M3, tokens de color, tipografía de dos niveles, transiciones) está bien resuelto y documentado en `STYLE.md`; no toco nada ahí.

---

## UX

- **X1. Spinner infinito ante error** 🟠 — Todos los `FutureBuilder` de analytics/dashboard comprueban solo `if (!snap.hasData)` y **nunca** `snap.hasError` (`analytics_sections.dart` varias, `analytics_screen.dart:559,702`, `dashboard_screen.dart:419`). Si una query falla, la pantalla gira para siempre sin mensaje. Impacto 3, dificultad 2. Añadir un estado de error simple (icono + "Reintentar"). Es de las mejores relaciones valor/coste.
- **X2. Borrado optimista sin rollback** 🟡 — En las 6 pantallas CRUD (`events_screen.dart:82-85`, `projects`, `tags`, `categories`, `payment_methods`, `tag_groups`) se hace `setState(remove)` y luego `await repo.delete()` sin revertir si falla; `tag_groups` incluso se traga el `StateError`. La fila desaparece de la UI aunque siga en la BD. Impacto 2, dificultad 2. Revertir el `setState` en el `catch` y mostrar toast.
- **X3. Mensaje de restore honesto pero mejorable** — `backup_screen.dart:69` pide "Reinicia la app para ver todos los cambios". Tras arreglar B (backup seguro) e invalidar bien los providers, idealmente no debería hacer falta reiniciar. Menor.

Buen trabajo ya hecho (no cambiar): `expenses_screen`, `budgets_screen`, `profile_screen` tienen estados de carga/vacío correctos; `backup_screen` gestiona busy/error con `AbsorbPointer` + toast; los haptics pasan siempre por `hapticsProvider` (regla de CLAUDE.md cumplida).

---

## Funcionalidades

Solo propongo lo que aporta valor real a **finanzas personales de un individuo** y encaja con lo ya construido. Descarto ideas "porque sí".

| Funcionalidad | Estado actual | Valor | Recomendación |
|---|---|---|---|
| **Movimientos recurrentes** (nómina, alquiler, suscripciones) | No existe | Alto | **Sí.** Es lo que más fricción quita: hoy hay que teclear cada mes lo mismo. Modelo simple: una tabla `recurring` (plantilla + periodicidad + próxima fecha) que genere un `Expense` real al vencer. No metas un motor de reglas complejo. |
| **Objetivos de ahorro** | Hay tipo `ahorro` pero sin objetivo/target | Alto | **Sí, ligero.** Ya tienes categorías de ahorro; falta un objetivo (importe meta + progreso). Reutiliza el patrón de `Budget`. Coherente y barato. |
| Ingresos, gastos, categorías, tags, presupuestos, eventos/proyectos, export PDF/CSV, analytics | Cubierto | — | No tocar; está completo para el alcance. |
| **Cuentas + transferencias + patrimonio** | No existe (no hay tabla `Account`) | Medio | **Opcional/aplazar.** Es la pieza gorda que falta para "finanzas completas", pero también la de mayor coste (toca esquema, entrada, analytics) y puede ser sobreingeniería si llevas el saldo en la cabeza. Solo si de verdad manejas varias cuentas. |

---

## Seguridad

Riesgo bajo en general: app **on-device, sin red, sin credenciales, sin datos de terceros**. La base SQLite local sin cifrar es aceptable para uso personal.

Único punto real a tener presente:

- **Backups en claro** — `BackupService.createBackup` genera un `.sqlite` sin cifrar que se comparte por el share sheet (`backup_screen.dart:34`). Si acaba en la nube/mensajería, tu historial financiero viaja en claro. **No** recomiendo cifrado obligatorio (fricción alta para uso personal); solo tenlo en cuenta al elegir dónde compartes el fichero. Opcional: proteger con contraseña el export si algún día se publica.

(La corrección de robustez del backup — checkpoint WAL — está en la sección de datos como B, no es un tema de seguridad sino de integridad.)

### B. Backup/restore no seguro con WAL 🔴

`lib/domain/backup/backup_service.dart:33-52`

```dart
Future<File> createBackup() async {
  ...
  return dbFile.copy(backupPath);   // copia el .sqlite ABIERTO, sin checkpoint,
                                    // e ignora despeses.sqlite-wal / -shm
}

Future<void> restoreBackup(File backupFile) async {
  final dbPath = await _dbFilePath();
  await backupFile.copy(dbPath);    // sobrescribe el principal; los -wal/-shm
                                    // antiguos quedan y pueden reproducirse encima
}
```

- **Problema:** con WAL activo, copiar el fichero principal mientras la BD está abierta puede **no incluir las últimas transacciones** (siguen en el `-wal`). Y al restaurar, el `restoreBackup` sobrescribe el principal pero deja los `-wal`/`-shm` viejos, que SQLite puede reproducir encima del fichero restaurado → estado corrupto o mezclado. `backup_screen.dart:64` sí cierra la conexión antes de restaurar (bien), pero no borra los sidecars.
- **Impacto:** 5 · **Dificultad:** 2 · **Tiempo:** 2–3 h.
- **Propuesta:**
  - En `createBackup`: hacer `PRAGMA wal_checkpoint(TRUNCATE)` antes de copiar (vuelca el WAL al principal), o cerrar la conexión y copiar los tres ficheros.
  - En `restoreBackup`: tras sobrescribir el principal, **borrar** `despeses.sqlite-wal` y `despeses.sqlite-shm` si existen, antes de reabrir.
- Es la red de seguridad de A1; tiene que ser fiable.

---

## Testing

Base actual razonable (621 LOC): repos, analytics (cashflow/category/scope/engine), backup, export, keypad, drag FAB. No hace falta perseguir cobertura alta en una app personal. Solo añadiría lo que protege los arreglos de arriba:

| Test a añadir | Protege | Prioridad |
|---|---|---|
| Migración real que preserva datos (una vez implementada A1) | Que un cambio de esquema no borre nada | Alta |
| Backup con WAL: crear backup con transacción sin checkpoint y verificar que restaura completa (B) | Integridad del backup | Alta |
| Presupuesto `range` en frontera de mes / meses sin padding (C5) | Comparación de meses | Media |
| Formateador de dinero por locale es/en (C1) | Símbolo y separadores correctos | Media |
| `signedSpend` centralizado con todos los tipos, incl. `refund` (C3) | Reglas contables | Media |

Sugerencia: borrar `test/widget_test.dart` si es la plantilla por defecto (no aporta).

---

## Roadmap recomendado

**Fase 0 — Integridad de datos (antes de cualquier otro cambio de esquema).** Bloqueante.
1. B — Backup/restore seguro con WAL (checkpoint + borrar sidecars).
2. A1 — Migraciones reales + auto-backup en `beforeOpen` cuando hay upgrade; quitar el reseed destructivo del binario de uso real.
3. Tests de A1 y B.

**Fase 1 — Rendimiento y robustez visibles.**
4. R1 — Sacar los futures de `build` en analytics (`FutureProvider.family` por mes/sección).
5. X1 — Estado de error en los `FutureBuilder` (no más spinner infinito).
6. R2/R3 — Acotar `calculateProgress` por fecha, `descendantIds` vía caché, índices en `date`/`categoryId`.
7. R4 — `expense_entry`: dejar de reconstruir por tecla y de re-resolver labels.

**Fase 2 — Consistencia y limpieza.**
8. C1 — Formateador de dinero único locale-aware.
9. C2/U2 — Quitar códigos `A1.4`; U1 — completar i18n.
10. X2 — Rollback en borrados optimistas.
11. C3/C4/C5 — Centralizar signo, unificar month-key, comparación de meses robusta.
12. C9 — Unificar widgets duplicados (fila de gasto, progreso de presupuesto, empty state, pager de mes; opcional: pantalla CRUD genérica para las 6 de settings).

**Fase 3 — Funcionalidad (solo si la usarás).**
13. Movimientos recurrentes.
14. Objetivos de ahorro.
15. (Aplazado) Cuentas + transferencias + patrimonio, solo si manejas varias cuentas.

**Continuo:** limpiar deuda menor según toques cada zona — `hapticsStrength` muerto, `onReorder` deprecado (4 pantallas), guardas de ciclo en `export_service.categoryPath` y de scope null/null en `analytics_events._scopeExpenses`, `uniqueKey` de categorías raíz duplicadas.

---

## Resumen final

La app está **sana** y su arquitectura es adecuada al tamaño; no necesita refactor grande ni patrones nuevos. Lo importante y urgente es una sola cosa: **los datos financieros reales no están protegidos** — un cambio de esquema los borra (A1) y el backup que debería salvarte no es fiable con WAL (B). Arregla eso primero.

El resto es pulido de alto valor y bajo riesgo: quitar el refetch de analytics durante el arrastre (R1), mostrar errores en vez de girar para siempre (X1), un formateador de dinero decente que respete el locale (C1), y completar el i18n quitando los códigos internos visibles (C2/U1). En funcionalidad, solo **recurrentes** y **objetivos de ahorro** justifican su coste; lo demás es opcional.

Prioriza siempre las Fases 0 y 1. Con eso la app pasa de "buena para desarrollo" a "segura para usarla en serio con tus datos".
