# Saldo por método de pago y arrastre entre meses (propuesta futura)

Estado: **no implementado**. Documento de análisis para retomar más adelante.

## Objetivo

Evaluar si vale la pena añadir a la app la posibilidad de:

1. Llevar el saldo de cada método de pago (cuenta, tarjeta, efectivo...).
2. Que ese saldo se arrastre de un mes a otro (en vez del modelo actual, donde
   cada mes se calcula de forma independiente).

Todo esto de forma **compatible** con el modo actual (transacciones mes a mes
sin influencia entre meses), no como sustituto.

Recordatorio de filosofía de la app (ver CLAUDE.md): la app lleva control de
gastos/ahorros mensuales y una visión global, pero **no** pretende ser un
reflejo fiel de la cuenta bancaria ni del patrimonio real del usuario.

## Situación actual (modelo de datos)

- Storage: Drift (SQLite), schema en `lib/data/tables.dart`, `schemaVersion`
  actual = 9 (`lib/data/database.dart`).
- Tabla `Expenses` (`tables.dart:137`): `amount` siempre positivo, `type`
  (`expense` / `income` / `refund` / `ahorro`), `paymentMethodId` FK nullable
  a `PaymentMethods`. El signo (suma/resta) se deriva en runtime a partir del
  `type`, no se guarda.
  - Convención de signos: gastos y ahorros restan; ingresos y reembolsos suman.
- Tabla `PaymentMethods` (`tables.dart:83`): entidad real (id, nombre, icono,
  posición), sin ningún campo de saldo.
- No existe ningún concepto de saldo, cuenta, saldo inicial o arrastre entre
  meses. Lo más parecido es `cumulativeBalance` en
  `lib/domain/repositories/analytics/analytics_cashflow.dart:64`, que es una
  suma acumulada solo para un gráfico, no persistida y no por método de pago.
- La vista mensual (`_Totals.of`, `dashboard_screen.dart:534`) recalcula los
  totales de cada mes de forma independiente, sin arrastre.

## Ventajas de tener saldo por método + arrastre

- Saldo real disponible por cuenta/tarjeta, no solo el flujo de un mes.
- Visibilidad de desfases: si un mes se gasta más de lo que entra, el mes
  siguiente arrastra ese déficit sin tener que mirar el banco.
- Permite "fondos" tipo hucha por método (efectivo, cuenta ahorro) que
  acumulan entre meses.
- Facilita en el futuro una reconciliación aproximada con el banco real, si
  algún día se quisiera.

## Coste / riesgos

- Migración de datos: cada método de pago necesitaría un saldo inicial (y
  fecha de referencia).
- Complejidad de UI: pantalla nueva (o extendida) para ver saldos y, si se
  quiere, transferencias entre métodos.
- Riesgo de romper la independencia mes-a-mes actual si se implementa mal
  (un mes afectando el saldo mostrado de otro mes sin que el usuario lo
  espere).

## Cómo compatibilizar ambos modos

La idea es que sea **aditivo**, no un cambio de modelo:

1. Nueva tabla, p.ej. `PaymentMethodBalances` (o campo `openingBalance` en
   `PaymentMethods`): saldo inicial + fecha de referencia por método.
2. Nueva query de saldo acumulado = saldo inicial + suma histórica de todas
   las transacciones de ese método hasta una fecha X. A diferencia de las
   queries actuales (`expensesInRange`, `PaymentAnalytics.byMethod`), esta no
   estaría acotada a un rango/mes.
3. Nueva pantalla/tab "cuentas" con el saldo por método, reutilizando el
   patrón de agregación ya existente en
   `lib/domain/repositories/analytics/analytics_payment.dart`.
4. La vista mensual actual no se toca: sigue sumando solo transacciones del
   mes, exactamente igual que ahora. El arrastre entre meses sería una vista
   alternativa/opcional sobre los mismos datos, no un reemplazo.

## Tamaño estimado del cambio

Cambio medio, acotado, no trivial:

- 1 migración de schema (v9 → v10).
- 1 tabla nueva (o campo nuevo en `PaymentMethods`).
- 1 repositorio nuevo para saldo acumulado por método.
- 1 pantalla nueva ("cuentas" / saldos).
- Sin romper nada existente, porque es una capa aditiva sobre lo que ya hay.

## Siguiente paso

Cuando se decida implementar: pasar por Plan mode para desglosar tareas
concretas (migración, repositorio, UI, actualizar LAYOUT.md/STYLE.md según
corresponda).
