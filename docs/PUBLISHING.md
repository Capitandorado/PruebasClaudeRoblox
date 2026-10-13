# Publicar VOID FACTORY

## 1. Abrir y probar en Studio

1. Abre `build/VoidFactory.rbxl` en Roblox Studio (o sincroniza `src/` con Rojo, ver
   [DEVELOPMENT.md](DEVELOPMENT.md)).
2. **Play** (F5): comprueba que apareces en tu parcela, que *OPEN BOX* funciona y que los
   artefactos producen Energy.
3. **Test → Clients and Servers** con 2–3 jugadores: cada uno debe tener su parcela; prueba
   las visitas desde 🏆 Ranks.
4. Revisa la ventana **Output**: el servidor imprime `[VoidFactory] server ready`. En Studio
   sin acceso a API verás un aviso de que el progreso se guarda solo en memoria (normal).

## 2. Publicar

1. *File → Publish to Roblox* → crea una experiencia nueva (nombre, descripción, género
   *Simulator*).
2. **Game Settings → Security**:
   - Activa **Enable Studio Access to API Services** (para probar el guardado real en Studio).
3. **Game Settings → Places → Server Size / Max Players: 8**. El juego tiene 8 parcelas; un
   noveno jugador recibe un mensaje claro y Roblox no debería enviarlo a un servidor lleno si
   el límite coincide.
4. **Game Settings → Avatar**: cualquier configuración funciona (el juego no depende del avatar).
5. Publica de nuevo (*File → Publish to Roblox*) tras cambiar ajustes.

## 3. Comprobar el guardado real

1. Con el juego publicado y *API Services* activado, entra, abre cajas y coloca artefactos.
2. Sal, espera unos segundos y vuelve a entrar: tu fábrica debe estar igual.
3. Opcional: en Studio, *View → Data Stores* (o el *Data Stores Manager* del Creator Dashboard)
   muestra el almacén `VoidFactory_Players_v1`, clave `u_<UserId>`.

Los nombres de almacén están en `src/server/Services/Data.luau` (`Data.StoreName`) y
`Leaderboards.luau`. **No los cambies** después de publicar o los jugadores empezarán de cero.

## 4. Administradores (herramientas de depuración)

El panel 🛠️ Debug funciona en Studio y para el dueño de la experiencia (si es una cuenta de
usuario). Para añadir más personas (por ejemplo si la experiencia pertenece a un grupo),
añade sus UserId en `src/shared/Config/Admin.luau`:

```lua
Admin.UserIds = { 12345678 }
```

El servidor comprueba los permisos en cada comando; el botón solo aparece a quien tiene acceso.

## 5. Sonidos propios (opcional)

Sube los `.wav` de `assets/sounds/` y pega sus IDs en `src/shared/Config/Sounds.luau`
(detalles en [SOUNDS.md](SOUNDS.md)). Sin ellos, el juego usa sonidos integrados del cliente.

## 6. Icono y miniaturas

El juego no incluye imágenes de marketing. Haz capturas en Studio de tu fábrica (con neón y
bloom se ve muy bien de noche) y súbelas en *Game Settings → Basic Info*.

## Lista de comprobación antes de lanzar

- [ ] Max Players = 8.
- [ ] API Services activado y guardado comprobado entrando/saliendo.
- [ ] Probado en móvil (Studio: *Test → Device* emulando un teléfono).
- [ ] Revisado el Output de un servidor en vivo (*Developer Console*, F9) sin errores.
- [ ] Ajustado el balance si quieres otro ritmo (`docs/ECONOMY.md`).
