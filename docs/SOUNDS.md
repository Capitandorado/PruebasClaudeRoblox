# Sonidos

El juego funciona desde el primer momento con dos sonidos que vienen **dentro del cliente de
Roblox** (verificados en el manifiesto oficial de archivos del cliente):
`rbxasset://sounds/volume_slider.ogg` y `rbxasset://sounds/impact_explosion_03.mp3`, con tono
distinto según el efecto. No se usa ningún ID de audio inventado.

Para tener sonidos propios, en `assets/sounds/` hay 15 efectos **originales** generados por
`tools/gen_sounds.py` (síntesis por código, sin muestras de terceros):

| Archivo | Cuándo suena |
| --- | --- |
| UIClick, Error | Botones y errores |
| BoxOpen | La caja empieza a abrirse |
| RevealCommon, RevealRare, RevealLegendary, RevealDivine, RevealVoid | Revelación según la rareza |
| Purchase, Upgrade, Unlock, Fusion, Rebirth, Place, QuestComplete | Compras, mejoras, desbloqueos, fusión, rebirth, colocar, misiones |

## Cómo usarlos

1. En Roblox Studio abre **Asset Manager** (o el Creator Dashboard → *Development Items → Audio*)
   y sube los `.wav` de `assets/sounds/` (Roblox puede pedir verificación o tener un límite mensual
   de subidas según tu cuenta).
2. Copia el ID de cada audio subido.
3. Pégalo en `src/shared/Config/Sounds.luau`, en el campo `id` del efecto con el mismo nombre:

```lua
RevealLegendary = { id = "rbxassetid://123456789", fallback = BOOM, volume = 0.35, pitch = 1.7 },
```

Si `id` está vacío se usa el sonido integrado (`fallback`). Los jugadores pueden desactivar los
efectos de sonido en ⚙️ Settings.

Para regenerar o modificar los sonidos: `python3 tools/gen_sounds.py`.
