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
| Overclocker | 5m45s | 12m00s |
| Fusion Chamber | 7m35s | 15m00s |
| Lucky Fabricator | 8m45s | 18m00s |
| Primer Legendary | 9m15s | 45m10s |
| Primer Mythic | 42m07s | 72m08s |
| **Primer rebirth** | **73m24s** | **93m00s** |
| Void Forge | 81m10s | 102m07s |
| Segundo rebirth | 131m53s | 228m (1/5 partidas) |

Void y Secret son metas a largo plazo (horas de Void Forge); sus probabilidades se muestran
tal cual en *Collection → Odds*.

## Decisiones de diseño que salieron del simulador

- Las misiones daban más Energy que la producción y una de ellas («coloca X artefactos») se podía
  repetir quitando y poniendo el mismo objeto. Ahora solo usan estadísticas que cuestan tiempo,
  objetos o Energy, y la recompensa equivale a 30 s de producción (con un mínimo).
- La velocidad acumulable hacía las máquinas 4 veces más rápidas sin límite inferior: ahora el
  máximo es x2,5 con intervalos mínimos de 2 s (fabricadora) y 3 s (impresora).
- Las cajas de pago cuestan lo mayor entre un precio base y X segundos de la **mejor producción de
  la partida** (no la actual, para que quitar artefactos no abarate las cajas). Así siguen siendo
  una decisión real en cualquier momento de la partida.
