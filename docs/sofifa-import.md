# Catálogo SoFIFA: sincronización local

## Estado actual

Los assets se alojan en el bucket público **local** `sofifa-assets`: 16 escudos y 437 imágenes de jugadores (176 fotos y 261 siluetas que ya estaban en los archivos guardados). Se verificaron los 453 enlaces públicos y sus bytes. Los escudos de las partidas existentes también se actualizaron; sus plantillas y economía se conservan. Reimportar el catálogo conserva los enlaces locales de Storage.

Para reconstruirlos: `scripts/prepare-sofifa-assets.py CARPETA --output .local-db/sofifa/assets.json`, seguido de `node scripts/upload-sofifa-assets-local.mjs .local-db/sofifa/assets.json`. El script usa únicamente la configuración de desarrollo y el endpoint fijo de Supabase local. Las rutas de objetos incluyen identidad y hash del archivo: repetir la subida no crea objetos nuevos para el mismo contenido. Informe: `.local-db/sofifa/assets-uploaded.json`. Los HTML pueden guardar siluetas cuando una foto aún no se ha cargado; no se presentan como retratos reales.

Importación local completada el 8 de octubre de 2026: 16 equipos, 437 jugadores y 437 relaciones de plantilla, revisión 270004, desde el lote completo de HTML entregado por el usuario. Comparación de campos e importación repetida verificadas. La base remota no se modificó.

## Antecedentes anteriores a la importación

Se reiniciaron, con autorización explícita, el catálogo y los torneos/datos de juego dependientes de la base local. Se comprobó `players=0`, `teams=0`, `team_players=0`, `tournaments=0`. Respaldo completo anterior: `.local-db/before-catalog-reset-1791257368406.sql`.

**La descarga automática todavía está bloqueada:** SoFIFA respondió HTTP 403 al descargar `https://sofifa.com/team/1/?hl=en-US`. La visita anterior desde el navegador también quedó en la verificación de Cloudflare. Posteriormente el usuario aportó el HTML real de Chelsea: se validó la revisión 270003 (1 de octubre de 2026), con 29 jugadores activos y 16 cedidos fuera de la plantilla. El catálogo local permanece vacío porque falta el lote completo; no se rellenó con resultados de buscadores, datos antiguos ni datos ficticios. Los tests sintéticos usan exclusivamente `mercatto_foundation_test`.

La muestra real permitió corregir tres casos: tablas Squad y On loan dentro de un mismo artículo, revisiones en rutas sin slug y escudo extraído de los metadatos del club en lugar del primer escudo de la página. Las 29 identidades y fotos se extraen de la plantilla activa. Falta acceso permitido a las otras páginas para descargar y validar el lote completo. No se implementan técnicas de evasión, resolución de retos ni reutilización de cookies personales.

## Uso

Requisitos: Docker/Supabase local activos, Node.js y Python 3. El extractor usa únicamente la biblioteca estándar de Python. El lanzador detecta el Python incluido en este entorno; fuera de él usa `py` en Windows o `python3`. Se puede fijar la ruta con `MERCATTO_PYTHON`.

```powershell
# Descargar siempre de nuevo y simular la transacción, sin conservar cambios.
node scripts/sync-sofifa-local.mjs

# Descargar siempre de nuevo y aplicar el lote completo localmente.
node scripts/sync-sofifa-local.mjs --apply

# Revisar un JSON previamente descargado (máximo 24 horas de antigüedad).
node scripts/import-sofifa-local.mjs .local-db/sofifa/latest-TIMESTAMP.json

# Validar un HTML guardado y exportar una vista previa; no escribe en DB.
python scripts/scrape_sofifa.py --saved-html "Chelsea - FC27 _ SoFIFA.html" --output .local-db/sofifa/chelsea-validated.json
```

La opción de importar un JSON no vuelve a consultar SoFIFA; es una herramienta de revisión. Para cumplir «siempre la última actualización», usar `sync-sofifa-local.mjs`, que nunca reutiliza una captura anterior si falla la descarga nueva.

La vista previa de HTML usa `source=sofifa-saved-html` y el importador no la acepta como lote completo. `latestListedInSavedPage` indica la última edición enumerada en ese archivo, no una comprobación en vivo de la versión más reciente.

Al aplicar correctamente, se actualizan solo las variables de selección de clubes de `.env.development.local` para usar los 16 UUIDs importados. Reiniciar el servidor local si está en marcha. Tras el wipe, los enlaces personales de los torneos antiguos ya no son válidos. Hasta tener catálogo no se puede crear un torneo jugable. No ejecutar `setup-game-local.mjs` para rellenar este catálogo: ese comando carga los fixtures ficticios anteriores.

## Equipos

Lista en `scripts/sofifa-teams.json`: Arsenal, Chelsea, Liverpool, Manchester City, Manchester United, Tottenham, Real Madrid, Barcelona, Atlético, Juventus, Inter, Milan, Napoli, Bayern, Dortmund y PSG.

Se corrigieron los IDs heredados de Inter y Milan a **44** y **47**, respectivamente, contrastados con sus páginas oficiales: [Inter](https://sofifa.com/team/44/inter/), [AC Milan](https://sofifa.com/team/47/ac-milan/). Los IDs no se deducen de nombres ni de la media.

## Reglas de sincronización

### Importación de archivos guardados (8 de octubre de 2026)

Se importaron los 16 HTML entregados por el usuario: 437 jugadores, revisión 270004 y 437 relaciones de plantilla. Se compararon todos los campos importados con el lote y se repitió la importación: registros, UUIDs y auditoría permanecieron iguales. Informe local: `.local-db/sofifa/verification.json`. Respaldo previo: `.local-db/backup-1791479845797.sql`.

Para preparar otro lote completo, usar `scripts/prepare-sofifa-saved.py CARPETA --output ARCHIVO.json` y luego `node scripts/import-sofifa-local.mjs ARCHIVO.json --allow-saved-html --apply`. Este modo requiere autorización explícita para usar archivos guardados; conserva `source=sofifa-saved-html` y `validatedAt` en el lote. Comprueba la última revisión indicada en cada archivo, pero no demuestra cuál está disponible en la web actualmente. El flujo automático sigue comprobando la revisión en vivo. Los archivos parciales siguen rechazándose.

### Descarga con navegador visible

```powershell
npm run catalog:sofifa:browser
```

Abre Chrome en una sesión independiente, sin usar el perfil personal. Si SoFIFA presenta una verificación, completarla manualmente en esa ventana y dejarla abierta. El script espera hasta diez minutos por página y continúa cuando aparecen los selectores de edición y la plantilla. No resuelve verificaciones automáticamente. Puede elegirse Edge con `MERCATTO_BROWSER_CHANNEL=msedge`.

Requiere Playwright (instalado en el proyecto o disponible en el runtime de Codex), Chrome/Edge y Python estándar. `MERCATTO_PYTHON` permite indicar el ejecutable de Python. Las capturas, el estado y el lote validado se guardan en `.local-db/sofifa/browser-<timestamp>/`, excluido de Git. Para una prueba sin guardar en DB, ejecutar `node scripts/sync-sofifa-browser-local.mjs` sin `--apply`.

El navegador utiliza el mismo parser estricto y el mismo importador local que la descarga HTTP. Comprueba la última revisión al empezar y terminar; solo importa después de validar los 16 clubes. Si la verificación no termina, se cierra el navegador y la DB queda sin cambios. Tras una importación correcta se actualiza la selección local de clubes; reiniciar el servidor de desarrollo para que lea esa configuración.

- El extractor empieza sin una versión fija, descubre las revisiones que ofrece SoFIFA y elige la más reciente. Descarga todos los equipos con esa misma revisión y vuelve a comprobarla al terminar. Si no puede demostrar la revisión o cambia durante el proceso, aborta.
- No mezcla ediciones ni importa parcialmente: deben llegar los 16 equipos, con IDs únicos, 18–80 jugadores por plantilla, media válida, nombre y posición. Una fila de jugador incompleta provoca error. Se excluye la sección de jugadores cedidos fuera del club; los cedidos que pertenecen a la plantilla activa permanecen en ella.
- `players.sofifa_id` y `teams.sofifa_id` tienen restricciones únicas. Un cambio de nombre, media o posición actualiza el mismo UUID. Dos personas distintas con el mismo nombre se distinguen por su ID.
- La relación base tiene un índice único por jugador: no puede aparecer simultáneamente en dos clubes del catálogo. Un traspaso mueve la relación; una salida elimina esa relación, conservando la identidad del jugador para referencias históricas. No se borra automáticamente su fila.
- Las importaciones se serializan mediante bloqueo, aplican todo en una transacción y rechazan revisiones anteriores a la importada. Un error revierte el lote entero. Repetir el mismo lote conserva UUIDs, cantidades e importación registrada.
- Precios y cláusulas iniciales se calculan de forma determinista a partir de la media (sin azar). Son valores del juego, no los valores de mercado publicados por SoFIFA. Las imágenes se guardan como URLs válidas de SoFIFA, sin subir archivos a Storage ni tocar servicios remotos.
- Se actualiza exclusivamente el catálogo público. Los nombres, medias, precios, contratos y presupuestos congelados de las partidas existentes se conservan.
- El importador rechaza un catálogo heredado sin IDs externos para evitar emparejamientos inciertos por nombre. El wipe autorizado resuelve ese caso inicial. Los iconos manuales sin ID de SoFIFA pueden mantenerse aparte.
- Las herramientas de DB usan un socket dentro del contenedor local fijado en código. No leen una URL remota ni aceptan un destino de producción.

## Pruebas

```powershell
python scripts/test-sofifa-parser.py
node scripts/test-sofifa-import-local.mjs
```

El parser se prueba con HTML sintético: identidades, revisión más reciente sin confundir IDs de jugadores, página truncada/bloqueada, medias ausentes, club/revisión incorrectos y cedidos excluidos.

La integración usa una base local dedicada inicialmente vacía: preview sin cambios, importación repetida, UUID estable al cambiar media/nombre/posición, homónimos, traspaso, salida, bloqueo de ID duplicado y doble propietario, lote incompleto, revisión anterior y rollback ante un error SQL. También crea una partida y comprueba que su instantánea no cambie al actualizar el catálogo.

El script anterior `sofifa_to_sql.py` queda como código histórico: no usarlo para este flujo. Su clave `(name, ovr, position)` no sirve para sincronizar identidades y ya no corresponde a la restricción de la base nueva.

## Reset deliberado

No forma parte de una sincronización habitual:

```powershell
node scripts/reset-catalog-local.mjs --confirm-reset-local-games
```

Hace un respaldo completo y elimina el catálogo, sus torneos/datos dependientes y el registro de importaciones local. **No usar para actualizar plantillas:** la sincronización habitual conserva datos e identidades.
