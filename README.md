# PruebasClaudeRoblox — Juego de cultivo

Juego de cultivo para Roblox escrito en Luau y sincronizado con [Rojo](https://rojo.space/).

## Cómo arrancarlo

1. Instala Rojo (CLI y plugin de Studio).
2. En la carpeta del proyecto ejecuta `rojo serve`.
3. Abre un lugar vacío (o un Baseplate) en Roblox Studio, conecta el plugin de Rojo y pulsa **Play**.

El servidor genera automáticamente todo lo que falte en el mapa: suelo, cinta transportadora, 6 parcelas y el puesto de venta.

## Cómo se juega

1. **Cinta transportadora.** En el centro del mapa hay una cinta compartida que suelta una semilla cada pocos segundos. Las semillas avanzan desde el extremo verde hasta el rojo y desaparecen si nadie las compra.
2. **Rarezas.** Cada semilla tiene un tipo y una rareza: Común (70 %), Rara (20 %), Épica (8 %) o Legendaria (2 %). Encima de cada semilla aparece su nombre, su rareza (con su color) y su precio.
3. **Comprar.** Acércate a una semilla y pulsa su aviso (ProximityPrompt) **Comprar**. Si tienes dinero suficiente, la semilla desaparece de la cinta y pasa a tu inventario. Si otro jugador la compra antes, ya no está disponible.
4. **Parcelas.** Cada jugador recibe una parcela propia (hay como máximo 6) con 4 huecos de tierra. Apareces en tu parcela al entrar.
5. **Plantar.** Abre el inventario (está abajo a la izquierda; la tecla **I** lo muestra u oculta), selecciona una semilla y pulsa **Plantar**. Se planta en el hueco libre de tu parcela más cercano a ti. Tienes que estar en tu parcela.
6. **Crecer.** La planta crece en 4 fases visibles: cada fase es más grande. El tiempo total depende de la semilla; las más raras tardan más.
7. **Cosechar.** Cuando la planta está madura aparece el aviso **Cosechar**. Sólo el dueño de la parcela puede cosecharla, y al hacerlo recibe un fruto.
8. **Vender.** Ve al **Puesto de venta** y pulsa **Vender frutos**: se venden todos tus frutos. Los frutos de semillas raras valen mucho más.

Empiezas con **30 $**, suficiente para 2 semillas comunes. El dinero se muestra arriba en pantalla y en la tabla de jugadores (leaderstats, columna *Dinero*).

## Estructura del código

```
src/
├── shared/                     -> ReplicatedStorage.Shared (servidor y cliente)
│   ├── SeedConfig.luau         Semillas y rarezas (¡aquí se añaden semillas!)
│   ├── GameConfig.luau         Dinero inicial, cinta, parcelas, fases de crecimiento...
│   ├── Tags.luau               Nombres de las Tags de CollectionService
│   └── Remotes.luau            Crea y obtiene los RemoteEvents/RemoteFunctions
├── server/                     -> ServerScriptService.Server
│   ├── Main.server.luau        Arranca los servicios en orden
│   └── Services/
│       ├── MapBuilder.luau     Genera los placeholders del mapa si no existen
│       ├── PlayerDataService.luau  Dinero (leaderstats) e inventario
│       ├── ConveyorService.luau    Cinta: aparición, movimiento y compra de semillas
│       ├── PlotService.luau        Parcelas: asignar, plantar, crecer y cosechar
│       ├── SellService.luau        Puesto de venta
│       └── ModelFactory.luau       Crea modelos de semillas/plantas (placeholder o definitivo)
└── client/                     -> StarterPlayer.StarterPlayerScripts.Client
    ├── Main.client.luau        Conecta la interfaz con el servidor
    └── UI/HUD.luau             Dinero, inventario, botón Plantar y avisos
```

### Seguridad (antitrampas)

Toda la lógica de dinero, compras, crecimiento, cosecha y ventas se ejecuta en el **servidor**:

- El cliente sólo envía una petición: `PlantSeed(seedId)`. El servidor comprueba que el Id exista en `SeedConfig`, que el jugador tenga esa semilla, que tenga parcela, que esté cerca de ella y que haya un hueco libre. También limita la frecuencia de peticiones.
- Las compras, cosechas y ventas usan ProximityPrompts, que se gestionan en el servidor. Los precios y valores salen siempre de `SeedConfig`, nunca del cliente.
- El dinero sólo se modifica desde `PlayerDataService`, que nunca lo deja en negativo.

### Remotes

| Nombre             | Tipo           | Dirección          | Uso                                         |
|--------------------|----------------|--------------------|---------------------------------------------|
| `PlantSeed`        | RemoteEvent    | Cliente → Servidor | Pide plantar la semilla seleccionada        |
| `InventoryUpdated` | RemoteEvent    | Servidor → Cliente | Envía el inventario completo tras un cambio |
| `Notify`           | RemoteEvent    | Servidor → Cliente | Muestra un aviso en pantalla                |
| `GetInventory`     | RemoteFunction | Cliente → Servidor | Devuelve el inventario actual               |

## Cómo añadir o equilibrar semillas

Todas las semillas están en **`src/shared/SeedConfig.luau`**. Para añadir una, copia una entrada de la lista `seedList` y cambia sus datos:

```lua
{
	Id = "PinaTornado",            -- Identificador único, sin espacios ni tildes
	DisplayName = "Piña Tornado",  -- Nombre que ve el jugador
	Rarity = "Epic",               -- "Common", "Rare", "Epic" o "Legendary"
	Price = 135,                   -- Precio en la cinta
	GrowTime = 85,                 -- Segundos hasta madurar
	SellValue = 380,               -- Dinero por cada fruto
	Color = Color3.fromRGB(250, 210, 60), -- Color del placeholder
},
```

No hay que tocar nada más: la cinta, la interfaz, el crecimiento y la venta la usarán automáticamente.

- **Probabilidades:** cambia `Weight` en `SeedConfig.Rarities`. Los pesos se normalizan, así que no tienen por qué sumar 100. Dentro de una rareza, todas sus semillas tienen la misma probabilidad.
- **Nueva rareza:** añádela a `SeedConfig.Rarities` con `Id`, `DisplayName`, `Color`, `Weight` y `Order`.
- **Dinero inicial, velocidad de la cinta, número de huecos, fases de crecimiento...:** están en `src/shared/GameConfig.luau`. Si subes el precio de las semillas comunes, recuerda revisar `StartingMoney`.

## Cómo sustituir los placeholders por modelos definitivos

El código no depende de cómo son los objetos, sólo de sus **Tags** (CollectionService) o de las carpetas con nombre:

| Objeto            | Cómo se identifica                                                                           |
|-------------------|----------------------------------------------------------------------------------------------|
| Cinta             | Una Part con la Tag `Conveyor`. Las semillas van desde su cara +Z local hasta su cara −Z (la dirección de su LookVector). |
| Parcela           | Un Model con la Tag `Plot`, una Part hija llamada `Base` y, opcionalmente, el atributo numérico `PlotIndex` para el orden. |
| Hueco de tierra   | Una Part con la Tag `PlotSlot` dentro del Model de la parcela (atributo opcional `SlotIndex`). |
| Puesto de venta   | Una Part o un Model (con PrimaryPart) con la Tag `SellStand`.                                |
| Modelo de semilla | `ServerStorage/Assets/Seeds/<Id de la semilla>` (Model o Part).                              |
| Modelo de planta  | `ServerStorage/Assets/Plants/<Id de la semilla>` (Model con el Pivot en la base, a tamaño de planta madura). |

Si en el mapa existe algún objeto con la Tag `Conveyor`, `SellStand` o `Plot`, no se genera su placeholder. Con las parcelas, si hay al menos una con Tag se usan sólo las tuyas, hasta un máximo de `GameConfig.Plots.MaxPlots`. Si una parcela tiene en su `Base` un BillboardGui llamado `Sign` con un TextLabel llamado `Text`, ahí se mostrará el nombre del dueño.

Los objetos que crea el servidor durante la partida también llevan Tags: `ConveyorSeed` en las semillas de la cinta y `Plant` en las plantas. Las semillas están en `Workspace.ConveyorSeeds` y las plantas en `Workspace.Plants`.

## Limitaciones conocidas / siguientes pasos

- Los datos (dinero, inventario y plantas) **no se guardan** entre sesiones. Para guardarlos, añade DataStoreService en `PlayerDataService`.
- Las parcelas tienen siempre `StartingSlots` huecos. Todavía no se pueden ampliar: habría que añadir Parts con la Tag `PlotSlot` y registrarlas en `PlotService`.
