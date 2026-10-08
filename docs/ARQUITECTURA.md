# Mercatto — arquitectura implementada

Actualizado: 2026-10-05. Partidas nuevas con lógica completa implementadas y verificadas en local. El diagnóstico y el plan de migración original permanecen en [rediseno-datos-y-flujos.md](./rediseno-datos-y-flujos.md); el detalle operativo vigente está en [IMPLEMENTACION_LOCAL.md](./IMPLEMENTACION_LOCAL.md).

## Estado actual

- Modelo privado game con catálogo congelado, clubes persistentes, contratos e historial por torneo.
- Presupuesto por club, reservas y libro inmutable equilibrado; mutaciones transaccionales con bloqueo del torneo e idempotencia.
- Mercado de verano/invierno, ofertas, contraofertas, libres, cláusulas, votaciones y subastas con tiempo.
- Cupos diarios y por ventana, ruleta de clubes y giros de libres, liberaciones voluntarias y por deuda.
- Calendario, alineaciones congeladas, resultados por consentimiento o resolución administrativa, clasificación, salarios, multas y suspensiones por jugador/temporada.
- Finalización deportiva, temporadas sucesivas, cambios de gestor, salida y sustitución de participantes.
- Muro por torneo con publicaciones, respuestas y likes; identidades preservadas.
- Interfaz original conectada al modelo de clubes solo en local; API heredadas bloqueadas y permisos de navegador restringidos.

## Recorrido técnico

Navegador → /api/game/tournaments → RPC PostgreSQL con service_role → tablas privadas game. Los tokens se validan contra el torneo en servidor/base. Todas las acciones económicas y deportivas de un comando comparten transacción. Un proceso local cada 15 segundos cierra votaciones/mercados, adjudica subastas y resuelve abandonos vencidos. Consultar estado no adjudica ni cobra.

El esquema público mantiene catálogo, metadatos de torneo/miembro y referencias sociales por compatibilidad. Las plantillas del juego nunca escriben team_players ni precios globales. Las claves compuestas impiden referencias entre torneos. Finalizar un partido no puede duplicar gastos ante dos confirmaciones concurrentes.

## Valores de negocio

Patrimonio por club confirmado por David. Los valores todavía no confirmados quedan configurables antes de iniciar: plantilla 0–35 para fixtures locales, dos libres básicos y uno premium diarios, una reelección, giro de cinco millones, dos compras invernales, ingreso estacional cero y plazo de sustitución tres días. La elección explícita y la ruleta están disponibles en pretemporada; tras sortear se aplica el límite de reelecciones.

## Verificación

Migraciones desde cero y escenarios SQL, concurrencia real de PostgreSQL, HTTP completo y regresiones de mercado/cláusulas/subastas; TypeScript, ESLint y compilación aprobados. Auditoría local de cuentas/libro, propiedades, asignaciones e historial deportivo. Comandos y limitaciones en IMPLEMENTACION_LOCAL.md.

## Lo que requiere un paso externo

1. Incorporar el catálogo recreado por David y seleccionar sus IDs para partidas nuevas. La inicialización completa rechaza pertenencias duplicadas.
2. Decidir si los torneos antiguos se archivan o se importan con estado visible y anomalías declaradas. Su historial perdido no se puede reconstruir de forma fiable.
3. Ensayar respaldo/restauración e importación en un proyecto remoto de pruebas, autorizar corte y desplegar backend/configuración/worker juntos. No aplicar permisos nuevos mientras la aplicación remota siga usando el backend antiguo.

No se modificó la base remota, no se desplegó y no se hizo push. Los respaldos y las credenciales locales están ignorados por Git.
