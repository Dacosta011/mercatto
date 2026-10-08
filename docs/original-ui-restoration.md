# Restauración de la interfaz original

Se retiró el montaje de LocalDashboard/LocalSquad del layout. El layout, FormationPitch y BottomNav vuelven a su versión original; se conservan los componentes, estilos y estructura de las páginas originales. Los archivos de la interfaz sustitutiva quedaron respaldados en .local-db/replaced-ui.

La conexión local usa legacy-game-fetch y /api/game-compat para traducir los contratos originales a las operaciones transaccionales game. La ruleta conserva SlotStrip y anima el resultado asignado por el servidor. Se añadieron actualizaciones periódicas para lobby, calendario y subastas. La base remota no se modificó.

Verificación: TypeScript sin errores; test-original-ui-http-local y test-restored-ui-local aprobados. Comprobación visual de lobby, equipo y calendario con datos locales.

La restauración visual no equivale a tener conectadas todas las acciones antiguas: siguen pendientes aplazar/reactivar partidos, slots/pool, imágenes/verificación social y notificaciones. Los resets destructivos no se traducen a borrado del patrimonio. Los endpoints sin adaptación responden con error explícito. No afirmar que todos los controles están listos hasta cubrir estos flujos y mostrar los errores de servidor en todos los manejadores antiguos.
