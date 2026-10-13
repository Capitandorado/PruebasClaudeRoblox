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
     En Studio el juego guarda en almacenes aparte (`..._Studio`): tus pruebas con el panel
     de depuración no afectan a los datos ni a las clasificaciones de los jugadores.
3. **Game Settings → Places → Server Size / Max Players: 8**. El juego tiene 8 parcelas; un
   noveno jugador recibe un mensaje claro y Roblox no debería enviarlo a un servidor lleno si
   el límite coincide.
4. **Game Settings → Avatar**: cualquier configuración funciona (el juego no depende del avatar).
5. Publica de nuevo (*File → Publish to Roblox*) tras cambiar ajustes.

## 3. Comprobar el guardado real

1. Con el juego publicado y *API Services* activado, entra, abre cajas y coloca artefactos.
2. Sal, espera unos segundos y vuelve a entrar: tu fábrica debe estar igual.
3. Opcional: en Studio, *View → Data Stores* (o el *Data Stores Manager* del Creator Dashboard)
   muestra el almacén `VoidFactory_Players_v1` (o `VoidFactory_Players_v1_Studio` para las
   partidas de Studio), clave `u_<UserId>`.

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

## 7. Tienda Robux (pases y productos)

La tienda (botón dorado **STORE**) ya está programada; solo faltan los IDs, que Roblox crea
para tu experiencia. Hasta que los pongas, en un servidor real esos artículos **no se
muestran**, y en Studio aparecen con un botón *Test (Studio)* que los da gratis para probar.

1. *Creator Dashboard → tu experiencia → Monetization → Passes → Create a Pass*: crea los
   6 pases (nombre, imagen y precio) y activa *Item for Sale*.
2. *Monetization → Developer Products → Create*: crea los 6 productos.
3. Copia cada ID en el campo `id` correspondiente de `src/shared/Config/Monetization.luau`.
4. En Studio, las compras con IDs reales son de prueba (no cobran Robux): compra cada
   artículo y comprueba el efecto y el mensaje de confirmación.

| Clave | Tipo | Qué hace | Precio sugerido |
| --- | --- | --- | --- |
| `vip` | Pase | +25 % Energy, +10 % suerte, cartel dorado | 299 |
| `double_energy` | Pase | Energy x2 (también sin conexión) | 249 |
| `lucky_charm` | Pase | Suerte x1,5 | 199 |
| `turbo_fabricator` | Pase | Máquinas un 50 % más rápidas, +2 cajas | 149 |
| `mega_storage` | Pase | +100 huecos de inventario | 99 |
| `night_owl` | Pase | +25 % producción sin conexión, hasta 24 h | 99 |
| `energy_small/medium/large` | Producto | 15 min / 1 h / 4 h de producción | 25 / 79 / 249 |
| `boost_energy`, `boost_luck` | Producto | x2 Energy / x2 suerte durante 30 min de juego | 49 / 49 |
| `refill` | Producto | Llena las cajas de todas las fabricadoras | 15 |

Cómo funciona por dentro: los productos se conceden en `MarketplaceService.ProcessReceipt`,
se guarda el ID de compra junto con la recompensa y solo entonces se confirma a Roblox, así que
una compra nunca se pierde ni se da dos veces. La propiedad de los pases se comprueba al entrar.
No se venden objetos aleatorios por Robux (las *Daily Crates* solo salen de recompensas
gratuitas).

## 8. Códigos

Los códigos están en `src/shared/Config/Codes.luau` (cada jugador puede usar cada código una
vez; `expires` es opcional). Vienen tres de lanzamiento: `VOIDFACTORY`, `LUCKY` y `CRATE`.
Publica nuevos códigos en la página del juego o en tus redes para traer jugadores de vuelta.

## Lista de comprobación antes de lanzar

- [ ] Max Players = 8.
- [ ] API Services activado y guardado comprobado entrando/saliendo.
- [ ] Probado en móvil (Studio: *Test → Device* emulando un teléfono).
- [ ] Revisado el Output de un servidor en vivo (*Developer Console*, F9) sin errores.
- [ ] Ajustado el balance si quieres otro ritmo (`docs/ECONOMY.md`).
- [ ] IDs de pases y productos copiados en `Config/Monetization.luau` (o la tienda solo
      mostrará los códigos).
