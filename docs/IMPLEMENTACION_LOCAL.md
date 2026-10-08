# Implementación local del modelo de clubes

> Estado vigente (2026-10-05): flujo completo para partidas nuevas en local. Las etapas anteriores que siguen debajo son el registro histórico; sus listas de pendientes han sido cubiertas por el cierre descrito aquí.


## Integración con la interfaz original

Las rutas habituales ya sirven la aplicación: portada, creación, unión, reingreso, lobby, ruleta, equipo, mercado, subastas, calendario, clasificación, historial y feed. /game permanece como laboratorio independiente. La portada ya no redirige al laboratorio. Se mantienen los formularios, la barra lateral, la navegación móvil, las tarjetas de equipo y la cancha con arrastre del diseño original; los controles de mercado y competición utilizan las API del modelo de clubes.

LocalDashboard sustituye el contenido heredado solo con el modo local y la URL local exacta. Las páginas heredadas no se montan en ese modo, ni ejecutan sus consultas directas o sus suscripciones antiguas. El backend remoto conserva su comportamiento anterior. Las API heredadas siguen bloqueadas localmente.

La migración 019 guarda atómicamente las opciones del formulario original (reelecciones, fichajes de verano y protección de cláusulas), con reintentos consistentes. Los borradores de formación permanecen en el navegador; confirmar el partido guarda en servidor sus jugadores elegibles y la instantánea histórica. La ruleta visual muestra el club elegido por el servidor. El enlace privado de recuperación conserva participante y administrador; cerrar sesión no abandona el torneo. Las notificaciones push heredadas se ocultan localmente, pues su backend no forma parte del nuevo modelo.

Validación adicional: node scripts/test-original-ui-http-local.mjs verifica rutas sin redirección a /game, opciones de creación y reintentos. Se verifican también la UI en el navegador, TypeScript, ESLint, compilación y las pruebas completas de competición.

## Decisiones confirmadas por David

- El patrimonio pertenece al club dentro del torneo. Un nuevo administrador recibe su plantilla y presupuesto; cambiar de club no lleva consigo el patrimonio del anterior.
- Docker funciona y se permite preparar una base local con datos de prueba. La implementación se valida localmente antes de cualquier intervención remota.
- El catálogo actual se recreará más adelante; su depuración no bloquea el trabajo de lógica. Se utilizan datos ficticios para desarrollar y verificar los flujos.


## Cierre de implementación: partida completa local

Las migraciones 009–018 completan liga/calendario, votaciones, liberaciones, reglas diarias, ruleta, gastos, deuda, abandonos, sustituciones e integración social. Se ensayaron en la base dedicada y se aplicaron únicamente a postgres local, con respaldos automáticos en .local-db.

La creación HTTP usa game_create_entry y activa por defecto las reglas completas. complete:false queda como modo explícito de laboratorio para pruebas anteriores aisladas; cambiar el modo con la misma clave de creación se rechaza. Los torneos anteriores de prueba no se convierten automáticamente. La interfaz crea siempre partidas completas.

### Reglas configurables antes del primer mercado o liga

| Regla | Valor inicial local |
|---|---|
| Plantilla mínima / máxima | 0 / 35 (mínimo 0 permite el catálogo ficticio de dos jugadores; cambiar antes de una liga real) |
| Libres diarios básicos / premium | 2 / 1; premium OVR ≥ 84; día de Bogotá |
| Reelecciones de ruleta | 1, además del primer giro |
| Límite de compras de invierno | 2, independiente del verano |
| Ingreso al comenzar la siguiente temporada | 0 |
| Coste del giro de libres | 5 millones |
| Plazo para sustituir a quien abandona | 3 días |

Estos valores son propuestas configurables, no decisiones confirmadas del usuario. La elección explícita se conserva para probar clubes y la ruleta es opcional; tras un sorteo solo se cambia mediante sus reelecciones limitadas. El patrimonio siempre permanece en el club.

### Flujos cerrados

- **Votación:** un voto irrevocable por club de un electorado congelado. Los candidatos son iconos libres de la instantánea. Gana el más votado; empate o ausencia de votos se resuelve por UUID ascendente. La votación se cierra al vencer o cuando todos votan y el administrador lo solicita, y crea una subasta de forma atómica. No se abre una subasta directa en modo completo. Cerrar la ventana cancela la votación pendiente. El proceso periódico realiza el cierre automático.
- **Libres:** candidatos sin propietario o de clubes sin administrador; el fichaje desde estos últimos cierra únicamente su contrato en ese torneo y registra la procedencia. No paga al club sin administrador ni cambia su saldo, ni escribe el catálogo. Contrataciones directas y resultados de giros comparten cupos por club/día/nivel y cupos generales de ventana. Los giros cobran una sola vez, duran cinco minutos y no reservan propiedad; aceptar valida otra vez disponibilidad y fondos, cobra el jugador y consume cupos. Rechazar/caducar no consume cupos ni reembolsa el giro.
- **Liberación voluntaria:** durante mercado abierto, propietario autenticado, mínimo de plantilla y sin partido activo. Cierra contrato y conserva evento histórico; no tiene reembolso ni devuelve cupos. El jugador reaparece desde el día siguiente para otros clubes. El antiguo club espera a otra ventana. Las ofertas pendientes por el jugador se invalidan y liberan reservas dentro de la misma transacción.
- **Liga:** ida o ida y vuelta, calendario circular con descansos para cantidad impar, clubes participantes congelados, como máximo un partido por club/jornada. Generarla requiere dos clubes y mercado cerrado. Cambiar libremente de club deja de ser posible en liga.
- **Partidos:** cada club confirma una alineación propia elegible; queda congelada toda la plantilla con nombre, OVR, posición y precio, diferenciando alineación/reservas. Ambos deben confirmar para iniciar. Solo se juega la jornada abierta y con mercado cerrado. Un club propone resultado y tarjetas; el rival confirma o disputa, y el administrador puede resolver un partido ya iniciado. La confirmación finaliza partido, tarjetas, sanciones, salarios, multas, liberaciones y libro en una sola transacción. Historial deportivo y alineaciones se mantienen después de transferencias.
- **Disciplina:** tres amarillas acumuladas generan un partido de sanción; una roja o doble amarilla, dos. Duplicados se normalizan por jugador/partido. Una suspensión sigue al jugador de la temporada al cambiar de club, se sirve al finalizar un partido de su club sin alinearlo y expira al finalizar la temporada. No se cumple una sanción nueva en el partido que la origina.
- **Gastos:** 10 % del precio del contrato por temporada, dividido por los partidos del club y redondeado hacia abajo; multa de 0,5 millones por amarilla y 2 por roja. La plantilla congelada determina los gastos y conserva su desglose. Si no alcanza el saldo, libera contratos por precio descendente y reembolsa 50 % hasta cubrirlo; esta medida obligatoria puede superar el mínimo de plantilla. Si quedan gastos sin cubrir y no quedan contratos con reembolso, registra deuda explícita, cobra solo lo disponible y bloquea compras. Pagar deuda utiliza saldo disponible y deja asientos equilibrados. No crea dinero artificial ni saldos negativos sin respaldo.
- **Invierno:** una sola ventana después de cerrar floor(total_jornadas/2), mínimo jornada 1, antes de confirmar la siguiente alineación. Sus límites son independientes. La jornada sigue detenida mientras el mercado esté abierto. El verano ocurre antes de generar liga, una vez por temporada.
- **Continuidad:** cerrar todas las jornadas finaliza la liga y expira sanciones. La nueva temporada conserva contratos, cuentas, participantes activos e historial; cierra asignaciones anteriores y permite nuevas elecciones. El ingreso configurado se registra una sola vez por club/temporada. No existe un botón que borre/restablezca el historial.
- **Salida:** exige mercado cerrado y ausencia de partido en juego. Conserva miembro/publicaciones, cierra su asignación y registra salida. El club conserva plantilla y presupuesto. El administrador puede incorporar un sustituto activo sin club; al vencer el plazo, el proceso local resuelve partidos pendientes de la jornada abierta por 0–3, sin salarios inventados. Si ambos abandonaron, 0–0. El cierre de jornada sigue siendo explícito.
- **Social:** publicaciones, respuestas y likes del torneo a través de servidor; idempotencia, validación de pertenencia y restricciones de referencias. Las publicaciones del participante que sale permanecen. No se reconstruyen perfiles globales a partir de tokens.

### Corte local y acceso

Con modo local y URL exacta, las rutas habituales utilizan el modelo de clubes y /game conserva el laboratorio. Las API de juego antiguas responden 410. Las tablas mutables públicas quedan con RLS y sin permisos anon/authenticated; el catálogo pierde permisos de escritura desde navegador. Las RPC nuevas solo pueden ejecutarse con service_role. El navegador envía credenciales de participante/administrador al servidor y no escribe tablas. La base remota y su aplicación habitual no recibieron estas migraciones. **No aplicar la migración de permisos al remoto sin el corte de backend correspondiente.**

### Verificación y ejecución

Ejecutar Next y el proceso periódico local en terminales separadas:

```powershell
node scripts/db-local.mjs migrate
node scripts/setup-game-local.mjs
node node_modules/next/dist/bin/next dev --hostname 127.0.0.1 --port 3100
node scripts/run-game-worker-local.mjs
```

Pruebas y auditoría:

```powershell
node scripts/test-db-local.mjs
node scripts/test-game-http-local.mjs
node scripts/test-clause-http-local.mjs
node scripts/test-auction-http-local.mjs
node scripts/test-competition-http-local.mjs
node scripts/audit-game-local.mjs
node scripts/build-game-local.mjs
```

SQL prueba liga con dos y tres clubes, continuidad, invierno, suspensión tras traspaso, gastos, deuda, liberación forzosa, rollback después de escrituras financieras, votación periódica, origen de libres y privilegios. Las pruebas HTTP recorren las rutas Next y ejecutan confirmaciones simultáneas con misma y distintas claves: un solo resultado y un solo cobro. Se mantienen las pruebas concurrentes de fichajes, cláusulas y subastas. TypeScript y ESLint aprobados; compilación de producción aprobada usando exclusivamente configuración local explícita.

La auditoría escribe .local-db/migration-audit.json sin credenciales. Verifica libro, propietarios, asignaciones, finanzas de partidos y anomalías del catálogo/legado. Se encontraron 75 jugadores con múltiples equipos base; David recreará el catálogo. No se inventó la historia perdida ni se migraron torneos antiguos. El respaldo se conserva para reversión; para ensayar restauración usar una base aislada, nunca sobrescribir datos de un entorno activo.

## Segunda etapa: flujo local conectado

La migración `20261005000200_game_local_flow.sql` incorpora creación atómica de torneo/participante/clubes, ingreso, asignación autenticada, lectura coherente de patrimonio y simulación de cambio de temporada. Se aplicó exclusivamente en local, tras otro respaldo.

La pantalla `/game` permite probar estos flujos. Usa tres clubes ficticios, cuatro jugadores en plantilla y un jugador libre. Los datos de prueba se añaden al catálogo bajo identificadores reservados; no se borran ni corrigen los jugadores anteriores. Cada nuevo torneo copia exclusivamente ese subconjunto. El presupuesto inicial se calcula una sola vez con la fórmula actual de OVR: 100 millones + (88 - media OVR) × 20 millones, redondeado a 5 millones y limitado entre 100 y 400 millones; un club vacío recibe 100 millones.

La API `/api/game/tournaments` utiliza funciones de PostgreSQL accesibles únicamente por service_role. Los clientes envían tokens personales; la base valida su pertenencia al torneo y distingue la credencial administrativa. Las mutaciones requieren una clave UUID `Idempotency-Key`. Creación e ingreso recuperan las mismas credenciales en un reintento; los resultados que contienen credenciales quedan en tablas privadas, con respuestas HTTP sin caché. Estas credenciales de prueba deben guardarse si se desea recuperar acceso después de recargar.

Para habilitarlo:

```powershell
node scripts/db-local.mjs migrate
node scripts/setup-game-local.mjs
node node_modules/next/dist/bin/next dev --hostname 127.0.0.1 --port 3100
# Abrir http://127.0.0.1:3100/game
node scripts/test-game-http-local.mjs
```

El configurador obtiene las claves de los contenedores locales sin imprimirlas y las guarda en `.env.development.local`, ignorado por Git. El servidor exige `MERCATTO_GAME_MODEL=local` y la URL exacta `http://127.0.0.1:54321`; rechaza una URL remota. La pantalla también se oculta si no está habilitado el entorno local. No copiar esta configuración experimental a producción.

Estos torneos tienen estado `prototype` y los verificadores compartidos rechazan usarlos con las operaciones autenticadas antiguas. Los endpoints y las pantallas habituales continúan con su comportamiento anterior. La selección de club aquí es explícita, para probar el dominio; falta integrar la ruleta y el resto de reglas deportivas. El botón de siguiente temporada simula el cierre exclusivamente en estos prototipos: todavía no finaliza una liga real.

Las pruebas SQL del flujo se ejecutan desde cero con el rol service_role y comprueban creación/reintentos, fórmula de apertura, participantes duplicados, club ocupado, credenciales incorrectas, autoridad administrativa, conservación del patrimonio y reversión completa ante fallos. Las pruebas HTTP verifican el recorrido de las rutas Next y dejan dos torneos locales de prueba; no imprimen sus tokens.

Verificado el 2026-10-05: pruebas SQL y de concurrencia aprobadas, pruebas HTTP aprobadas, TypeScript sin errores y ESLint de los archivos nuevos aprobado. Se comprobó en el navegador la creación de un torneo y la asignación de Prueba Norte, con sus dos jugadores y 160 millones de presupuesto. En este entorno Windows fue necesario ejecutar TypeScript y Next fuera del sandbox porque denegaba la lectura de algunas dependencias de pnpm; esto no cambió el destino local de la base.

## Tercera etapa: mercado y fichajes transaccionales

La migración `20261005000300_game_market.sql` se aplicó exclusivamente en la base local, con respaldo previo. Añade ventanas por temporada, cupos por club/ventana, ofertas con reserva de dinero y cupo, traspasos históricos y verificación diferida de que cada saldo coincide con su libro financiero.

La pantalla `/game` permite abrir/cerrar ventanas de verano e invierno como administrador, enviar ofertas, aceptarlas/rechazarlas como vendedor, cancelarlas como comprador y contratar jugadores libres. El selector de participantes conserva en memoria los accesos utilizados para probar ambos lados de una operación. Recargar la pantalla borra esos accesos en memoria; las credenciales siguen siendo recuperables si se guardaron.

Reglas implementadas para este prototipo:

- Todas las operaciones bloquean primero el torneo. Los vencimientos se comprueban con `clock_timestamp()` después de obtener el bloqueo. Una operación admitida antes del cierre puede completar su misma transacción; una que obtiene el bloqueo después del vencimiento se rechaza.
- Las ofertas tienen clubes comprador/vendedor fijos. Crear una oferta reserva saldo disponible y un cupo; no paga todavía al vendedor. El vendedor acepta la oferta inicial; en la cuarta etapa puede responder con una contraoferta que debe aceptar el comprador. El comprador puede cancelar la negociación. No se ofrecen jugadores de clubes sin administrador.
- Aceptar mueve propiedad, débito/crédito, libro, cupos e historial en la misma transacción. Las ofertas rivales por ese jugador se invalidan y sus reservas se liberan. Cualquier fallo revierte todos estos cambios.
- El libre se contrata al precio de su instantánea en el torneo. Un importe enviado por el cliente no lo modifica. La contrapartida financiera es la cuenta del sistema. Los iconos quedan fuera de estos flujos hasta integrar sus subastas.
- El límite es `max_transfers` del torneo, copiado al abrir cada ventana (3 por defecto). Las compras efectivas consumen cupos durante esa ventana; vender no los devuelve. Ofertas canceladas, rechazadas, invalidadas o expiradas liberan sus cupos reservados. Cada nueva ventana tiene contadores nuevos y conserva el historial anterior. Los límites adicionales exclusivos de libres y las reglas especiales de invierno siguen pendientes.
- Cerrar el mercado cancela las ofertas pendientes o las marca vencidas y libera sus reservas. Hasta cerrar la ventana se impide cambiar administradores/clubes o avanzar de temporada. El vencimiento impide nuevas compras; la cuarta etapa añade el proceso periódico para cerrar la ventana y liberar reservas. Las consultas no liquidan operaciones ni modifican saldos.
- Las operaciones usan claves de idempotencia por actor/torneo; un reintento recupera el resultado sin repetir cobros ni fichajes. Cambiar el contenido con la misma clave se rechaza. Las relaciones compuestas y el propietario activo único mantienen el aislamiento entre torneos.

Verificación: pruebas SQL con el rol service_role, reversión tras fallo inyectado después del débito/crédito/libro, concurrencia real para un libre, dos compras por encima del saldo conjunto, dos reservas, reintentos simultáneos y vencimiento durante la espera de un bloqueo. También pasaron las pruebas HTTP del flujo, TypeScript y ESLint de los archivos modificados. En el navegador se comprobó una oferta aceptada de 15 millones (Norte 145 millones, Sur 275 millones), seguida de un libre por 12 millones (Norte 133 millones, dos compras). El catálogo y los demás torneos no recibieron esas modificaciones.

Falta integrar votación previa de iconos, liberaciones con sus reglas económicas y calendario real de invierno. La pantalla habitual del juego todavía utiliza las rutas antiguas; esta etapa permanece habilitada únicamente en el entorno local.

## Cuarta etapa: contraofertas y cierre automático

La migración `20261005000400_game_market_counter.sql` se aplicó en local tras guardar un respaldo. La negociación mantiene los clubes comprador y vendedor originales: cambia el precio propuesto y el club que debe responder. El historial conserva la oferta original y todas las propuestas posteriores; no admite UPDATE/DELETE y un reintento no añade otra revisión.

El importe reservado corresponde al último precio comprometido por el comprador. Si el vendedor pide más, no aumenta unilateralmente la reserva. Cuando el comprador acepta o propone otro importe, se comprueba su saldo disponible y se ajusta la reserva dentro de la misma transacción. Si no alcanza el dinero, toda la operación revierte: quedan la oferta y su reserva anteriores. Aceptar mueve el jugador y cobra el precio acordado conservando el comprador y vendedor originales. Las cancelaciones y expiraciones liberan el importe realmente reservado, no una propuesta todavía sin aceptar.

`public.game_expire_markets` es una operación exclusiva del servidor. Cierra ventanas vencidas, expira sus ofertas pendientes, libera dinero/cupos y registra una sola operación histórica. Bloquea primero cada torneo; si otro comando lo ocupa, lo omite con `SKIP LOCKED` y vuelve a intentarlo en el siguiente ciclo. Dos procesos concurrentes no duplican el cierre. No modifica ventanas futuras ni se ejecuta como efecto secundario de una consulta.

El proceso local funciona cada 15 segundos; la pantalla consulta el estado cada 10 segundos, sin solapar actualizaciones ni conservar respuestas de una sesión anterior. Son dos procesos de desarrollo que deben permanecer activos:

```powershell
# Terminal de la aplicación
node node_modules/next/dist/bin/next dev --hostname 127.0.0.1 --port 3100
# Otra terminal para el cierre periódico
node scripts/run-game-worker-local.mjs
# Comprobación de un solo ciclo
node scripts/run-game-worker-local.mjs --once
```

También está disponible `npm run game:local:worker`. El ejecutor exige `.env.development.local` con modo local, URL exacta `http://127.0.0.1:54321` y clave de servicio local; no imprime credenciales. Se detiene con Ctrl+C. Si se detiene, la base sigue rechazando compras vencidas, pero la liberación general espera a que se reinicie o el administrador cierre el mercado. Todavía falta configurar la ejecución permanente para el despliegue futuro.

Verificación: SQL con service_role para respuestas alternadas, falta de fondos, importe reservado, ambos sentidos de aceptación, idempotencia, historial inmutable y conciliación financiera; conexiones reales para omitir un torneo bloqueado y cerrar simultáneamente sin duplicados; HTTP para la negociación y el RPC real del proceso de cierre. TypeScript y ESLint aprobados. La demostración del navegador negoció Defensa Sur de 15 a 20 millones: el comprador aceptó, Norte quedó con 140 millones, Sur con 280 millones y se consumió un solo cupo. No se tocó la base remota.

## Quinta etapa: cláusulas de rescisión

Las migraciones `20261005000500_game_clause.sql` y `20261005000600_game_clause_keys.sql` se ensayaron primero en la base desechable y se aplicaron únicamente en Supabase local, con respaldos previos. Añaden intentos inmutables de cláusula, protección del vendedor por ventana y la operación `public.game_pay_clause`, exclusiva del servidor. La pantalla `/game` permite pagar la cláusula y consultar su resultado.

Reglas de este flujo:

- El importe lo determina el contrato activo del jugador en el torneo; un precio o resultado enviado por el navegador no lo modifica. Solo se compra a otro club gestionado y durante una ventana vigente, comprobando el reloj después de bloquear el torneo.
- Hay un 25 % de rechazo, sorteado dentro de la transacción. Se registra el resultado y se devuelve en cada reintento sin volver a sortear. Si rechaza, no hay pago ni consumo de compra. Ese comprador no puede intentar otra cláusula por el mismo jugador durante esa ventana; los demás compradores conservan su oportunidad.
- Se comprueban fondos y cupos antes del sorteo. Una cláusula aceptada sustituye una oferta propia pendiente por el mismo jugador: su dinero y cupo reservados pueden utilizarse para esa compra. Al rechazar la cláusula se conserva intacta la negociación previa. Las demás reservas del comprador siguen limitando su saldo y cupos disponibles.
- Pagar, acreditar al vendedor, mover el contrato, liberar ofertas rivales, consumir el cupo y registrar el libro/historial ocurre en una sola transacción. Una excepción tardía revierte todo, incluso la liberación de reservas y el intento registrado.
- Cada ventana copia `clause_protection_limit` del torneo: 1 por defecto; 0 significa sin límite. Solo las cláusulas aceptadas consumen la protección del club vendedor. Cambiar los ajustes del torneo no altera una ventana ya abierta; la siguiente copia los nuevos valores.
- Un jugador tiene como máximo un traspaso entre clubes por ventana, por oferta o cláusula. Se comprueba al ofertar, contraofertar, aceptar y pagar cláusula, y un índice único sostiene la restricción. La contratación inicial como libre no cuenta como traspaso entre clubes.
- Si se compra un icono ya perteneciente a otro club, su nuevo contrato fija la cláusula en el 130 % de lo pagado. Este caso se probó con un contrato sintético; todavía falta implementar la subasta que adjudica inicialmente los iconos. Los precios y cláusulas del catálogo global nunca cambian.
- Las nuevas cláusulas comparten el espacio de claves de idempotencia del mercado por actor y torneo. Reutilizar la misma clave para una oferta diferente se rechaza. La corrección conserva el reintento de los intentos locales registrados antes de unificar ese espacio.

Pruebas:

```powershell
node scripts/test-db-local.mjs
node scripts/test-clause-http-local.mjs
node scripts/test-game-http-local.mjs
# Equivalente para las cláusulas HTTP: npm run test:clause:local
```

Las pruebas SQL fuerzan ambas ramas mediante semillas en conexiones directas de prueba; no hay parámetro de semilla ni de resultado en la API. Cubren rechazo sin cobro, reintentos sin otro sorteo, repetición prohibida, sustitución de reservas, cupos, protección, instantáneas, fallo inyectado tras mover dinero, cláusula de icono y conciliación financiera. Las conexiones concurrentes verifican comprador único, reintentos simultáneos, carrera cláusula/oferta, protección del vendedor y vencimiento durante la espera de un bloqueo.

Pasaron las pruebas HTTP de cláusulas (se observaron aceptación y rechazo en ejecuciones distintas), las del resto del mercado, TypeScript y ESLint. En el navegador, Norte compró Defensa Sur por su cláusula de 30 millones: quedó con 130 millones, Sur con 290 millones, sin reservas pendientes y con una sola compra. La base remota continúa intacta.

## Sexta etapa: subastas de iconos con tiempo

Las migraciones `20261005000700_game_auctions.sql` y `20261005000800_game_auction_worker.sql` se comprobaron en la base desechable y se aplicaron solo en Supabase local, con respaldo previo. Añaden subastas por torneo/ventana, pujas inmutables, cupo propio de subasta y adjudicación financiera transaccional. Se añadieron dos iconos ficticios al configurador; solo los torneos nuevos que los incluyen en su instantánea pueden usarlos.

Para el laboratorio, el administrador elige un icono libre de la instantánea y abre una subasta de 10 minutos. La operación interna permite de 1 a 1440 minutos y limita su cierre al de la ventana. La selección aleatoria de candidatos y la votación previa del flujo antiguo todavía no están integradas. Solo hay una subasta activa por ventana.

Reglas implementadas:

- El mínimo inicial procede del precio de referencia de la instantánea, con suelo de 5 millones. Cada nueva puja supera a la anterior en al menos 5 millones. No se permite superar la propia puja ganadora.
- Ser líder reserva el importe completo y un cupo de subasta; no cobra todavía. Al ser superado, se libera el dinero y el cupo del anterior líder dentro de la misma transacción. Ofertas, cláusulas, libres y subastas comparten el saldo disponible del club.
- Cada club puede ganar una subasta por ventana. El cupo se reserva al liderar y se consume al adjudicarse el icono; es independiente del límite de compras normales y se reinicia en la siguiente ventana. La adquisición de un icono por cláusula conserva las reglas de cláusulas de la etapa anterior.
- Una puja admitida durante los últimos dos minutos deja al menos dos minutos para responder, hasta el límite del cierre del mercado. Los plazos se evalúan con el reloj después de adquirir el bloqueo del torneo; los reintentos no vuelven a extender el plazo.
- El proceso periódico adjudica subastas vencidas sin esperar al fin del mercado. Si la ventana termina antes, liquida sus subastas pendientes y cierra la ventana en la misma transacción. El cierre manual del administrador también liquida todas sus subastas activas al mejor postor. Una subasta sin pujas queda cerrada sin cobrar ni adjudicar y conserva su historial.
- Adjudicar captura la reserva, cobra al ganador, acredita la cuenta del sistema, crea el libro y el contrato, consume el cupo e inserta un traspaso `icon_auction`. La cláusula del contrato nuevo es el 130 % del precio pagado. El catálogo y los demás torneos permanecen intactos.
- Los fallos tardíos revierten las pujas o la adjudicación completas. Las pujas y subastas finalizadas no admiten edición/borrado; las operaciones usan claves por actor/torneo y la liquidación tiene una clave única por subasta. Las consultas solo muestran el estado, incluyendo la espera de adjudicación tras vencer.

La API usa `auction_open` y `auction_bid` en `/api/game/tournaments/[code]/market`. La pantalla local muestra pujas, reservas, ganadores e historial. El mismo proceso local de 15 segundos liquida subastas y ventanas; debe permanecer activo junto con Next. No se configuró un servicio permanente ni un despliegue remoto.

```powershell
node scripts/setup-game-local.mjs
# Reiniciar Next para cargar los iconos ficticios del configurador.
node scripts/test-db-local.mjs
node scripts/test-auction-http-local.mjs
# Equivalente HTTP: npm run test:auction:local
```

Verificación: pruebas SQL para reservas, incrementos, fondos compartidos, cupos independientes, extensión con límite, subasta sin pujas, liquidación periódica y cierre manual, reversión tras fallos de escritura y conciliación del libro. Las conexiones simultáneas comprueban dos pujas competidoras, reintentos de una puja, dos liquidadores, puja contra cierre, vencimiento durante un bloqueo y puja contra oferta por encima del saldo conjunto. Pasaron HTTP, los flujos anteriores de mercado/cláusulas, TypeScript y ESLint.

En el navegador, Norte pujó 30 millones y Sur lo superó con 35: Norte recuperó su reserva sin pagar; el cierre del mercado adjudicó el icono a Sur, que quedó con 225 millones y cláusula de 45,5 millones. La base remota sigue intacta.

## Primera etapa implementada

La descripción de esta primera etapa se conserva como referencia; el estado actual incluye además las etapas de flujo conectado y mercado que se describen en este documento.

La migración `20261005000100_game_foundation.sql` añade el esquema privado `game`, sin reemplazar ni rellenar las tablas de juego actuales. Se aplicó exclusivamente al contenedor local `supabase_db_mercatto`, base `postgres`, tras guardar un respaldo completo en `.local-db/` (ignorado por Git).

Incluye clubes por torneo con instantáneas del catálogo, jugadores por torneo, contratos con historial y un único propietario vigente, cuentas por club con reservas, cuenta de contrapartida, libro de apertura equilibrado, operaciones con claves de idempotencia, temporadas y asignaciones con historial. Las claves compuestas impiden relaciones entre torneos diferentes. Las operaciones financieras y el libro no admiten modificación ni borrado mediante UPDATE/DELETE.

Las funciones internas `game.initialize`, `game.assign_club` y `game.advance_season` bloquean el torneo durante sus transacciones y permiten reintentos. Las funciones no son SECURITY DEFINER; su acceso se limita al backend de confianza. Todas las nuevas tablas tienen RLS y el esquema no se expone en PostgREST ni permite acceso anon/authenticated. El avance de temporada es un componente interno; el futuro backend debe validar previamente la finalización deportiva y la autoridad del administrador.

La inicialización está destinada a partidas nuevas. Rechaza juegos con asignaciones, mercado, liga o presupuestos de miembros existentes; no reconstruye sus historiales. El presupuesto de apertura es un parámetro, con valor predeterminado de 200 millones para el componente interno. La integración deberá pasar el valor calculado por las reglas del juego, antes de habilitarlo a usuarios.

## Ejecutar localmente

Requisitos: Node y Docker, con el contenedor `supabase_db_mercatto` iniciado.

```powershell
node scripts/db-local.mjs status
node scripts/db-local.mjs backup
node scripts/db-local.mjs migrate
node scripts/test-db-local.mjs
```

También hay scripts equivalentes en package.json: `db:local:status`, `db:local:backup`, `db:local:migrate` y `test:db:local`. No requieren Supabase CLI.

El ejecutor no acepta URL, proyecto remoto, nombre de contenedor ni base de datos arbitraria. Usa el socket PostgreSQL dentro del contenedor fijo y no lee archivos .env. Registra cada migración dentro de su misma transacción y detecta cambios en las migraciones nuevas ya aplicadas. Si una migración aplicada necesita corrección, crear otra posterior. El esquema consolidado previo se conserva tal como estaba.

Las pruebas construyen `mercatto_foundation_test` dentro del mismo PostgreSQL local, aplicando las migraciones desde cero, sin importar datos personales ni el catálogo actual. Los escenarios usan datos sintéticos. Los casos SQL se revierten al terminar; la prueba concurrente limpia sus datos en esa base dedicada. **No usar esta base de prueba para datos propios:** su limpieza trunca el esquema game completo. Las pruebas no alteran la base `postgres`.

## Verificación y límite de esta etapa

Las pruebas verifican inicialización y reintentos, cambio de parámetros, asignación de club ocupado, referencias de otro torneo, propietario único, saldo/reservas válidos, apertura equilibrada y concordante con cuentas, inmutabilidad financiera, snapshot frente a cambios de catálogo, continuidad de plantilla/presupuesto e historial entre temporadas, permisos y RLS. Dos conexiones PostgreSQL reales compiten por un club y exactamente una obtiene la asignación.

El movimiento de contrato del test de la primera etapa valida la estructura de datos. La tercera etapa añade las operaciones autorizadas de ofertas y contratación de libres, sus cupos, reservas y movimientos financieros transaccionales. Los resultados deportivos y las reservas de subastas todavía no están implementados.

Los endpoints y pantallas habituales siguen utilizando las tablas anteriores. La pantalla local `/game` conecta el primer flujo con el nuevo modelo sin escrituras dobles a asignaciones/presupuestos anteriores. Falta el corte del juego completo; no se habilita producción ni se eliminan todavía los permisos de las tablas antiguas.

El catálogo local existente contiene **75 jugadores con pertenencia a más de un equipo base**, detectados mediante agrupación de `public.team_players.player_id`. La inicialización completa rechaza ese estado. David indicó que recreará esos jugadores; no se dedica esta etapa a reconstruirlos. El flujo local utiliza un catálogo ficticio acotado para continuar el desarrollo de lógica sin depender de esas relaciones.

## Trabajo externo restante

El flujo completo para partidas nuevas está implementado y probado en local. Quedan la incorporación del catálogo que David recreará, la decisión explícita de importar o archivar los torneos antiguos y el ensayo/corte remoto autorizado. No se ha importado un historial perdido ni se han desplegado estos cambios.
