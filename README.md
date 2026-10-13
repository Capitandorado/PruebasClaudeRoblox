# VOID FACTORY

Simulador de fábrica para Roblox: abre cajas misteriosas, consigue artefactos de 10 rarezas,
colócalos en tu plataforma flotante y construye una fábrica cada vez más extraña.

## Abrir el juego en Roblox Studio (sin instalar nada)

1. Descarga `build/VoidFactory.rbxl` de este repositorio.
2. Ábrelo con doble clic (o *File → Open from File* en Roblox Studio).
3. Pulsa **Play** (F5). El juego construye el mundo al arrancar.

> En Studio, el panel 🛠️ *Debug* (botón del menú izquierdo) permite dar Energy, avanzar el
> tiempo, etc. para probar la progresión rápidamente.

## Desarrollo (Rojo)

El código vive en `src/` y se sincroniza con Studio mediante [Rojo](https://rojo.space):

```
rojo serve default.project.json      # sincroniza en vivo con el plugin de Rojo
rojo build -o build/VoidFactory.rbxl # genera el archivo del lugar
./tools/check.sh                     # formato, lint, tipos, build y pruebas
```

| Carpeta | Contenido |
| --- | --- |
| `src/shared/Config` | Catálogos y balance: artefactos, rarezas, cajas, máquinas, mejoras, economía |
| `src/shared/Logic` | Reglas del juego puras (tiradas, producción, acciones). Compartidas por servidor y cliente |
| `src/shared/Visuals` | Modelos procedurales de artefactos y máquinas |
| `src/server/Services` | Servicios del servidor: red, sesiones, parcelas, simulación, administración |
| `src/client` | Interfaz, animaciones y controladores del cliente |
| `tests/` | Pruebas en Lune con un entorno simulado de Roblox (`tests/mock`) |
