# Verificación de la UI original — 5 de octubre de 2026

## Actualización posterior: aplazamientos corregidos

El pendiente de aplazamiento/reactivación descrito en la auditoría inicial queda resuelto en el entorno local. Migraciones 024–026: solicitudes por club y partido, aceptación del rival, cancelación propia, acciones forzadas del administrador, reintentos idempotentes y archivo de las alineaciones previamente congeladas. La UI original usa sus mismos controles.

Se comprobó en navegador, en la temporada 2 de QA Integral A: solicitar/cancelar/repetir, aceptar con Bruno, solicitar/cancelar reactivación, aceptar con Ana, forzar ambas acciones y aplazar tras confirmar la alineación de Ana. Tras reactivar, ambos aparecen esperando y se puede confirmar inicio otra vez. Sus dos jugadores congelados y su confirmación quedaron archivados; los saldos permanecen en 271 M (Sur) y 117,5 M (Norte), sin reservas ni cargos.

La jornada no puede cerrarse mientras tenga partidos aplazados; reactivar devuelve el partido a su jornada original, no lo mueve automáticamente a una fecha posterior. Un resultado pendiente debe confirmarse o disputarse antes de solicitar aplazamiento; el administrador puede forzarlo y descartar esa propuesta sin consolidar gastos. Los partidos terminados no pueden aplazarse. La resolución reglamentaria por abandono se conserva.

Pruebas `game_postponements.sql` aprobadas: permisos (incluido espectador y administrador de otro torneo), cancelación, aceptación, repetición, archivo de cuatro jugadores y dos confirmaciones, bloqueo de resultados/cierre de jornada, reactivación y posterior finalización. Suite completa, TypeScript, compilación local y auditoría contable aprobados. Capturas: `.local-db/qa-browser/aplazamiento-aceptado.png` y `aplazamiento-reactivado.png`. La base remota no se modificó.

El resto del documento conserva los resultados de la auditoría inicial; los otros pendientes siguen vigentes.

## Resultado

El flujo principal se recorrió en el navegador, desde crear dos torneos hasta completar una liga y comenzar la temporada 2. Se corrigieron errores de integración encontrados durante el recorrido. **La aplicación todavía no tiene todas sus funcionalidades conectadas a la UI original.** No debe presentarse como una validación del 100 % ni como autorización para migrar producción.

Todas las operaciones se ejecutaron en `http://127.0.0.1:3100`, contra Supabase local (`127.0.0.1:54321`). Los tests SQL usan la base dedicada `mercatto_foundation_test` dentro de `supabase_db_mercatto`. No se modificó la base remota. Se conservaron los componentes y el aspecto de la UI original.

## Torneos de prueba

| Torneo | Participantes | Estado final |
| --- | --- | --- |
| QA Integral A — `DEV-36778710961944C99036742AA48C2034` | Ana QA / Prueba Sur; Bruno QA / Prueba Norte | Temporada 1 archivada; temporada 2 en lobby, clubes sorteados nuevamente |
| QA Integral B — `DEV-DF39EB14B4F6418E994FDFC53A49CAF0` | Carla QA / Prueba Sur | Temporada 1 en lobby; plantillas y presupuestos iniciales intactos |

Se utilizaron jugadores ficticios. Los enlaces personales están guardados exclusivamente en un archivo local ignorado; no se incluyen en este informe.

## Aislamiento y continuidad comprobados

En A, Ana compró Defensa Norte por 25 M tras una contraoferta, Bruno pagó la cláusula de Defensa Sur por 30 M y ganó Icono de Prueba Uno por 35 M. Se abrió invierno con una inyección de 10 M por club y se disputaron dos partidos, con salarios y multas.

| Club | A, al terminar la liga y después del sorteo de temporada 2 | B, después de todas las operaciones en A |
| --- | --- | --- |
| Prueba Norte | 117.500.000; Delantero Norte, Defensa Sur, Icono de Prueba Uno | 160.000.000; Delantero Norte y Defensa Norte originales |
| Prueba Sur | 271.000.000; Delantero Sur y Defensa Norte | 260.000.000; Delantero Sur y Defensa Sur originales |

La UI redondea 117,5 M a 118 M; el valor exacto se verificó mediante API y PostgreSQL. Ninguno de los dos torneos conserva reservas de dinero pendientes. El catálogo mantiene Defensa Norte en su equipo base Prueba Norte. El feed de B no mostró las publicaciones de A.

En la temporada 2 Ana obtuvo primero Reserva (110 M, incluida la inyección de invierno), usó su reroll y recibió Sur con 271 M. Bruno recibió Norte con su icono y el jugador adquirido por cláusula. El contador de rerolls se reinició por temporada; después del reroll de Ana desapareció la opción de otro. Los resultados de la temporada 1 permanecen archivados. El sorteo final volvió a asignar los mismos managers a Norte y Sur: el intercambio de esos dos managers no se ejercitó en navegador; las pruebas del modelo cubren reasignación y patrimonio del club.

## Matriz de pruebas en navegador

| Función | Resultado / alcance observado |
| --- | --- |
| Crear torneo, unirse, acceso personal de admin y participante | Correcto en A y B; reingreso repetido con cada identidad |
| Sorteo y confirmación de club | Correcto, con asignación del servidor |
| Reroll y reinicio por temporada | Correcto en temporada 2 |
| Navegar entre torneos | Correcto; las plantillas, saldos e identidad corresponden al torneo activo |
| Plantilla, búsqueda, filtros y Auto XI | Lectura y selección comprobadas; no hay 11 jugadores en los clubes ficticios |
| Guardar un XI completo desde UI | **No ejercitado**: los fixtures tienen 2–3 jugadores; guardado de borrador comprobado por HTTP en pruebas previas |
| Oferta → contraoferta → aceptar | Correcto: 20 M → 25 M; un único traspaso y cargo |
| Cancelar oferta | Correcto en invierno; reserva liberada |
| Cláusula | Correcto: Defensa Sur por 30 M |
| Votación de icono | Dos votos, cierre administrativo y apertura de subasta correctos |
| Pujas | 30 M y 35 M correctos; 999 M rechazados por saldo insuficiente; reserva del superado liberada |
| Cierre manual de subasta | Correcto después de arreglar el endpoint; ganador recibe el icono y paga 35 M |
| Cierre automático / carreras al vencer | Cubierto por pruebas SQL y de concurrencia, no esperando el vencimiento en navegador |
| Mercado de verano | Apertura y cierre correctos |
| Mercado de invierno | Apertura de 6 h, inyección de 10 M, oferta/cancelación y cierre correctos |
| Calendario con invierno abierto | Sigue accesible; confirmar inicio de partido se rechaza mientras el mercado está abierto |
| Crear liga | Calendario de dos jornadas y dos vueltas correcto |
| Confirmación de alineaciones | Ambos participantes confirmaron; servidor congeló las alineaciones |
| Proponer, disputar y confirmar resultado | Primera jornada 2–1: propuesta, disputa, nueva propuesta y confirmación correctas |
| Tarjetas de ambos participantes | Roja de Defensa Sur y amarilla de Defensa Norte conservadas al confirmar |
| Suspensión | Advertencia visible antes de jornada 2; API confirmó al jugador sancionado excluido del XI congelado |
| Validación administrativa | Jornada 2, 3–0, validada con el control original |
| Cerrar jornada y finalizar liga | Correcto; dos resultados históricos y gastos de ambos clubes |
| Clasificación y disciplina | Empate a tres puntos resuelto por diferencia de goles; Ana campeona; tarjetas visibles |
| Finanzas | Presupuesto, salarios pagados 3,5 M y multa amarilla 0,5 M de Sur comprobados |
| Historial deportivo | Temporada 1, campeón y ambos marcadores visibles |
| Historial de mercado | Verano: tres transferencias, 90 M, una cláusula y una subasta; invierno: cero transferencias |
| Nueva temporada | Correcto después de arreglar acción deshabilitada y limpiar equipo almacenado |
| Feed: perfil, texto, like y respuesta | Correcto; aislamiento de B comprobado |
| Copiar enlace y volver a entrar | Correcto; los enlaces se usaron para alternar participantes y torneos |
| Slots: habilitar | Preferencia se guarda y cambia a Encendidos |
| Slots: pool y juego | **Falla de integración**: regenerar devuelve rechazo; pantalla queda con pool en carga y muestra presupuesto 0/precio predeterminado |
| Aplazamiento de partido | **No conectado**; solicitud devuelve error explícito. Reactivación queda sin recorrido completo |

## Fallos corregidos durante esta revisión

- El service worker podía servir JavaScript antiguo en localhost, causando estados de ruleta y autenticación incorrectos. Se evita almacenar recursos locales en su manejador de caché.
- Cambiar de identidad podía conservar el nombre/escudo del equipo anterior. Se limpian y sincronizan con la asignación real.
- La ruleta trataba algunas respuestas de error como listas vacías. Ahora comprueba el estado HTTP.
- La compatibilidad de ofertas elegía incorrectamente al encargado de responder en la oferta inicial y contaba contraofertas dos veces.
- La cláusula usaba una acción inexistente del RPC de mercado; se conecta a la operación de cláusula correspondiente.
- Terminar una subasta intentaba cerrar una votación. La migración local 022 incorpora cierre administrativo con autenticación, ámbito de torneo e idempotencia.
- La confirmación de resultados perdía las tarjetas añadidas por el segundo participante. La migración local 023 conserva las del rival y permite declarar las propias en una transacción.
- El historial omitía las subastas por un nombre de tipo incompatible. Se mantiene `icon_auction` y se separan transferencias por ventana.
- El estado almacenado al entrar en invierno ocultaba el calendario. Se conserva la fase de liga y el indicador de mercado por separado.
- Los iconos aparecían como negociables aunque las reglas los excluyen. Se filtran en la oferta disponible.
- Algunos formularios de calendario y ofertas cerraban como si hubieran tenido éxito aunque el servidor rechazara la acción. Ahora presentan el error.
- Verificar un perfil social mostraba éxito anticipado; ya no aplica la insignia antes de una respuesta correcta.
- Nueva temporada estaba deshabilitada al terminar la liga local. Se habilita y sincroniza la ausencia de asignación mientras se sortea nuevamente.
- El resumen financiero proyectaba una jornada adicional con liga terminada. Se corrige el cálculo; compilación y tipos comprobados, sin volver a representar ese modal después de avanzar a temporada 2.

## Pendientes que impiden decir «todo funciona»

1. **Slots completos en la UI original:** pool, tiradas, premios, cobro y cupos todavía necesitan adaptación. El motor tiene pruebas de cupos y reclamaciones; eso no equivale a tener la pantalla integrada.
2. **Aplazamiento/reactivación:** las acciones originales no tienen correspondencia funcional en el adaptador local.
3. **Notificaciones:** la compatibilidad devuelve una lista vacía; no se validaron entrega, push ni suscripciones.
4. **Funciones sociales adicionales:** imágenes y verificación siguen rechazadas. La comprobación del error de verificación después del arreglo no se repitió en navegador. El like conserva tratamiento optimista que debe revertirse también ante errores HTTP.
5. **Acceso de invitado y regeneración del enlace:** no certificados en navegador; requieren revisar/adaptar los endpoints de la UI original. No se rotaron credenciales durante la prueba.
6. **Reinicios y cierre definitivo:** controles heredados siguen visibles aunque el modelo protege el historial y rechaza reinicios. Algunos manejadores del lobby no muestran esos errores. «Finalizar torneo» no equivale actualmente a un estado independiente de cierre permanente.
7. **Historial por manager después de reasignación:** el adaptador de transferencias consulta asignaciones actuales para algunos nombres; debe usar la asignación de la fecha del movimiento. Los movimientos y clubes sí permanecen, pero la atribución personal requiere una prueba con cambio de manager.
8. **XI completo, plantillas amplias y responsive:** falta repetir guardado y edición de once jugadores, escenarios de descansos en UI y distintos tamaños de pantalla. No se realizaron pruebas de carga, accesibilidad completa ni navegadores alternativos.
9. **Texto y contadores secundarios del mercado:** revisar el remitente de contraoferta, el texto de duración de ofertas y el límite mostrado de compras al consultar una ventana ya cerrada.

## Validación automatizada final

- `node scripts/test-db-local.mjs`: aprobado, incluidas migraciones 022 y 023; integridad, mercados, cláusulas, subastas, competición, casos límite, pool/social, propiedad concurrente y reservas. Los fixtures SQL revierten sus cambios.
- Nuevo `supabase/tests/game_ui_mutations.sql`: cierre de subasta reservado al admin, repetición sin doble cobro, tarjetas propias y preservación de roja del rival aunque el confirmante intente cambiarla, confirmación repetida sin duplicar gastos.
- `node scripts/test-original-ui-http-local.mjs`: aprobado, rutas originales y opciones atómicas de creación.
- `node node_modules/typescript/bin/tsc --noEmit`: aprobado.
- `node scripts/build-game-local.mjs`: aprobado con configuración local.
- Aserciones finales HTTP sobre A y B: presupuestos exactos, plantillas esperadas, cero reservas, dos partidos archivados y sancionado excluido; aprobadas.
- `node scripts/audit-game-local.mjs`: cero operaciones descuadradas, discrepancias cuenta/libro, propietarios activos duplicados, asignaciones activas duplicadas, partidos sin gastos ni publicaciones cruzadas. Deuda pendiente: cero.
- El inventario local del catálogo heredado devuelve **75 jugadores con varias relaciones de equipo**. No corresponde a duplicidad de contratos activos en las nuevas partidas; su procedencia histórica no se determinó en esta prueba. Debe depurarse al reconstruir el catálogo, sin inventar historial.

## Evidencia local

Capturas en `.local-db/qa-browser/` (directorio ignorado):

- `torneo-a-fichaje.png`: Sur después de comprar Defensa Norte.
- `torneo-b-original-final.png`: Sur en B mantiene sus dos jugadores originales y 260 M después de todas las operaciones de A.
- `subasta-finalizada.png`: icono adjudicado por 35 M.
- `temporada-2-patrimonio.png`: Norte conserva el icono y el jugador de cláusula tras el nuevo sorteo.
- `historial-90m.png`: tres fichajes por 90 M y conteos por tipo.
- `slots-pendiente.png`: evidencia del panel todavía sin conectar.

Los logs de compilación y pruebas, junto con la instantánea final sin credenciales, quedan en ese mismo directorio para reproducir el diagnóstico. La aplicación queda abierta en el historial de A.
