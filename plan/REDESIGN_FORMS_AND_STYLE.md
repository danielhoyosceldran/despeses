# Plan de Rediseño — Formularios Add/Edit + Estilo (Flutter)

Estado: propuesta. Alcance: reestructuración completa de los dos formularios
(transaction + budget) y sus panels, más una pasada de estilo terminal/fintech
sobre toda la app. La app funciona; esto cambia solo layout y estilo, nunca la
lógica de datos, repositorios ni RPC.

---

## 0. Decisiones cerradas (fuente de verdad)

- Patrón único: **full-screen** para ambos formularios. Se descarta el modal
  desktop centrado. Transaction cierra con flecha atrás; Budget cierra con X.
- Estilo: **terminal/fintech** (skill adjunto manda en todo lo visual).
- Border-radius: **todo recto (radius 0)** en toda la app. Decisión explícita
  del proyecto; se descarta el radio 10-14px que sugería el skill.
- Color de acento único: **azul `#2563EB`** (+ variante dark). Aplica a acciones
  principales, selección, foco, estado activo, progress bars, chevrons activos.
- Colores semánticos: solo en importes/valores — expense rojo, income verde,
  refund ámbar. Nunca como fondo, borde o relleno de UI.
- Ambos temas: light + dark.
- Datos: reales de Supabase. Cero mock.
- Todo el texto de UI vía i18n existente. Comentarios de código en inglés.

---

## 1. Sistema visual (aplicable a toda la app)

### 1.1 Tokens de color — `lib/core/theme/app_theme.dart`

- Cambiar `AppColors.light.accent` de `#3F6FB0` a `#2563EB`.
- Cambiar `AppColors.dark.accent` a una variante más luminosa para dark
  (p. ej. `#5B8DEF`), manteniendo contraste AA sobre `#0A0A0A`.
- Mantener el resto de la paleta grayscale ya definida (bg/surface/border/text).
- Mantener `AppSemanticColors` como está (ya cumple: income verde, expense rojo,
  refund ámbar, over rojo).

### 1.2 Radio de esquinas

- **Todo recto: radius 0 en toda la app.** Se mantiene el carácter terminal puro
  del theme actual (`BorderRadius.zero` en botones, inputs, chips, segmented
  controls, cards, sheets, dialogs, panels y navigation bar).
- No se introduce ningún token de radio. Se descarta la recomendación del skill
  de radio 10-14px en botones — decisión explícita del proyecto.
- El theme actual ya usa `BorderRadius.zero` en todos los componentes, así que
  esta sección no requiere cambios sobre lo ya implementado.

### 1.3 Tipografía (sin cambios estructurales)

- Se mantiene Inter para texto y JetBrains Mono para labels mono uppercase.
- Confirmar tabular figures en importes: aplicar
  `fontFeatures: [FontFeature.tabularFigures()]` a los estilos que muestran
  dinero (displaySmall usado por el keypad y los totales de dashboard/analytics).

### 1.4 Motion

- Transiciones de panel inferior: `AnimatedContainer`/`AnimatedSize` 180-220ms,
  curva `Curves.easeOutCubic`. Solo fade/slide/scale. Sin bounce ni overshoot.

---

## 2. Componentes compartidos a crear/modificar

Estos son la base; se hacen primero porque los formularios dependen de ellos.

### 2.1 `BottomActionPanel` (NUEVO) — `lib/presentation/widgets/bottom_action_panel.dart`

Panel inferior animado embebido en la pantalla (no `showModalBottomSheet`).
- API: `height` animada 0 -> contenido (max ~340px), `onDismiss`, `child`.
- Fondo `surface`, borde superior hairline `border`, esquinas rectas.
- Reemplaza el uso de sheets modales dentro de los formularios.
- Anima con `AnimatedSize` + `SlideTransition`.

### 2.2 `NumericKeypad` (MODIFICAR) — `numeric_keypad.dart`

- Anadir **formato de miles en vivo** en `_formattedAmount` (ya usa `NumberFormat`,
  cambiar a grouping activo manteniendo 2 decimales).
- Boton **"Next ->"**: rediseñar como botón lateral rotado 90 grados (RotatedBox)
  según spec, manteniendo `onNext` y el estado disabled si `amountCents == 0`.
- Mantener la mecánica de céntimos actual (POS-style), `00`, backspace.
- Botón "Next" recto, acento `#2563EB`.

### 2.3 Pickers -> contenido de panel, no sheets

Convertir el contenido de estos sheets en widgets embebibles dentro de
`BottomActionPanel` (extraer el `child` actual a un widget reutilizable, y
conservar además el wrapper `showModalBottomSheet` si se usa en otras pantallas
como Settings):
- `category_picker_sheet.dart` -> drill-down con breadcrumb + chevrons (ya lo
  hace; portar su cuerpo a panel). "Use X directly" se mantiene.
- `tag_picker_sheet.dart` -> grouped chips multi-select + botón "Next" (no
  auto-avanza). Anadir dot de color del tag si existe.
- `simple_picker_sheet.dart` -> lista plana, auto-avance al tocar.
- `month_picker_dialog.dart` -> convertir a panel embebido (12-month grid + year
  stepper) para el flujo de budget; mantener versión dialog si se referencia.

### 2.4 `ConfirmDialog`, `AppToast` (sin cambios de fondo)

- Solo pasada de estilo (acento, semánticos). Todo recto. Toast sigue siendo el
  único feedback de éxito/error. Sin banners inline ni errores por campo.

---

## 3. Transaction Form (REESCRITURA) — `expense_entry_screen.dart`

Rutas existentes intactas (`/expenses/new`, `/expenses/:id/edit`). Full-screen.

### 3.1 Estructura

- **Header**: flecha atrás (izquierda) + segmented control Type (Expense/Income/
  Refund) con color-coded del tipo activo usando semánticos en el texto/indicador,
  no como fondo.
- **Amount row**: importe grande centrado "€0.00" con currency read-only al lado.
  Comportamiento móvil: tocable, abre el keypad en `BottomActionPanel`.
- **Lista de filas tocables** (icon + label + valor actual + chevron):
  Date, Category, Payment method, Tags, Event, Project.
  - Cada fila abre su panel inferior (no sheet modal).
  - Description y Notes: inputs inline en su propia fila (teclado sistema).
- **Save bar** sticky abajo, siempre visible, botón acento full-width.

### 3.2 Paneles por campo

- **Date** -> calendar picker propio (mes con navegación, hoy marcada, semana
  empieza lunes). Sustituye el `showDatePicker` nativo actual.
- **Category** -> drill-down con breadcrumb "All > Food" + chevrons; hoja = select
  y cierra; branch = desciende.
- **Payment / Event / Project** -> lista plana, auto-avance.
- **Tags** -> grouped chips multi-select con dot de color, botón "Next ->"
  explícito (no auto-avanza).

### 3.3 Mecánica wizard

- Al confirmar un campo con panel de auto-avance, abre automáticamente el
  siguiente campo disponible, saltando los que no tienen datos (categorías,
  pagos, tags, eventos, proyectos vacíos se omiten — ya implementado en
  `_openNextStep`, se conserva la lógica).
- Tags no auto-avanza (multi-select).
- Sin swipe gestures, sin shortcuts de teclado.

### 3.4 Validación

- Save disabled si `amount <= 0` o sin fecha. Sin mensajes inline. Solo botón
  bloqueado. (Se mantiene `_canSave`, se anade check de fecha explícito.)

---

## 4. Budget Form (REESCRITURA) — `budget_entry_screen.dart`

Full-screen, mismo patrón fixed/panel que transaction, **cierra con X** (no flecha).

### 4.1 Estructura

- **Header**: botón X (izquierda) + título ("New budget" / "Edit budget").
- **Limit**: mismo patrón amount que transaction (importe grande + keypad en
  `BottomActionPanel`).
- **Name**: input inline.
- **Dimension type**: segmented control Category/Tag/Project/Event.
- **Dimension value**: fila que abre panel de lista plana. Oculto/locked al editar.
- **Budget type**: segmented control Range/Months/Total. Oculto/locked al editar.
- **Config condicional**:
  - **Range**: Start month + End month (opcional, con botón Clear) -> month-picker
    en panel inferior.
  - **Months**: chips removibles + panel multi-select con botón "Done".
  - **Total**: solo texto explicativo, sin campos.
- **Save bar** sticky abajo.

### 4.2 Modo edición (inmutabilidad)

- `dimension`, `dimension value` y `budget type` quedan **bloqueados** (gris, no
  editables) al editar. Solo `name` y amount editables — coincide con
  `BudgetRepository.updateNameAndAmount`. (Ya reflejado en `_isEdit`, se conserva.)

### 4.3 Validación

- Save disabled si falta name, amount, dimension, o months (si type = months).
  Se mantiene `_canSave`.

---

## 5. Pasada de estilo al resto de pantallas (sin cambio estructural)

Aplicar los tokens nuevos (acento `#2563EB`, tabular figures en importes) a:
Dashboard, Expenses (lista + filtros), Budgets (cards + segmented Active/Expired),
Analytics (donut + leyenda), Settings y subpantallas CRUD, Profile, Backup, y el
`app_shell` (bottom nav 5 tabs + FAB). Todo recto (radius 0).

- FAB: fondo acento `#2563EB`, icono monocromo, recto.
- Progress bars de budgets: track grayscale, fill acento; estado "over budget"
  usa semántico `over` (rojo) solo en la barra/texto.
- Importes en todas las listas: color semántico por tipo, tabular figures.
- Segmented controls: activo con acento.

No se toca navegación, rutas, ni lógica de ninguna de estas pantallas.

---

## 6. Orden de ejecución (fases)

1. **Tokens & theme** (§1): acento, tabular figures. (Radio no cambia: ya recto.)
   Compila, no rompe nada.
2. **Componentes base** (§2): `BottomActionPanel`, keypad (miles + Next rotado),
   extracción de pickers a contenido embebible.
3. **Transaction form** (§3): reescritura completa sobre los componentes base.
4. **Budget form** (§4): reescritura completa reutilizando §2 y patrón de §3.
5. **Pasada de estilo** (§5) al resto de pantallas.
6. **QA**: ambos temas (light/dark), edición vs creación, wizard con datos
   vacíos, validaciones, i18n en los 5 idiomas.

---

## 7. Fuera de alcance (no tocar)

- Repositorios, providers, RPC, esquema Supabase, i18n keys (solo se consumen).
- Rutas y navegación existentes.
- Lógica de cálculo de budgets, filtros, export, backup.
- Datos mock: no se introducen; todo contra datos reales.

---

## 8. Riesgos / notas

- Todo recto (radius 0): coherente con el theme actual, sin cambios en esa capa.
- El keypad ya acumula en céntimos: el formato de miles es solo presentación, no
  cambia la mecánica.
- Convertir sheets modales en paneles embebidos afecta solo a los formularios;
  Settings puede seguir usando los sheets modales si se conserva su wrapper.
