# Estudio: estadísticas y análisis para Despeses

Investigación sobre qué métricas y análisis son útiles para el usuario, partiendo del
modelo de datos actual. Dividido en (A) lo calculable **hoy** con los datos que ya se
capturan y (B) propuestas que **requieren capturar datos nuevos**.

---

## 0. Inventario de datos capturados

Base para razonar qué se puede calcular.

| Entidad | Campos relevantes para análisis |
|---|---|
| **Expense** | `amount` (céntimos), `currency`, `type` (expense/income/refund), `date`, `description`, `notes`, `categoryId`, `paymentMethodId`, `eventId`, `projectId`, `createdAt` |
| **Category** | jerárquica (`parentId`), `color`, `icon`, `isDefault` |
| **Tag** / **TagGroup** | M:N con Expense vía `ExpenseTags`; agrupadas por grupo |
| **PaymentMethod** | `name`, `icon` |
| **Event** / **Project** | `startsAt`, `endsAt`, `description` |
| **Budget** | ámbito (category/tag/project/event), `amount`, `currency`, `budgetType` (months/range/total), `months`, `startsMonth`/`endsMonth` |
| **Profile** | `currency` base, `language` |

Regla contable ya establecida (AnalyticsRepository): suma con signo →
`income` se excluye, `refund` resta, `expense` suma. Todo el análisis de gasto debe
respetarla para ser consistente.

**Estado actual de Analytics:** un mes, moneda del perfil, pie de categorías con
drill-down (raíz → sub → sub-sub + slice "directo"), pie de tags. Nada más.

Limitaciones estructurales actuales a tener en cuenta:
- **Multi-moneda:** los análisis filtran por una sola moneda (la del perfil). Gasto en
  otras monedas queda invisible. Ver §B1.
- **Sin recurrencia explícita:** no hay campo que marque una transacción como
  suscripción/recurrente. Se puede *inferir* pero no es fiable. Ver §B2.
- **Sin comercio/payee:** solo `description` libre. Agrupar por comercio requiere
  parsear texto. Ver §B3.

---

## A. Calculable HOY (sin cambios de esquema)

### A1. Tendencia temporal (lo que más falta)

Hoy Analytics es una foto de un mes. El mayor salto de valor es la **serie temporal**.

- **Gasto mensual (línea/barras, 6–12–24 meses).** Total con signo por mes. Detecta
  estacionalidad y deriva.
- **Media móvil 3 meses.** Suaviza el ruido; línea de "gasto típico".
- **MoM (mes vs mes anterior)** y **YoY (mismo mes año anterior)** en % y absoluto.
- **Acumulado del mes vs mismo día del mes pasado ("burn-down/burn-up").** "Llevas
  X€ el día 12; el mes pasado a estas alturas llevabas Y€." Muy accionable en vivo.
- **Proyección fin de mes:** extrapolar el ritmo diario del mes en curso.
- **Gasto medio diario** por mes y **por día de la semana** (`date` es DateTime).
- **Heatmap calendario** (estilo GitHub): intensidad de gasto por día. Revela patrones
  (findes, día de cobro, etc.).

### A2. Ingresos vs gasto / flujo de caja

`type=income` ya se captura pero Analytics lo ignora. Hay una dimensión entera sin usar.

- **Cash-flow neto por mes:** ingresos − gasto (refund neteado). Positivo/negativo.
- **Tasa de ahorro:** `(ingresos − gasto) / ingresos`. KPI financiero clave.
- **Balance acumulado** a lo largo del tiempo (suma de netos mensuales).
- **Ingresos por categoría/fuente** (si se categorizan los ingresos).

### A3. Categorías en el tiempo (más allá del pie de un mes)

- **Stacked area / barras apiladas** de categorías raíz por mes.
- **Top movers:** categorías que más subieron/bajaron vs mes o media previa.
- **Ranking de categorías** del periodo con % del total y ticket medio.
- **Tendencia de una categoría** al hacer drill (sparkline por subcategoría).
- **% del gasto en la subcategoría "directa"** vs subcategorías (calidad de
  categorización).

### A4. Tags y grupos de tags

Los tags ya se agregan (pie plano). Ampliable:

- **Análisis por grupo de tags.** El `TagGroup` da un eje natural (ej. grupo
  "Necesidad/Deseo" → ratio necesidades vs caprichos; grupo "Persona" → gasto por
  persona). Muy potente y hoy sin explotar.
- **Tendencia temporal por tag/grupo.**
- **Cobertura de tags:** % de transacciones sin ningún tag (calidad de datos).
- **Cruce tag × categoría** (heatmap): p.ej. cuánto de "Trabajo" cae en cada categoría.

### A5. Métodos de pago

Dimensión capturada y **totalmente sin analizar hoy**.

- **Gasto por método de pago** (pie + tendencia). Tarjeta vs efectivo vs …
- **Ticket medio por método.**
- **% de gasto en efectivo** (a menudo el "gasto invisible").
- **Método por categoría** (¿el efectivo va sobre todo a…?).

### A6. Eventos y Proyectos

`startsAt`/`endsAt` permiten análisis con duración.

- **Coste total por evento/proyecto** (suma con signo).
- **Presupuesto vs real** cuando hay Budget con ese ámbito (ver A7).
- **Coste por día** de un evento (total / días de duración).
- **Desglose por categoría dentro de un evento** ("¿en qué se fue el viaje?").
- **Línea temporal de gasto del proyecto** (acumulado entre `startsAt` y `endsAt`).
- **Gasto fuera de rango:** transacciones asignadas a un evento pero con `date` fuera
  de `[startsAt, endsAt]` (control de calidad).

### A7. Presupuestos (Budgets)

Modelo rico (months/range/total, por category/tag/project/event) → mucho analizable.

- **Progreso: gastado vs presupuestado**, % consumido, restante. (Probablemente ya
  parcialmente en la pantalla de budgets.)
- **Ritmo vs tiempo transcurrido:** "vas al 60% del presupuesto y ha pasado el 40% del
  periodo" → semáforo de sobre-ritmo.
- **Proyección de cierre:** al ritmo actual, ¿acabarás dentro o fuera?
- **Histórico de cumplimiento:** de N presupuestos pasados, cuántos se cumplieron;
  desviación media.
- **Presupuestos `total`/`range`:** barra de avance sobre toda la vida del presupuesto.

### A8. Comportamiento transaccional

- **Nº de transacciones** por mes; tendencia.
- **Ticket medio, mediana, máximo** (la mediana resiste outliers mejor que la media).
- **Distribución de importes** (histograma): ¿muchos pequeños o pocos grandes?
- **Transacciones más grandes** del periodo (top 5).
- **Gasto hormiga:** volumen agregado de micro-transacciones (< umbral). Suele
  sorprender.
- **Frecuencia:** días con gasto vs días sin gasto ("no-spend days" — métrica
  motivacional).
- **Refunds:** total reembolsado, ratio refund/gasto, categorías con más devoluciones.

### A9. Patrones inferidos (heurística, no perfectos)

Extraíbles de los datos actuales aunque con limitaciones:

- **Posibles recurrentes:** transacciones con misma `description` (normalizada), importe
  similar y cadencia ~mensual → candidatas a suscripción. Base para "gasto fijo
  estimado". No fiable al 100% sin campo dedicado (§B2).
- **Fijo vs variable:** una vez identificado lo recurrente, separar gasto comprometido
  de discrecional.
- **Notas/descripciones:** métricas de calidad de datos (% sin descripción, % sin
  categoría).

### A10. Cuadro resumen / salud financiera

Un dashboard de KPIs derivados de lo anterior:

- Tasa de ahorro del mes, gasto vs media 3M, presupuestos en riesgo, mayor categoría,
  proyección fin de mes, racha de días sin gasto. Todo ya calculable.

---

## B. Requiere capturar datos nuevos (propuestas)

Ordenadas por relación valor/esfuerzo.

### B1. Tipo de cambio / normalización multi-moneda  ⭐ alto valor
**Falta:** tasas FX (histórica por fecha) o importe normalizado a moneda base.
**Desbloquea:** un total real que incluya gasto en varias monedas; análisis de viajes en
moneda extranjera; patrimonio consolidado. Hoy el multi-moneda queda **oculto**.
**Cómo:** añadir `baseAmount`/`fxRate` a Expense (congelado en el momento) o tabla de
tasas por día. Import opcional de tasas.

### B2. Marca de recurrencia / suscripciones  ⭐ alto valor
**Falta:** flag `isRecurring` + cadencia (mensual/anual) en Expense, o entidad
`RecurringExpense`.
**Desbloquea:** coste fijo mensual real, "suscripciones activas", alerta de subida de
precio de una suscripción, previsión de gasto comprometido, detección de suscripciones
zombie (dejaste de usar pero sigues pagando).

### B3. Comercio / beneficiario (merchant/payee)
**Falta:** campo estructurado `merchant` (hoy solo `description` libre).
**Desbloquea:** "top comercios", gasto por comercio en el tiempo, ticket medio por
comercio, sin depender de parsear texto libre.

### B4. Cuentas / saldos (accounts)
**Falta:** entidad `Account` (banco, efectivo, tarjeta) con saldo, y vínculo desde
Expense. `PaymentMethod` se acerca pero no lleva saldo.
**Desbloquea:** patrimonio neto y su evolución, conciliación, distribución de saldos,
transferencias entre cuentas (excluibles del gasto).

### B5. Importe planificado vs real por transacción
**Falta:** `plannedAmount` en Expense o en Event/Project.
**Desbloquea:** varianza planificado−real a nivel línea (más fino que Budget), útil en
viajes/proyectos.

### B6. Geolocalización
**Falta:** lat/lon o ciudad/país en Expense.
**Desbloquea:** mapa de gasto, gasto por ciudad/país (viajes), detección de gasto en el
extranjero. (Considerar privacidad.)

### B7. Adjuntos / recibos
**Falta:** adjuntar imagen/PDF a Expense.
**Desbloquea:** menos analítica que utilidad, pero permite futuro OCR → autocompletar
comercio/importe/impuestos.

### B8. Impuestos / propinas / deducibles
**Falta:** desglose `tax`, `tip`, flag `deductible`.
**Desbloquea:** informe de gasto deducible (autónomos), IVA soportado, análisis de
propinas.

### B9. Metas de ahorro (savings goals)
**Falta:** entidad `Goal` (objetivo, fecha límite, aportado).
**Desbloquea:** progreso hacia metas, aportación mensual necesaria, proyección de
consecución. Complementa la tasa de ahorro (§A2).

### B10. Estado / conciliación de transacción
**Falta:** `cleared`/`pending`, `excludeFromStats`.
**Desbloquea:** separar previsto de confirmado; excluir transferencias/reembolsos
internos que hoy distorsionan totales.

---

## Recomendación de priorización

**Fase 1 — explotar lo que ya hay (sin tocar esquema):**
1. Serie temporal de gasto mensual + media móvil + MoM/YoY (§A1).
2. Ingresos vs gasto y tasa de ahorro (§A2) — dimensión capturada e ignorada.
3. Método de pago y grupos de tags (§A5, §A4) — ejes capturados y sin analizar.
4. Coste por evento/proyecto y progreso de presupuestos con proyección (§A6, §A7).
5. KPIs de comportamiento: ticket medio/mediana, top gastos, días sin gasto (§A8).

**Fase 2 — datos nuevos de mayor ROI:**
1. Normalización multi-moneda (§B1) — corrige un punto ciego real.
2. Recurrencia/suscripciones (§B2) — separa fijo de variable, muy demandado.
3. Cuentas/saldos (§B4) si se quiere pasar de "tracker de gasto" a "finanzas netas".

El mensaje central: **gran parte del valor está sin extraer de datos que ya se
capturan** (tiempo, ingresos, método de pago, grupos de tags, eventos, presupuestos).
Empezar por ahí antes de ampliar el esquema.
