# Bugfix y recuperación de iconos — 8 octubre 2026

Rama: `codex/bugfix-regression-icons`. Validación y cambios de datos exclusivamente locales. Sin push ni cambios en producción.

## Correcciones

- Cláusulas: conservar `rejected` devuelto por la transacción; el adaptador ya no transforma un rechazo en éxito.
- Espectadores: entrada sin token previo, reintentos idempotentes, perfil social y navegación de invitado. La base bloquea asignarles equipos, también en temporadas futuras; no cuentan como participantes del draft.
- Feed: publicaciones con imagen, incluso sin texto, con validación de formato/tamaño, pertenencia de respuestas e idempotencia.
- Notificaciones: eventos de ofertas, fichajes y subastas; lectura y suscripciones aisladas por miembro. Entrega push con reintentos y eliminación de suscripciones caducadas.
- Nuevos torneos: incluir automáticamente los iconos del catálogo en el conjunto disponible para subastas, salvo una lista explícita de jugadores libres en la configuración.

Se mantiene el diseño existente.

## Recuperación

Se recuperaron los 52 iconos del respaldo anterior al reinicio, conservando UUID, nombre, media, posición, precio, cláusula, salario y nacionalidad. Sus 52 imágenes se copiaron y verificaron en Storage local. Resultado: 437 jugadores regulares + 52 iconos = 489 identidades únicas. Se repitió la restauración: sin duplicados y conservando las 52 URL de Storage local.

Los scripts `restore-icons-local.mjs` y `restore-icon-assets-local.mjs` restringen escrituras a la base y Storage locales. Los respaldos, imágenes y manifiestos están en `.local-db`, ignorado por Git. No se modifican automáticamente las instantáneas de torneos existentes: los iconos están disponibles al crear un torneo nuevo.

## Verificación realizada

- `node scripts/test-bugfix-local.mjs`: siete grupos aprobados: catálogo, subastas de dos participantes (incluida extensión por puja tardía, adjudicación y reintentos), rechazo de cláusula en adaptador, notificaciones, suscripciones push, invitados y publicaciones con imágenes.
- `node scripts/test-db-local.mjs`: regresión SQL y concurrencia aprobadas, incluyendo mercado, cláusulas, subastas, competición y aplazamientos.
- `node scripts/build-game-local.mjs`: compilación Next.js y TypeScript aprobadas.
- Navegador local: entrada de invitado, navegación restringida, publicación con imagen y persistencia después de recargar. Todas las imágenes presentes cargaron correctamente. Evidencia: `.local-db/bugfix/local-feed-image.png`.

La prueba de rechazo del adaptador usa un resultado idempotente sembrado para reproducir el fallo de forma determinista; no depende del azar de la cláusula. Los restantes comportamientos transaccionales se cubren en la regresión SQL.

## Límites y siguiente despliegue

La entrega push a un teléfono real queda pendiente; está desactivada deliberadamente en el modo local. En producción la cola se procesa después de solicitudes RPC y al ejecutar el cron HTTP. Los eventos generados por el cron de PostgreSQL quedan pendientes hasta esa ejecución; no se garantiza entrega inmediata sin tráfico. Se requiere una prueba de dispositivo con las claves VAPID de producción.

Antes de desplegar: respaldar producción, aplicar las migraciones aditivas `20261008000100` y `20261008000200`, restaurar los 52 iconos con sus mismos UUID y publicar sus imágenes en Storage remoto con URL remotas. Preparar ese paso por separado: los scripts de recuperación actuales solo escriben localmente. No reiniciar ni borrar torneos. Después desplegar el código y verificar invitado, imagen, subastas y push en un torneo de prueba nuevo.
