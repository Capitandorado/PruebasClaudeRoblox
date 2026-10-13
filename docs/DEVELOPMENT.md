# Desarrollo

## Herramientas

| Herramienta | Uso | Versión probada |
| --- | --- | --- |
| [Rojo](https://github.com/rojo-rbx/rojo) | Sincronizar `src/` con Studio y compilar el `.rbxl` | 7.7.1 |
| [Lune](https://github.com/lune-org/lune) | Ejecutar las pruebas y herramientas | 0.10.4 |
| [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) | Comprobación de tipos con las definiciones de Roblox | 1.70.1 |
| [StyLua](https://github.com/JohnnyMorganz/StyLua) | Formato | 2.1.0 |
| [Selene](https://github.com/Kampfkarren/selene) | Lint | 0.29.0 |

Todas se descargan desde sus *releases* de GitHub (un único ejecutable cada una). Para la
comprobación de tipos hace falta `globalTypes.d.luau` del repositorio de luau-lsp
(`scripts/globalTypes.d.luau`); indica su ruta con `ROBLOX_DEFS=/ruta/globalTypes.d.luau`.

## Flujo de trabajo

```
rojo serve default.project.json   # + plugin de Rojo en Studio para sincronizar en vivo
./tools/check.sh                  # formato, lint, tipos, build, verificación del .rbxl y pruebas
lune run tests/run.luau inventory # solo las pruebas cuyo nombre contiene "inventory"
```

## Arquitectura en una frase

El servidor es la única fuente de verdad: el cliente pide acciones a través de una única
`RemoteFunction` (`Shared/Net`), el servidor las valida y aplica la lógica pura
(`Shared/Logic`) sobre el perfil, y replica el resultado; el cliente usa la misma lógica solo
para mostrar valores derivados (producción, suerte, costes) idénticos a los del servidor.

| Servidor (`src/server/Services`) | Responsabilidad |
| --- | --- |
| Net | Remotes, validación de argumentos, límites de frecuencia, aislamiento de errores |
| Data | DataStore: carga con bloqueo de sesión, reintentos, guardado seguro, BindToClose |
| Sessions | Ciclo de vida del jugador y réplica del perfil |
| World / Plots | Iluminación, isla central, parcelas y su renderizado incremental |
| Game | Manejadores de cada acción |
| Simulation | Un único bucle de Heartbeat para la producción de todos los jugadores |
| Leaderboards | Clasificaciones del servidor y globales |
| Admin | Herramientas de depuración protegidas |

## Vistas previas de los modelos

Sin abrir Studio se pueden revisar las formas y colores de los modelos procedurales:

```
lune run tools/preview/export.luau build/preview.json   # geometría real generada por el juego
python3 tools/preview/render.py build/preview.json docs/images
lune run tools/part_audit.luau                           # piezas/luces/partículas por modelo
```

El render es una aproximación (trazado de rayos simple con numpy), no el motor de Roblox.
