# Auditoría del proyecto

> App: **despeses** (finanzas personales, uso individual) · Flutter · Riverpod · Drift · go_router · Material 3
> Última actualización: 2026-10-02 · Alcance: `lib/` completo + `test/` + configuración.
> Criterio: solo se listan problemas reales cuyo beneficio de arreglo supera al coste.

---

## Resumen ejecutivo

El proyecto está **bien construido para una app personal**: dinero en enteros (céntimos), no en `double`; repositorios con transacciones en las escrituras multi-fila; capas separadas (`data` / `domain` / `presentation` / `core`); estado con Riverpod sin sobreingeniería; y una base de tests razonable. `flutter analyze` sale casi limpio (5 avisos `info`).

Las funcionalidades principales están implementadas: ingresos/gastos/reembolsos/ahorros, categorías anidadas, presupuestos, eventos/proyectos, tags, métodos de pago, movimientos recurrentes (v8), objetivos de ahorro (v9), exportación PDF/CSV, backup/restore y analytics completo.

Las mejoras pendientes son de **calidad y consistencia**: formato de dinero no locale-aware, i18n incompleto, refetch innecesario en analytics, y unificación de lógica duplicada.

---

## Mejoras pendientes

| # | Mejora | Área | Impacto | Dificultad | Tiempo | Prioridad |
|---|--------|------|:-------:|:----------:|:------:|:---------:|
| 1 | Sacar los `future:` de `build()` en analytics (tormenta de refetch al arrastrar) | Rendimiento | 4 | 3 | 3–4 h | 🟠 Alta |
| 2 | Manejar `snapshot.hasError` (spinner infinito ante error) | UX/Rob. | 3 | 2 | 2 h | 🟠 Alta |
| 3 | Formateador de dinero único, locale-aware (símbolo + separadores) | UI/Código | 3 | 2 | 2–3 h | 🟠 Alta |
| 4 | Matar el N+1 de analytics (`descendantIds`, `calculateProgress`) | Rendimiento | 3 | 2 | 3 h | 🟠 Alta |
| 5 | `expense_entry`: rebuild por tecla y parpadeo de labels | Rendimiento/UX | 3 | 2 | 1–2 h | 🟡 Media |
| 6 | Completar i18n (cadenas en inglés) y quitar códigos `A1.4` de la UI | UI/i18n | 3 | 3 | 3–4 h | 🟡 Media |
| 7 | Unificar widgets duplicados (fila de gasto, progreso de presupuesto, empty state, pager de mes) | Código | 3 | 3 | 4–6 h | 🟡 Media |
| 8 | Rollback en borrados optimistas | Robustez | 2 | 2 | 1 h | 🟡 Media |
| 9 | Centralizar la lógica de signo por tipo (`refund` negativo) | Código | 2 | 2 | 1 h | 🟢 Baja |
| 10 | Formato de `month-key` único + comparación de meses robusta | Código | 2 | 2 | 1–2 h | 🟢 Baja |
| 11 | Limpieza: columna `hapticsStrength` muerta, `onReorder` deprecado, guardas de ciclo/scope | Deuda | 1 | 1 | 1 h | 🟢 Baja |

---

## Arquitectura

La estructura por capas es correcta y proporcionada. Los repositorios actúan de frontera y eso es suficiente para una app personal. **No** se recomienda Clean Architecture formal (casos de uso, interfaces de repositorio, entidades separadas de las de Drift): el beneficio es marginal y añadiría mucha ceremonia.

### A1. `intl` está como dependencia pero no se usa para dinero/fechas

El `pubspec` incluye `intl`, pero el dinero se formatea a mano con `toStringAsFixed(2)` en 6+ sitios (ver C1) y no hay `NumberFormat`/`DateFormat` locale-aware. O se usa `intl`, o sobra en `pubspec`. Recomendado: usarlo (resuelve C1 y el formato de fechas de paso).

### A2. El `ReferenceDataCache` existe pero no se usa donde importa

`lib/domain/repositories/reference_data_cache.dart` cachea categorías, pero el camino caliente de analytics (`descendantIds()` → `listAll()`) va directo a la BD (ver R2). El caché que mataría el N+1 está ahí sin aprovechar. Enrutar analytics de categorías por el caché es la mejora de arquitectura con mejor relación beneficio/coste.

---

## Calidad del código

### C1. Formato de dinero duplicado y no locale-aware 🟠

Presente en `dashboard_screen.dart:544,596,698`, `expenses_screen.dart:237`, `budgets_screen.dart:174`, `charts/analytics_widgets.dart:7`, `export_service.dart:47`, `amount_text.dart:19`:

```dart
'$sign${(expense.amount / 100).toStringAsFixed(2)} ${expense.currency}'
```

- **Problema:** (a) misma lógica repetida en 6+ ficheros; (b) muestra `1234.56 EUR` en vez de `1.234,56 €` — sin separador de miles, con punto decimal fijo y el código de moneda en lugar del símbolo. La app soporta es/ca/fr/it, que usan coma decimal.
- **Impacto:** 3 · **Dificultad:** 2 · **Tiempo:** 2–3 h.
- **Propuesta:** un único helper y borrar las 6 copias.

```dart
// lib/core/format/money.dart
String formatMoney(int cents, String currency, String locale) =>
    NumberFormat.currency(locale: locale, name: currency).format(cents / 100);
```

`AmountText` puede seguir partiendo entero/decimales, pero tomando la cadena ya formateada de este helper.

### C2. Códigos internos de spec mostrados al usuario 🟡

`analytics_sections.dart` (líneas 114, 201, 216, 224, 307, 315, 332, 384, 445, 454, 462, 509, 548, 711, 718): subtítulos de `StatCard` como `'A1.4'`, `'A2.1'`, `'A7.1–A7.3'`. Son referencias internas que se están **mostrando en pantalla**.
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

No urge, pero mover esto al dominio facilita testear y evita divergencias.

### C7. `dynamic` que pierde tipado

`analytics_sections.dart:488 _BehaviorData.stats` es `dynamic`. Tipar la clase de stats de tickets. Impacto 1.

### C8. Código/columna muertos

- `Profile.hapticsStrength` (`tables.dart:9-10`) + `ProfileRepository.setHapticsStrength` (`:41-46`): la feature se retiró. Eliminar en la próxima migración real.
- `test/widget_test.dart` (18 líneas): parece el test por defecto de Flutter; si es la plantilla del contador, bórralo.

---

## Rendimiento

> El volumen de datos de una app personal es pequeño, así que nada de esto crashea. Pero son trabajos evitables y algunos causan parpadeos visibles.

### R1. Futures creados dentro de `build()` → refetch en cada frame de arrastre 🟠

`analytics_screen.dart:555,699` y `analytics_sections.dart` (90,147,185,297,373,428,505,537,643,691): cada sección hace `future: _load(ref)` **inline en `build`**.

- **Problema:** el future se recrea en cada rebuild y vuelve a lanzar la query + parpadea el spinner. Peor: el **arrastre de preview del FAB** llama a `setState` cada frame (`analytics_screen.dart:152-155`), que reconstruye el `itemBuilder` del `PageView` (`:211-214`) y **re-dispara todas las queries de la sección en cada frame del gesto**.
- **Impacto:** 4 · **Dificultad:** 3 · **Tiempo:** 3–4 h.
- **Propuesta:** convertir cada cálculo de sección en un `FutureProvider.family` cacheado por (mes, sección), o memoizar el future en el `State` y recrearlo solo cuando cambie el mes.

### R2. N+1 apilado en analytics de categorías y presupuestos 🟠

- `category_repository.dart:113-114 descendantIds` hace `await listAll()` (escaneo completo de categorías) **en cada llamada**, y se llama en bucle en `analytics_category.dart:60,82,118`.
- `budget_repository.dart:111-141 calculateProgress` **no acota por fecha**: un presupuesto `monthly` carga todo el histórico de su categoría y filtra en Dart.
- `analytics_dashboard.dart:67-72` recorre los presupuestos activos y por cada uno llama `pace()` → `calculateProgress` (N+1) + `descendantIds` (otro N+1).
- **Impacto:** 3 · **Dificultad:** 2 · **Propuesta:** (a) acotar `calculateProgress` por rango de fechas en SQL; (b) resolver `descendantIds` desde el `ReferenceDataCache` (A2).

### R3. `expense_entry`: rebuild por pulsación y parpadeo de labels 🟡

`expense_entry_screen.dart:74` hace `_descriptionController.addListener(() => setState((){}))` → reconstruye toda la pantalla en **cada tecla**, y `_buildFieldsView` crea `future: _resolveLabels()` inline en `build`. Mientras el future está pendiente, los tiles de Categoría/Método/Evento/Proyecto vuelven a su placeholder en cada tecla.
- **Impacto:** 3 · **Dificultad:** 2 · **Propuesta:** escuchar el controller solo para habilitar Guardar (`ValueListenableBuilder` sobre el botón), y resolver labels una vez fuera de `build`.

### R4. Otros N+1 menores

- `dashboard_screen.dart:665,709 _ExpenseRow`: un `FutureBuilder<String?>` por fila lee toda la lista de categorías del caché; resolver los labels una vez en la carga del mes.
- `export_screen.dart:57-59`: `for (final e in expenses) ... await expenseRepo.tagIdsOf(e.id)` → N+1 en exportaciones que pueden abarcar años. Batch en el repo.
- `dashboard_screen.dart:45,84-98,124-132`: caché de mes manual (`_expenseCache`) con invalidación a mano. Frágil; un `FutureProvider.family(mes)` lo da gratis.

---

## UI

- **U1. i18n incompleto (cadenas en inglés incrustadas)** 🟡 — Muchas cadenas hardcodeadas conviviendo con `translations.t(...)`: `'Savings rate'`, `'Total Balance'`, `'No transactions'`, `'Delete "$label"?'`, `'Search budgets'`, `'Load more'`, `'Backup failed'`, etc. En una app multilingüe rompe la experiencia. Impacto 3, dificultad 3. Ir moviéndolas a los JSON de locale.
- **U2. Códigos `A1.4` visibles** — ya cubierto en C2. Es lo más chocante visualmente y lo más barato de arreglar.
- **U3. Accesibilidad: tamaños de fuente fijos** — `dashboard_screen.dart:678 (fontSize: 11)`, y varios `appDisplay(fontSize: …)` fijos no responden al ajuste de tamaño de texto del sistema. Para uso personal es menor. Impacto 2.
- **U4. Objetivos táctiles sin semántica** — `expense_entry_screen.dart:479-489,588-599`: selector de tipo/importe montado con `GestureDetector`+`Text` sin rol de botón ni `Semantics`. Impacto 2.

El sistema de tema (M3, tokens de color, tipografía de dos niveles, transiciones) está bien resuelto y documentado en `STYLE.md`.

---

## UX

- **X1. Spinner infinito ante error** 🟠 — Todos los `FutureBuilder` de analytics/dashboard comprueban solo `if (!snap.hasData)` y **nunca** `snap.hasError` (`analytics_sections.dart` varias, `analytics_screen.dart:559,702`, `dashboard_screen.dart:419`). Si una query falla, la pantalla gira para siempre sin mensaje. Impacto 3, dificultad 2. Añadir un estado de error simple (icono + "Reintentar").
- **X2. Borrado optimista sin rollback** 🟡 — En las 6 pantallas CRUD (`events_screen.dart:82-85`, `projects`, `tags`, `categories`, `payment_methods`, `tag_groups`) se hace `setState(remove)` y luego `await repo.delete()` sin revertir si falla. La fila desaparece de la UI aunque siga en la BD. Impacto 2, dificultad 2. Revertir el `setState` en el `catch` y mostrar toast.

---

## Seguridad

Riesgo bajo: app **on-device, sin red, sin credenciales, sin datos de terceros**. La base SQLite local sin cifrar es aceptable para uso personal.

- **Backups en claro** — `BackupService.createBackup` genera un `.sqlite` sin cifrar que se comparte por el share sheet. Si acaba en la nube/mensajería, el historial financiero viaja en claro. No se recomienda cifrado obligatorio (fricción alta para uso personal); tenerlo en cuenta al elegir dónde se comparte el fichero.

---

## Testing

Base actual razonable: repos, analytics (cashflow/category/scope/engine), backup, export, keypad, drag FAB. No hace falta perseguir cobertura alta en una app personal. Los tests que más valor añadirían:

| Test a añadir | Protege | Prioridad |
|---|---|---|
| Presupuesto `range` en frontera de mes / meses sin padding (C5) | Comparación de meses | Media |
| Formateador de dinero por locale es/en (C1) | Símbolo y separadores correctos | Media |
| `signedSpend` centralizado con todos los tipos, incl. `refund` (C3) | Reglas contables | Media |

Sugerencia: borrar `test/widget_test.dart` si es la plantilla por defecto (no aporta).

---

## Resumen final

La app está **sana** y lista para uso en producción. Su arquitectura es adecuada al tamaño; no necesita refactor ni patrones nuevos.

Las mejoras de mayor valor son: quitar el refetch de analytics durante el arrastre (R1), mostrar errores en vez de girar para siempre (X1), un formateador de dinero que respete el locale (C1), y completar el i18n quitando los códigos internos visibles (C2/U1).
