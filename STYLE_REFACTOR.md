# Refactor estilístico — adaptación del mock "Innovative Style Proposal" a Flutter

Documento de refactor **solo de estilo y motion** (el layout ya coincide: el
`LAYOUT.md` del mock es el mismo que el de esta app). Fuente: mock React/Vite +
Tailwind v4 + Framer Motion en `Downloads/Innovative Style Proposal`
(`style.md`, `src/styles/theme.css`, `src/app/App.tsx`).

Objetivo: que la app Flutter se vea **exactamente** como el mock — carácter
minimalista mono-ink, tipografía de dos niveles (Inter + Clash Display),
formas redondeadas suaves, bordes hairline translúcidos, y el conjunto de
animaciones (balance colapsable del dashboard, pill de nav que morfea,
bottom-sheets con spring, scale-on-press del FAB).

Regla transversal: nunca se toca lógica, repos, RPC, providers, i18n ni rutas.
Comentarios de código en inglés. Ambos temas (light + dark).

---

## 0. Carácter general (lo que cambia respecto a hoy)

El theme actual es "Revolut" (acento morado `#5A31F4`, Inter única, cards
radius 8, bordes sólidos). El mock es **mono-ink minimalista**:

- **Acento = tinta casi negra** `#030213` (light) que invierte a casi blanco en
  dark. Sin morado. El acento se usa en FAB, botón primario, estado activo de
  nav, foco. Los colores vivos quedan **solo** para importes y chips de datos.
- **Dos tipografías**: Inter (UI/cuerpo) + **Clash Display** (dinero, titulares,
  nombres de budget, títulos de modal). Hoy solo hay Inter.
- **Más redondeado**: filas y cards a 16px, paneles a 24px, sheets a 40px,
  pills/círculos completos. Hoy cards a 8px.
- **Bordes hairline translúcidos** (`border` al 50%) como divisor dominante;
  borde completo solo en frame, nav y sheets.
- **Motion de primera clase**: el estilo *es* el movimiento.

---

## 1. Tokens de color — `lib/core/theme/app_colors.dart`

### 1.1 `AppColors` (roles neutros de UI)

Reemplazar los valores actuales por los del mock (`theme.css`). Mapeo de
roles del mock a los campos existentes de `AppColors`:

| Campo Flutter | Rol mock | Light | Dark |
|---|---|---|---|
| `bg` | `--background` | `#FFFFFF` | `oklch(0.145 0 0)` ≈ `#242424` |
| `surface` | `--card` | `#FFFFFF` | `oklch(0.145 0 0)` ≈ `#242424` |
| `surfaceAlt` | `--muted` (fill) | `#ECECF0` | `oklch(0.269 0 0)` ≈ `#434343` |
| `border` | `--border` | `rgba(0,0,0,0.10)` | `oklch(0.269 0 0)` |
| `divider` | `--border` al 50% | `rgba(0,0,0,0.05)` | `#434343` @ 50% |
| `text` | `--foreground` | `oklch(0.145 0 0)` ≈ `#242424` | `oklch(0.985 0 0)` ≈ `#FBFBFB` |
| `textMuted` | `--muted-foreground` | `#717182` | `oklch(0.708 0 0)` ≈ `#B4B4B4` |
| `textDisabled` | `--muted-foreground` atenuado | `#B0B1BC` | `oklch(0.5 0 0)` |
| `accent` | `--primary` | `#030213` | `oklch(0.985 0 0)` ≈ `#FBFBFB` |
| `onAccent` | `--primary-foreground` | `#FFFFFF` | `oklch(0.205 0 0)` ≈ `#343434` |
| `shadow` | sombra frame/FAB | `0x1F000000` (12%) | `0x66000000` (40%) |

Notas de conversión:
- Los `oklch(L 0 0)` son grises neutros; convertir a sRGB (valores hex de arriba
  ya aproximados). Precisión suficiente para UI; si se quiere exacto, usar
  `oklch`→sRGB una vez y fijar el hex.
- **`accent` en dark es casi blanco** (`#FBFBFB`) con `onAccent` oscuro. Esto es
  clave: en dark el FAB/botón primario son claros sobre fondo oscuro, igual que
  el mock. Verificar contraste AA en ambos sentidos.
- `border` debe ser translúcido de verdad (canal alfa), porque el mock lo pinta
  al 50% (`border-border/50`) sobre distintos fondos. Mantener el alfa, no
  aplanar contra blanco.

### 1.2 `divider` translúcido (borde hairline al 50%)

El mock usa `border-border/50` como divisor por defecto y `border-border` (100%)
solo en frame/nav/sheet. En Flutter:

- `border` = color completo (nav, sheet, contorno de "frame" si se emula).
- `divider` = mismo color al 50% → usar para separadores de filas de settings,
  bordes de cards, bordes de stat tiles, filas de transacción, inputs.

Añadir helper:
```dart
// 50% version of the hairline border — the mock's default divider (border/50).
Color get borderSoft => border.withValues(alpha: border.a * 0.5);
```

### 1.3 Semánticos + paleta de datos — `AppSemanticColors`

El mock usa la paleta Tailwind, distinta de la actual. Actualizar:

| Campo | Hoy | Mock (Tailwind 500) |
|---|---|---|
| `income` | `#00C48C` | **Emerald `#10B981`** |
| `expense` | `#FF4757` | **Rose `#F43F5E`** |
| `refund` | `#FFB020` | Refund se muestra en color **texto** (`foreground`), no ámbar — ver §7 fila de transacción |
| `over` | `#FF4757` | **Rose `#F43F5E`** |

Además, el mock introduce una **paleta de acentos de datos** para chips de icono
y series de charts/budgets (no existe hoy). Añadir como constantes:

```dart
// Data-accent palette (Tailwind 500). Used only for category icon chips,
// budget progress fills and donut slices — never as UI surface fills.
class AppDataColors {
  static const emerald = Color(0xFF10B981);
  static const rose    = Color(0xFFF43F5E);
  static const purple  = Color(0xFF8B5CF6);
  static const amber   = Color(0xFFF59E0B);
  static const blue    = Color(0xFF3B82F6);
}
```

Chips de icono: **fill = color al 10%**, icono = color pleno. Sustituir el
`pillBackground` (15%) por 10% en los chips de icono de datos; mantener 15% para
chips de selección UI si se quiere, pero el mock usa 10% (`bg-emerald-500/10`).

```dart
Color iconChipBackground(Color c) => c.withValues(alpha: 0.10);
```

---

## 2. Tipografía — dos niveles

### 2.1 Fuentes a añadir

- **Inter** (ya presente) — cuerpo/UI. Pesos 300/400/500/600.
- **Clash Display** (NUEVO) — dinero, titulares, títulos de modal, nombres de
  budget. Pesos 300/400/500/600. **No está en Google Fonts**: descargar de
  Fontshare (`https://www.fontshare.com/fonts/clash-display`) y **bundlear** los
  `.otf/.ttf` en `assets/fonts/`.

`pubspec.yaml`:
```yaml
flutter:
  fonts:
    - family: ClashDisplay
      fonts:
        - asset: assets/fonts/ClashDisplay-Light.otf
          weight: 300
        - asset: assets/fonts/ClashDisplay-Regular.otf
          weight: 400
        - asset: assets/fonts/ClashDisplay-Medium.otf
          weight: 500
        - asset: assets/fonts/ClashDisplay-Semibold.otf
          weight: 600
```
> Decisión pendiente del usuario: si no se quiere bundlear Clash Display, el
> fallback del mock es **Instrument Serif** (sí está en Google Fonts, vía
> `google_fonts`). Cambia bastante el carácter (serif vs geométrica). Recomiendo
> Clash Display para fidelidad 1:1.

Helper de estilo display:
```dart
// Display face for money/headlines. tracking-tight + tabular figures.
TextStyle appDisplay(AppColors c, {required double size, FontWeight w = FontWeight.w500}) =>
    TextStyle(
      fontFamily: 'ClashDisplay',
      fontSize: size,
      fontWeight: w,
      letterSpacing: -0.5, // tracking-tight
      height: 1.0,
      color: c.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
```

### 2.2 `TextTheme` — `app_theme.dart::_textTheme`

El mock (base 16px) usa:

| Uso | Mock | Flutter (estilo → fuente/size/peso) |
|---|---|---|
| Balance hero | `text-6xl` display medium, colapsa a `text-3xl` | `displayLarge` ClashDisplay 60 / colapsado 30 (animado, §6.4) |
| Total analytics | `text-5xl` display | `displayMedium` ClashDisplay 48 w500 |
| Importe modal | `text-6xl` display | ClashDisplay 60 (usar `appDisplay`) |
| Título modal / header display | `text-3xl` / `text-2xl` display | ClashDisplay 30 / 24 w500 |
| Importe de fila / stat tile | `text-lg`/`text-xl` display | ClashDisplay 18 / 20 w500 |
| Fila de cuerpo (título tx) | `text-sm` medium | Inter 14 w500 |
| Método / subtítulo | `text-xs` muted | Inter 12 w400 muted |
| Línea de categoría (tx) | `text-[11px]` uppercase tracking-wide muted | Inter 11 w500 letterSpacing .5 uppercase muted |
| Header día / sección | `text-xs` semibold uppercase tracking-wide muted | Inter 12 w600 letterSpacing .5 uppercase muted |
| Label mes header | `text-sm` medium uppercase muted | Inter 13 w500 uppercase muted |
| Label nav | `text-[10px]` medium | Inter 10 w500 |
| Botón primario | `text-lg` medium | Inter 18 w500 |

Reglas:
- **Todo importe** lleva `FontFeature.tabularFigures()` (hoy solo `displaySmall`).
- Los estilos "display" cambian a `fontFamily: 'ClashDisplay'`. El resto sigue
  Inter.
- Peso de UI predominante = **500** (medium), no 600/700 como hoy en varios
  títulos. Ajustar `titleLarge/titleMedium/labelLarge` a w500 salvo donde el mock
  pida semibold (headers de día/sección → w600).
- `line-height` por defecto de titulares/labels/botón = 1.5 (poner `height:1.5`).
  Los display de dinero van a `height: 1.0` (tracking-tight, sin aire vertical).

---

## 3. Forma, radios y bordes — `app_dimens.dart`

El mock usa radios mayores que sus propios tokens. Valores **en uso**:

| Token nuevo | Valor | Uso |
|---|---|---|
| `radiusCard` | **16** (era 8) | cards, stat tiles, filas de transacción, inputs de formulario |
| `radiusPanel` | **24** (nuevo) | panel de analytics, card de settings, `AppCard` "grande" |
| `radiusSheet` | **40** (era 28) | esquinas superiores de bottom-sheets / `BottomActionPanel` |
| `radiusPill` | 100 (igual) | FAB, search pill, botones de icono, progress bars, dots, avatares, chips |
| `radiusButton` | **16** (igual) | botón primario full-width |
| `radiusBudget` | **12** (nuevo) | card de budget (`rounded-xl`, algo menos que el resto) |

Bordes:
- **Hairline translúcido** (`divider` = border/50) como divisor por defecto:
  cards, stat tiles, filas tx, inputs, separadores de settings.
- Borde completo (`border`) solo en: nav bar (top), sheets (top), y el "frame"
  si se emula (en móvil real no hay frame; ver §9).
- Foco de input: anillo 1px `accent` (`focusedBorder` ya lo hace; bajar width a
  1.0–1.5 y usar accent nuevo).

---

## 4. Superficies, sombras y efectos

- Fills sutiles = **muted translúcido**: `surfaceAlt` al 30/50/80% según caso.
  Stat tiles y campos de formulario usan `surfaceAlt @ 30%`; search pill `@ 50%`;
  pill de nav activo `@ 80%`.
  ```dart
  Color mutedFill(AppColors c, double a) => c.surfaceAlt.withValues(alpha: a);
  ```
- Sombras: una sola sombra suave. Mantener `AppShadows.card`. FAB y sheets con
  sombra más marcada (`shadow-xl`/`shadow-2xl`): añadir `AppShadows.fab` y
  `AppShadows.sheet` (mayor blur/offset).
- **Backdrop de modal**: `bg-background/80` + **blur**. En Flutter → barrera con
  `color: bg @ 80%` + `BackdropFilter(ImageFilter.blur(sigmaX:8,sigmaY:8))`.
- Scrollbars ocultos (ya por defecto en móvil). Safe-area inferior respetada
  (`SafeArea`/`MediaQuery.padding.bottom`) en nav y sheets.

---

## 5. Iconografía

- Estilo **línea fina** (lucide). En Flutter no hay lucide nativo: usar el
  paquete **`lucide_icons`** (o `lucide_icons_flutter`) para paridad 1:1, o
  mapear a Material "outlined" si se prefiere no añadir dependencia.
  > Decisión pendiente: `lucide_icons` (fiel al mock) vs Material outlined
  > (cero deps). Recomiendo lucide para el carácter exacto.
- Tamaños: nav **22**, FAB **24**, iconos de lista 18–20, inline 16.
- Icono de nav activo **engorda**: en lucide no hay strokeWidth variable por
  `IconData`; emular con `weight`/tamaño o usar la variante fill sutil. Mínimo:
  activo = `accent` + pill detrás; inactivo = `textMuted`.
- Color por defecto `textMuted`; activo/primario `accent` (o `text`).

---

## 6. Motion (Framer Motion → Flutter)

### 6.1 Cambio de tab
Cross-fade + slide horizontal (`opacity 0→1`, `x -20→0→20`). El shell ya hace
cross-fade/slide (`app_shell`); confirmar que usa `easeOutCubic` y ~250ms.

### 6.2 Bottom-sheets / `BottomActionPanel`
Slide up `y:100%→0` con **spring** (`damping 25, stiffness 200`). En Flutter:
- Modal sheets: `showModalBottomSheet` con `AnimationController` custom o
  `transitionAnimationController` usando `SpringSimulation` (o aproximar con
  `Curves.easeOutBack` suave sin overshoot fuerte).
- `BottomActionPanel` embebido: `AnimatedSize`/`SlideTransition`, curva tipo
  spring (`Curves.easeOutCubic` 200ms es aceptable; para spring real usar
  `SpringDescription(mass:1, stiffness:200, damping:25)`).
- Handle de arrastre: pill `48×6` (`w-12 h-1.5`) en `textDisabled`/muted, ya
  configurado en `bottomSheetTheme.dragHandleColor`; ajustar tamaño.

### 6.3 Pill de nav activo (morphing)
`layoutId="nav-pill"` con spring `stiffness 400, damping 30` que **morfea** entre
tabs. En Flutter no hay shared-layout nativo:
- Opción A (fiel): `Stack` en la nav con un `AnimatedPositioned`/`AnimatedAlign`
  del pill (fill `surfaceAlt @ 80%`, `radiusButton` 16) que se desliza al índice
  activo con `Curves.easeOutCubic` ~300ms.
- Opción B: reemplazar `NavigationBar` por barra custom (recomendado, ver §8) que
  dibuja el pill detrás del icono activo.
- El `indicatorColor` del `NavigationBar` actual ya es transparente → sustituir
  por el pill custom.

### 6.4 Header de balance colapsable (dashboard) ⭐
El efecto estrella. En el mock (`App.tsx` renderDashboard):
- Contenedor sticky top. Al `scrollTop > 40`:
  - Balance: `text-6xl → text-3xl` (60→30).
  - Padding: `pt-4 pb-0 → pt-2 pb-3`, aparece `border-b border-border/50`.
  - Tiles Income/Spent: colapsan (`grid-rows-[1fr]→[0fr]`, `opacity 1→0`,
    `margin-top 24→0`) — desaparecen plegándose.
  - Todo con `transition-all duration-300`.

Adaptación Flutter (dashboard_screen) — **dashboard híbrido**:

El mock es una única lista scrollable. Flutter mantiene el **swipe horizontal de
meses** (`PageView`) que el mock no tiene. Para conservar ambas cosas y verse
igual que el mock, el hero vive **fuera del `PageView`**:

```
Column
 ├─ MonthHeaderBar            (chevrons de mes, compartido)
 ├─ _BalanceHeader            (hero colapsable, compartido — FUERA del PageView)
 │    · "Total Balance" label
 │    · balance grande (ClashDisplay, colapsa 60→30)
 │    · Row de 2 stat tiles (Income · Spent) que se pliegan al scroll
 └─ Expanded PageView de meses
      └─ cada página: ListView scrollable
           · (opcional) bloque "Active budgets"
           · transacciones AGRUPADAS POR DÍA (header día + filas)
```

- El **swipe de meses es invisible**: solo cambia el contenido de la lista; el
  hero permanece fijo arriba y se comparte entre meses.
- El **colapso lo dispara el scroll interno** de la página de mes activa. Enganchar
  un `ScrollController` (o `NotificationListener<ScrollNotification>`) de la página
  visible a un `ValueNotifier<double> t` (0..1, clamp sobre offset 0..40) que
  alimenta el hero con un `AnimatedBuilder`.
- Interpolar con `t`:
  - `fontSize = lerpDouble(60, 30, t)` en el balance (ClashDisplay, tracking
    tight, tabular).
  - stat tiles: `Align(heightFactor: 1-t)` + `ClipRect` + `Opacity(1-t)` → se
    pliegan.
  - padding del header y opacidad del borde inferior hairline interpolados con `t`.
- Snap 300ms `easeOutCubic`. Resetear `t=0` al cambiar de mes o de tab (el mock
  hace `setScrolled(false)`).
- Label "Total Balance" (`textMuted`, medium) encima; tamaño `text-sm→text-xs`.

> Fidelidad dashboard: estética ~95%, layout ~95%. Único matiz real: el hero está
> fuera del `PageView` (el mock no tiene PageView, así que no hay referencia con la
> que discrepe). Diferencias funcionales — swipe de meses, long-press selección,
> tap→editar — son **invisibles en reposo**; se ve como el mock.

### 6.5 FAB scale-on-press
`hover:scale-105 active:scale-95`. En Flutter: envolver el FAB en un
`GestureDetector`/`AnimatedScale` (0.95 al `onTapDown`, 1.0 al soltar), curva
rápida ~120ms. Sombra `shadow-xl`.

### 6.6 Theme switch
`transition-colors duration-300` en toda la app. Flutter cambia de `ThemeData`
instantáneo; usar `AnimatedTheme`/`MaterialApp`(ya interpola) — el `lerp` de
`AppColors` (ya implementado) da el crossfade de color. Confirmar 300ms.

---

## 7. Especificación por componente (mapa a widgets existentes)

Estilo **solo**; el rol/estructura ya está en `LAYOUT.md`.

### `AppCard` (`app_card.dart`)
- Fondo `surface`, borde hairline `divider` (border/50), **radius 16** por
  defecto y variante **24** (`AppCard.large`) para panel de analytics y card de
  settings. Sombra suave opcional (el mock casi no la usa en cards internas — la
  reserva para frame/FAB/sheet). Recomiendo cards **sin sombra**, solo borde
  hairline, salvo donde hoy ya se use.

### Fila de transacción (dashboard / expenses)
Estructura mock (`TransactionRow`): card `rounded-2xl` (16) hairline,
`hover:bg-muted/50`. Contenido en Column izquierda:
1. **Línea categoría** `text-[11px]` uppercase tracking-wide muted →
   `CATEGORY • Subcategory`.
2. **Título** `text-sm` medium (Inter 14 w500).
3. **Método** `text-xs` muted.
Importe a la derecha: **ClashDisplay** `text-lg` tabular, con signo, color por
tipo: income=emerald, expense=rose, refund=**text** (foreground, neutro).
- Usar/actualizar `amount_text.dart` para color+signo+tabular+ClashDisplay.

### Header de grupo por día (dashboard)
Row `space-between`: etiqueta día uppercase muted semibold (`text-xs`) +
total del día tabular; total **≥0 en emerald**, `<0` en muted. Esto implica
**agrupar transacciones por día** en el dashboard (hoy es lista plana en
`AppCard`) — ajuste de layout menor; actualizar `LAYOUT.md` §Dashboard.

### Stat tile (Income/Spent) — dashboard hero
`bg-muted/30` (`surfaceAlt @30%`), radius 16, `p-4` (16), borde hairline. Dentro:
chip circular de icono 32px con fill color/10% e icono del color pleno
(income→emerald `ArrowDownRight`, spent→rose `ArrowUpRight`), label muted
`text-xs`, valor ClashDisplay `text-xl`.
> Nota: el mock reduce a **2 tiles (Income, Spent)** dentro del hero colapsable,
> con el Balance como número grande arriba. Hoy la app tiene 3 tiles
> (Spent/Income/Balance) en un `AppCard`. Adaptar a: Balance = hero grande;
> Income/Spent = 2 tiles que colapsan (§6.4, dashboard híbrido). `LAYOUT.md` ya
> actualizado con esta estructura.

### `ThinProgressBar` (`thin_progress_bar.dart`) + card de budget
- Barra: alto **6px** (`h-1.5`), track `surfaceAlt` (muted pleno), fill **color
  de dato** por budget (emerald/purple/amber/blue/rose), esquinas `rounded-full`.
- Card de budget: `bg-card` **radius 12** (`rounded-xl`), borde hairline,
  `hover:border-muted-foreground/30`. Header Row: nombre en **ClashDisplay**
  `text-base` + `spent / limit` (spent medium, `/ limit` muted normal). Debajo
  Row: barra + `%` a la derecha (muted, tabular, ancho fijo ~36px).
- Estado over-budget: fill en `over` (rose) — solo la barra/el %.

### Search pill (budgets)
`rounded-full`, fill `surfaceAlt @ 50%`, icono search 16 leading muted,
`text-sm`, foco anillo 1px accent. Botón archive a la derecha: icono en botón
redondo `hover:bg-muted`.

### Inputs de formulario (modales/entry)
`bg-muted/30` (`surfaceAlt @30%`), **radius 16**, borde hairline, label muted
medium `text-sm` encima con `px-1`, foco anillo accent. Actualizar
`inputDecorationTheme` (hoy usa `surfaceAlt` pleno y radius `radiusButton`).

### Donut (analytics)
Recharts pie `innerRadius 60 / outerRadius 80`, `paddingAngle 5`, sin stroke. En
Flutter (`fl_chart` `PieChart` o el actual): `centerSpaceRadius ≈ 60`, radio
sección ≈ 20 (80-60), `sectionsSpace ≈ 5` (equiv. paddingAngle), sin borde.
Colores = paleta de datos (hex semántico del mock, no chart tokens). Contenedor
~240–256px. Leyenda: Row dot(12px)+label(medium `text-sm`)+importe(medium)+
chevron muted 16.

### Card de settings (`settings_screen.dart` / `hairline_list_tile.dart`)
Un **único** card `radius 24` que envuelve todas las filas; filas separadas por
`border-b divider` (border/50, no en la última), `hover:bg-muted/30`. Fila:
icono tintado (muted) 20 + label medium + chevron 18 muted. Ya casi lo hace
`HairlineListTile`; ajustar: card contenedor a radius 24, separador translúcido,
sin borde exterior por fila.

### `EntityListTile` (`entity_list_tile.dart`)
Fila CRUD (Dismissible). Aplicar mismos tokens: radius 16 si es card
independiente, hairline divider, avatar/leading circular, título medium,
subtítulo muted, chevron muted. Mantener swipe edit/delete.

### FAB
56×56 (`w-14 h-14`), **círculo** (`radiusPill`), `bg-primary`=`accent`
(near-black light / near-white dark), `onAccent` para el icono, sombra
`shadow-xl`, icono contextual 24, **scale-on-press** (§6.5). Oculto en Settings
(ya). Nota: hoy el FAB usa `radiusButton` (16) → cambiar a círculo.

### Botón primario
`bg-primary`(accent) `onAccent`, **radius 16**, alto ~`py-4` (≈56, ya
`buttonHeight 52`→subir a 56), Inter `text-lg` (18) w500, `hover:opacity-90`,
`disabled:opacity-40`. Full-width en sheets/entry.

### Segmented (Expense/Income/Refund, dimension, budget type)
`bg-muted/50` (`surfaceAlt @50%`) con `p-1` (4), radius del contenedor
**`radiusPill`-ish**? El mock usa `rounded-xl` (12–14) contenedor y `rounded-lg`
segmento; segmento activo = `bg-card` (surface) + `shadow-sm`, texto medium
`text-sm`, activo=`text`, inactivo=`textMuted`. Ajustar
`segmentedButtonTheme`: `backgroundColor surfaceAlt@50`, `selectedBackgroundColor
surface`, sombra sutil en el seleccionado, radius contenedor ~14.

### Bottom sheet / `BottomActionPanel` (`bottom_action_panel.dart`)
Top `rounded-t-[2.5rem]` = **radius 40**, `bg-card`, borde superior `border`,
handle pill 48×6 muted, altura 70–80%, spring (§6.2). Botón de acción primario
full-width dentro. `bottomSheetTheme` ya define drag handle; subir `radiusSheet`
a 40.

### Nav bar (bottom)
80px alto (`h-20`), `bg-card`(surface), borde superior `border`, `pb-safe`.
Tab: icono 22 + label `text-[10px]` (10) medium; activo=`accent`, con **pill
morphing** (`surfaceAlt @80%`, radius 16) detrás del icono (§6.3). Ver §8 sobre
reemplazar `NavigationBar`.

### Header (top bar)
Transparente, `pt-10 pb-4 px-6`. Izquierda: nav de mes (chevrons redondos muted +
label mes uppercase muted `text-sm`) **o** título display (`text-2xl`
ClashDisplay). Derecha: botón toggle tema **redondo blanco con icono oscuro**
(`bg-white text-neutral-900`) — nota: este botón es blanco fijo en ambos temas en
el mock. Los chevrons de mes → `month_header_bar.dart`; el toggle vive en
Profile en la app Flutter (no en header) — mantener en Profile, pero con estilo
de botón redondo.

### Modales de entry/budget
Título ClashDisplay `text-3xl`, "Cancel" como texto muted a la derecha, importe
grande ClashDisplay `text-6xl` centrado, filas de campo `bg-muted/30` radius 16
con icono muted + label + chevron, botón Save primario full-width abajo.

---

## 8. ¿Reemplazar `NavigationBar` por barra custom?

El pill morphing (§6.3) y el label 10px + icono 22 con pill detrás no salen
limpios con `NavigationBar` de Material. **Recomendación**: barra custom (Row de
5 tabs en un `Container` de 80px) con:
- `Stack` por tab: pill animado (`AnimatedPositioned` sobre toda la fila, o
  `AnimatedContainer` por celda) + icono + label.
- Drag horizontal para cambiar de tab ya existe en el shell (conservar).
Esto es cambio de **implementación de un widget**, no de estructura → `LAYOUT.md`
sigue describiendo "NavigationBar (bottom) 5 tabs"; solo cambiar la nota si se
renombra el widget.

---

## 9. Notas de fidelidad y decisiones abiertas

- **Frame de móvil** (`max-w-md`, `border-x`, `shadow-2xl`): es andamiaje del
  mock para simular un teléfono en web. En la app real **no aplica** — la app ya
  ocupa la pantalla. Ignorar.
- **4 vs 5 tabs**: el mock tiene 4 (sin Expenses). La app tiene 5 con Expenses
  tras feature flag. Mantener la estructura de la app; el estilo de nav se aplica
  igual a 5 tabs.
- **Refund**: el mock solo muestra Expense/Income en el segmented del modal y
  pinta refund en color texto neutro. La app tiene Refund como tercer segmento
  (conservar) y hoy lo pinta ámbar. Decisión: ¿refund neutro (como mock) o
  mantener ámbar? Recomiendo **neutro (foreground)** para fidelidad; si se
  prefiere señal, ámbar `#F59E0B`.
Decisiones cerradas (2026-07-12):
- **Fuente display = Clash Display**, bundleada. Falta que el usuario deje los
  `.otf/.ttf` en `assets/fonts/` (pubspec ya cableado). Ver §2.1.
- **Iconos = `lucide_icons_flutter`** (ya era dependencia del proyecto). Ver §5.
- **Refund = color neutro** (`foreground`), no ámbar. Ver §7 fila de transacción.

### 9.1 Pantallas sin referencia en el mock (se extrapola)

El mock solo implementa 4 pantallas (dashboard, budgets, analytics, settings) +
2 modales *stub*. **No cubre**: Expenses, expense/budget entry con keypad y
pickers, drill-down de categorías, CRUD de settings (categories/tags/tag
groups/payment methods/events/projects), profile, export, backup, filtros,
reorder, selección múltiple. Para todas ellas **no hay referencia visual**: se
aplican los mismos tokens (color, tipo, radios, hairline, motion) para que
queden en la misma familia, pero el resultado es una **extrapolación**, no una
copia 1:1. Fidelidad esperable: "coherente con el sistema", no "clon del mock".

### 9.2 Gestos y funcionalidad — se conservan al 100%

El refactor es **solo piel**. No se toca ningún gesto existente: Dismissible
(swipe editar/borrar), long-press reorder, long-press selección múltiple, drag
horizontal de nav, swipe de meses en el `PageView`. El mock no tiene gestos, así
que no aporta nada aquí; se mantienen porque son función, no estilo.

---

## 10. Orden de ejecución sugerido

1. **Fuentes**: bundlear Clash Display + `pubspec`. Compila.
2. **Tokens** (`app_colors.dart`, `app_dimens.dart`): paleta mono-ink, semánticos
   Tailwind, paleta de datos, `divider` translúcido, radios 16/24/40, helpers
   (`borderSoft`, `mutedFill`, `iconChipBackground`, `appDisplay`).
3. **Theme** (`app_theme.dart`): `TextTheme` dos niveles + tabular en dinero,
   input/segmented/FAB/button/nav/sheet themes a los nuevos valores.
4. **Widgets base**: `app_card`, `amount_text`, `thin_progress_bar`,
   `hairline_list_tile`, `entity_list_tile`, `bottom_action_panel`,
   `month_header_bar`, FAB scale wrapper.
5. **Nav custom** con pill morphing (§8).
6. **Dashboard**: hero de balance colapsable + 2 stat tiles + agrupación por día
   (§6.4, §7). Actualizar `LAYOUT.md`.
7. **Resto de pantallas**: budgets (search pill + cards 12), analytics (donut +
   leyenda + panel 24), settings (card 24), entry/budget modales.
8. **Motion pass**: springs de sheets, transición de tab, theme crossfade.
9. **QA**: light+dark, colapso del balance, edición vs creación, i18n 5 idiomas.

---

## 11. Fuera de alcance

Repos, providers, RPC, esquema Supabase, i18n keys, rutas, navegación, lógica de
budgets/filtros/export/backup. Solo estilo y motion.
</content>
</invoke>
