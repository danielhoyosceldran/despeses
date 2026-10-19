# Rendimiento: medición, reglas y build de release

Referencia para medir la fluidez de la app en Android y no perderla. Las
entradas de rendimiento del backlog (BL-0xx, tipo «Rendimiento») se validan con
el procedimiento de este documento.

## 1. Dataset de perfilado (BL-056)

`lib/dev/perf_seed.dart` siembra ~5 años de datos realistas (~10k movimientos de
los cuatro tipos, tags en ~30 %, 5 presupuestos y 4 plantillas recurrentes) con
semilla fija, para que las mediciones sean comparables entre ejecuciones.

- Se activa con `--dart-define=SEED_PERF_DATA=true`.
- Solo en debug/profile: la constante es `false` en release y el código se
  elimina del binario.
- Solo actúa si la BD **no tiene ningún movimiento**: nunca toca datos reales.
  Para volver a sembrar, borra los datos de la app (Ajustes de Android › Apps ›
  canut finances › Almacenamiento › Borrar datos).

```bash
flutter run --profile --dart-define=SEED_PERF_DATA=true
```

## 2. Procedimiento de medición

Siempre en **modo profile** (debug no es representativo) y en un **dispositivo
físico**, preferiblemente de gama media/baja (es donde se notan los problemas).

1. `flutter run --profile --dart-define=SEED_PERF_DATA=true`
2. Abrir DevTools (la URL sale en la consola) › **Performance**.
3. Activar *Track widget builds* y, cuando haga falta, *Highlight repaints* y el
   *Performance overlay*.
4. Grabar cada escenario de la tabla 3 por separado (3 repeticiones, quedarse con
   la mediana).

Presupuesto por frame: 16 ms a 60 Hz, 11 ms a 90 Hz, 8 ms a 120 Hz, tanto en el
hilo de UI como en el de raster.

Arranque en frío:

```bash
flutter run --profile --trace-startup
```

Genera `build/start_up_info.json` con `timeToFirstFrameMicros`, entre otros.

## 3. Escenarios y métricas

Rellenar con el dataset de la sección 1. Indicar dispositivo y fecha.

| Escenario | Qué mirar | Objetivo | Medido |
|---|---|---|---|
| Arranque en frío | `timeToFirstFrameMicros` | < 1 s en gama media | pendiente |
| Scroll del dashboard (hero colapsando) | frames UI/raster; no se reconstruyen `AmountText`/`_StatTile` | sin frames por encima del presupuesto | pendiente |
| Swipe entre meses del dashboard | frames UI; nº de `ExpenseRow` construidos ≈ los visibles | sin jank | pendiente |
| Guardar un movimiento desde otro tab | el dashboard oculto no se reconstruye | — | pendiente |
| Entrar en Analytics sin cambios previos | ninguna consulta nueva ni spinner | — | pendiente |
| Lista de movimientos: «cargar más» varias veces | tiempo de cada página constante | < 50 ms por página | pendiente |
| Arrastrar el FAB de secciones en Analytics | *Highlight repaints*: solo el FAB | — | pendiente |

## 4. Reglas que mantienen la app fluida

Patrones ya aplicados; respétalos al tocar estas zonas.

- **Formateadores cacheados.** Usa `formatMoney`/`formatDecimal`/`formatDate`
  o `cachedDateFormat(...)` (`lib/core/format/`). No crees `NumberFormat` ni
  `DateFormat` en un `build`, por fila o por frame.
- **Listas perezosas.** Las listas de movimientos usan `ListView.builder` /
  `SliverList.builder` con `key` por id. Nada de `SliverList.list` /
  `ListView(children:)` con todas las filas.
- **Datos derivados memoizados.** Agrupar/filtrar/totalizar una vez por snapshot
  de datos, no en cada `build` (ver `_MonthDerived` en el dashboard).
- **Animaciones guiadas por scroll/drag.** Construir los hijos una vez y en cada
  frame solo cambiar transformaciones (`Transform`, `Align.heightFactor`),
  nunca `fontSize` ni nada que obligue a recolocar texto. Evitar `Opacity` con
  valores intermedios durante mucho recorrido (capa offscreen).
- **Repaint boundaries** en gráficos, barra de navegación, FABs arrastrables y
  el hero del dashboard.
- **Lookups O(1).** Etiquetas de categoría vía `categoryLabelsProvider`, nunca
  `categories.where(...)` por fila.
- **Nada de N+1.** Cargar relaciones en lote (p. ej.
  `ExpenseRepository.tagIdsByExpense`), no un `await` por fila.
- **Paginación keyset**, no `OFFSET` (`ExpenseRepository.list(after:)`), apoyada
  en `idx_expenses_order`.
- **Índices nuevos** en `_createIndexes` con `IF NOT EXISTS`: se crean también
  en `beforeOpen`, así que no hace falta subir `schemaVersion`.
- **SQLite en WAL** con `synchronous = NORMAL` (`beforeOpen`). Cualquier copia
  del fichero de BD debe hacer antes `PRAGMA wal_checkpoint(TRUNCATE)` o copiar
  también los sidecars `-wal`/`-shm` (ver `BackupService`).
- **Tabs ocultos.** El shell mantiene montados los tabs visitados; un tab con
  streams en vivo debe pausarlos cuando no es visible (ver `active` en el
  dashboard) y Analytics solo se invalida si hubo escrituras
  (`analyticsStalenessProvider`).

## 5. Build de release para Android (BL-067)

```bash
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
```

- **App Bundle**: Play entrega a cada dispositivo solo su ABI y densidad.
- **`--obfuscate --split-debug-info`**: binario más pequeño y nombres
  ofuscados. **Guarda `build/symbols/` de cada versión publicada** (fuera del
  repo): sin ellos las trazas de crash no se pueden leer. Para desofuscar:
  `flutter symbolize -i <traza> -d build/symbols/app.android-arm64.symbols`.
- **R8 / shrink**: activo por defecto en release con el plugin de Flutter; no
  añadas `isMinifyEnabled = false` ni `isShrinkResources = false` en
  `android/app/build.gradle.kts`.
- **Impeller**: es el renderer por defecto en Android; no añadas el meta-data
  `io.flutter.embedding.android.EnableImpeller=false` al manifest.

APK para instalar a mano (una por ABI, más pequeñas que la universal):

```bash
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
```

Tamaño: revisar de vez en cuando qué ocupa más en el binario.

```bash
flutter build appbundle --release --analyze-size --target-platform android-arm64
```

Genera un JSON que se abre en DevTools › *App Size*.
