# Economía y ritmo de progresión

Todos los costes, probabilidades y recompensas están en `src/shared/Config/`. Tras cada cambio
de balance, ejecuta el simulador: un bot juega con la **lógica real** del juego y mide cuándo
alcanza cada hito.

```
lune run tools/simulate.luau 240 active 5   # jugador activo, 240 min, 5 semillas
lune run tools/simulate.luau 240 casual 5   # juega 30 s cada 3 min
```

## Resultados con el balance actual (mediana de 5 partidas)

| Hito | Jugador activo | Jugador casual |
| --- | --- | --- |
| Box Printer | 1m47s | 6m00s |
| Primera ampliación | 3m44s | 9m00s |
| Overclocker | 5m29s | 12m00s |
| Fusion Chamber | 6m36s | 15m00s |
| Lucky Fabricator | 7m00s | 18m00s |
| Primer Legendary | 7m54s | 18m25s |
| Cuarta ampliación | 25m16s | 54m00s |
| **Primer rebirth** | **54m29s** | **93m00s** |
| Void Forge | 61m28s | 99m22s |
| Primer Mythic | 62m40s | 69m04s |
| Segundo rebirth | 132m34s | 195m (1/5 partidas) |

Divine, Celestial, Void y Secret son metas a largo plazo (horas tras el primer rebirth); sus
probabilidades se muestran tal cual en *Collection → Odds*.

## Decisiones de diseño que salieron del simulador

- Las misiones daban más Energy que la producción y una de ellas («coloca X artefactos») se podía
  repetir quitando y poniendo el mismo objeto. Ahora solo usan estadísticas que cuestan tiempo,
  objetos o Energy, y la recompensa equivale a 30 s de producción (con un mínimo).
- La velocidad acumulable hacía las máquinas 4 veces más rápidas sin límite inferior: ahora el
  máximo es x2,5 con intervalos mínimos de 2 s (fabricadora) y 3 s (impresora).
- El bonus de colección original (+2 % por artefacto) casi duplicaba la velocidad del juego al
  acumularse con todo lo demás; se redujo a +1 % por artefacto y +0,25 % por variante.
- Las cajas de pago cuestan lo mayor entre un precio base y X segundos de la **mejor producción de
  la partida** (no la actual, para que quitar artefactos no abarate las cajas). Así siguen siendo
  una decisión real en cualquier momento de la partida.

## Ganancias sin conexión y recompensa diaria

No entran en el simulador (mide sesiones de juego), así que sus límites se eligieron para que
ayuden a quien vuelve sin sustituir al juego activo:

- **Sin conexión** (`Economy.Offline*`): al volver, el servidor paga el 25 % de la producción
  estable (sin eventos ni Void Surge) por el tiempo fuera, con un máximo de 8 h: como mucho
  2 h de producción activa. Ausencias de menos de 5 min no dan nada (cambios de servidor). La
  ventaja de rebirth *Night Shift* sube el porcentaje un 10 % por nivel (máximo 75 %). La
  Box Printer guarda hasta 3 cajas.
- **Diaria** (`Config/Daily`): 7 días que se repiten; la racha se pierde si se salta un día
  (UTC). Los días de Energy dan entre 2 y 10 minutos de la producción actual (con mínimo para
  jugadores nuevos); los días 3 y 7 dan *Daily Crates* (Rare o mejor, probabilidades visibles
  en *Collection → Odds*).

