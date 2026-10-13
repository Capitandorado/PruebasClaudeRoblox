# Qué está probado (y qué no)

## Cómo se prueba

No hay acceso a Roblox Studio en el entorno donde se desarrolló el juego, así que las pruebas
corren en **Lune** con un entorno simulado de Roblox (`tests/mock`):

- Cada `Instance` se valida contra la **base de datos oficial de la API de Roblox**
  (generada del API Dump): usar una propiedad, método o evento que no existe, o asignar un
  tipo incorrecto, produce el mismo error que en el motor.
- Servidor y cada cliente tienen su **propia máquina virtual** (módulos y globales
  separados); los `RemoteEvent`/`RemoteFunction` copian los argumentos como la red real
  (las tablas mixtas pierden datos, las funciones se convierten en nil).
- El tiempo es simulado (`task.wait`, `Heartbeat`, `os.time`), lo que permite probar horas de
  juego en segundos.
- El DataStore simulado serializa en JSON, rechaza valores no serializables, y permite
  **inyectar fallos**, compartir datos entre varios servidores y simular la caída de uno.

Se ejecutan los **scripts reales** del juego: el servidor arranca, los jugadores entran, la
interfaz se construye y las pruebas pulsan sus botones.

## Cobertura (113 pruebas)

| Área | Ejemplos |
| --- | --- |
| Lógica | Probabilidades normalizadas, prueba estadística de 200 000 tiradas, efectos, mutaciones, fusión, rebirth, misiones, saneado de datos corruptos |
| Servidor | Arranque, abrir/colocar/producir, compras, rechazo de 13 tipos de peticiones malformadas, límite de frecuencia |
| Cliente | HUD, botón de abrir con animación, inventario → colocar, las 9 ventanas, tienda, modo automático |
| Guardado | Reentrar, bloqueo entre servidores, caída de un servidor, fallos transitorios y persistentes, perfil inválido, cierre del servidor (también con un guardado en cola detrás de un autoguardado), Studio sin API, almacenes separados para Studio |
| Efectos y eventos | Etiquetas y enlaces, vista previa, eventos que cambian la producción, catálogo de temporada, máquinas animadas |
| Seguridad y multijugador | Fuzzing de todas las acciones, peticiones en paralelo, cliente manipulado, 8 jugadores independientes, servidor lleno, visitas, clasificación global |
| Pulido | Escala y menú en pantalla de móvil, consejos de inicio, ventanas que no se reconstruyen sin cambios, inventario que solo rehace las tarjetas que cambian, rescate al caer al vacío |
| Volver a jugar | Ganancias sin conexión (mínimo, tope, Night Shift, cajas de la impresora, sin pagar dos veces), ventana de bienvenida, racha diaria (seguida, perdida, ciclo de 7 días), *Daily Crates*, aviso al entrar |
| Analíticas | Embudo de primera sesión en orden y una sola vez, jugadores que vuelven fuera del embudo, eventos de economía agrupados por minuto, rebirth y racha; el emulador valida los argumentos de AnalyticsService |

Prueba de carga (`tools/soak.luau`, 30 minutos simulados, 4 jugadores con la interfaz real):
0 errores, 375 cajas abiertas, un jugador sale y vuelve a entrar, y el cierre guarda a todos.
Las instancias crecen con el progreso (más máquinas, pedestales y objetos distintos en el
inventario); la cuadrícula del inventario es lo único que crece en la interfaz y está acotada
por la capacidad del almacén.

Además: comprobación de tipos con luau-lsp y las definiciones oficiales de Roblox, lint con
Selene, y el `.rbxl` compilado se abre y cada script se compila con el compilador de Luau.

Una revisión específica buscó fallos que solo aparecerían en el motor real (física,
replicación, interfaz de Roblox, DataStore real) y se corrigieron los encontrados: IDs de
usuario de más de 32 bits, toques en pedestales traseros, colores de anillos que podían quedarse
encendidos, la lista de jugadores tapando la interfaz, carteles de tamaño fijo, datos de Studio
mezclados con los reales, la tecla Esc, el rescate al caer y una carrera al cerrar el servidor.

## Lo que NO se ha podido comprobar

- **Ejecutar el juego dentro de Roblox Studio o de un servidor real.** El emulador reproduce la
  API, pero no el motor: física, colisiones, cámara, renderizado, iluminación, partículas,
  rendimiento real en móviles, latencia de red y el aspecto visual final.
- **El DataStore real de Roblox** (cuotas, latencias y errores reales) y las clasificaciones
  globales en producción.
- **Que los sonidos subidos suenen bien en el juego** (se generaron y validaron como WAV).
- En el emulador todos los clientes comparten un único DataModel (en Roblox cada cliente tiene
  su copia), así que el estado visual por cliente —por ejemplo, prompts desactivados para los
  visitantes— se comprueba a través de la lógica de cada controlador, no del objeto compartido.

Por eso la primera prueba recomendada es abrir `build/VoidFactory.rbxl` en Studio y seguir
[PUBLISHING.md](PUBLISHING.md).
