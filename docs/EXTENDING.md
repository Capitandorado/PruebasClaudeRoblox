# Ampliar el juego

Todo el contenido está en catálogos centralizados (`src/shared/Config`). La lógica, la
interfaz, las probabilidades y las pruebas los leen automáticamente.

## Añadir un artefacto

Añade una entrada al final de `Config/Artifacts.luau`:

```lua
{
	id = "plasma_lantern",          -- único y permanente (se guarda en los datos de los jugadores)
	name = "Plasma Lantern",
	rarity = "Epic",                 -- cualquier id de Config/Rarities
	weight = 40,                     -- peso dentro de su rareza
	eps = 50,                        -- Energy por segundo en un pedestal
	value = 650,                     -- Energy al venderlo
	effects = { { type = "global_mult", amount = 0.05 } },
	shape = "Reactor",               -- forma de Visuals/ArtifactModels (o crea una nueva)
	primary = Color3.fromRGB(255, 120, 40),
	secondary = Color3.fromRGB(255, 230, 120),
	lore = "Texto de la colección.",
	catalog = "core",                -- o el catálogo de un evento
},
```

- **Forma nueva:** añade `shapes.MiForma = function(model, artifact) ... end` en
  `Visuals/ArtifactModels.luau` usando los ayudantes de `Util/Build.luau`.
- **Efectos disponibles:** `global_mult`, `adjacent_mult`, `luck`, `duplicate`, `speed`,
  `entropy` (`min`, `max`), `singularity`, `surge` (`period`, `duration`, `amount`).
  Un efecto nuevo se implementa en `Logic/Production.luau` y se describe en `Logic/Effects.luau`.
- Ejecuta `./tools/check.sh`: las pruebas comprueban que las probabilidades siguen sumando 1
  y que el catálogo es coherente.
- **Nunca cambies ni borres el `id` de un artefacto publicado.** Si eliminas uno, los datos de
  los jugadores lo conservan aparte (`orphaned`) y vuelve si lo restauras.

## Añadir una máquina

1. Entrada en `Config/Machines.luau` (tipo `fabricator`, `printer`, `booster` o `fusion`,
   coste, `pad` libre y estadísticas por nivel).
2. Modelo en `Visuals/MachineModels.luau` (`builders.mi_maquina`).
3. Si usas un `pad` nuevo (más de 6), ajusta `Plots.padLocal` para su posición.

## Cajas, rarezas y mutaciones

- Tablas de botín: `Config/Boxes.luau` (pesos por rareza; se normalizan solos).
- Rarezas: `Config/Rarities.luau` (color, cómo afecta la suerte, animación de revelado).
- Mutaciones: `Config/Mutations.luau` (probabilidad, multiplicador, color).

## Eventos

`Config/Events.luau`:
- **Rotativos:** se añaden a `Events.Rotating` con modificadores (`luckMult`,
  `productionMult`, `speedBonus`, `mutationMult`).
- **De temporada:** `Events.Scheduled` con `startsAt`/`endsAt` (UTC) y, opcionalmente,
  `catalog = "nombre"`. Los artefactos con ese `catalog` solo caen mientras dure el evento.

## Misiones

`Config/Quests.luau`. Usa solo estadísticas que cuesten tiempo, objetos o Energy (las pruebas
lo exigen para evitar misiones que se completen repitiendo una acción gratis).

## Balance

Tras cualquier cambio de números: `lune run tools/simulate.luau 240 active 5` y compara con
[ECONOMY.md](ECONOMY.md).

## Cambios en el formato de datos

`Logic/Profile.luau`: sube `Profile.Version`, añade la migración en `migrate()` y los valores
por defecto en `Profile.new()`/`reconcile()`. `reconcile` acepta cualquier dato antiguo o
corrupto y siempre devuelve un perfil válido.
