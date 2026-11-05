# 05 — MVP, entregables y roadmap · v1.2

## Definición del MVP (v1.0)
> Un jugador abre AnimalitosPlanner con cualquier personaje y ve **qué raids y mazmorras legacy puede hacer ahora mismo para conseguir monturas que le faltan a la cuenta**, agrupadas por zona. Pone un waypoint a la entrada con un clic y la lista se actualiza sola cuando consigue la montura o queda guardado en la instancia.

### Incluido
- El catálogo completo del journal, con el progreso de la cuenta.
- Las fuentes de raids y mazmorras legacy: primero el **piloto** y luego toda la cobertura legacy.
- Estados por fuente: Ready, Locked out, Unlock Required, Verification Required y Unavailable.
- Lockouts según la dificultad y el modelo de botín.
- La lista "farmeable ahora", con orden manual, ocultar, marcar como hecho y agregar a mano con advertencia.
- Waypoint nativo, con TomTom como opción.
- Pantallas: Inicio, Farmeable ahora, Colección, Detalle de montura y Ajustes.
- Locales enUS, esES y esMX.

### Excluido del MVP
Scoring, modos Hoy/Semana/Custom, estimación de duración, grafo de viajes, world bosses, rares, eventos, reputaciones y otras fuentes que no sean de instancias, y la optimización entre personajes.

## Piloto de datos
Son ~13 raids clásicas de monturas, elegidas para cubrir **varias expansiones y modelos de lockout**. Las relaciones exactas (boss → montura → dificultad) salen del pipeline, no de esta lista.

| # | Raid | Expansión |
|---|---|---|
| 1 | Karazhan | TBC |
| 2 | Tempest Keep (The Eye) | TBC |
| 3 | Onyxia's Lair | Wrath (versión revisada) |
| 4 | Ulduar | Wrath |
| 5 | Icecrown Citadel | Wrath |
| 6 | Throne of the Four Winds | Cataclysm |
| 7 | Firelands | Cataclysm |
| 8 | Dragon Soul | Cataclysm |
| 9 | Mogu'shan Vaults | MoP |
| 10 | Throne of Thunder | MoP |
| 11 | Siege of Orgrimmar | MoP |
| 12 | Hellfire Citadel | WoD |
| 13 | Antorus, the Burning Throne | Legion |

**Opcional:** sumar 2 o 3 mazmorras con montura conocida para probar el modelo `daily`, por ejemplo Stratholme o Utgarde Pinnacle (heroica).

## Criterios de aceptación del MVP

| ID | Criterio |
|---|---|
| AC-01 | Los totales coinciden con el Mount Journal y se actualizan sin `/reload` al conseguir una montura |
| AC-02 | Una montura conseguida con otro personaje nunca aparece como objetivo |
| AC-03 | Cada raid del piloto tiene sus fuentes con `mountID`, encuentro, dificultades y `lockoutModel` validados |
| AC-04 | Una raid en la que el personaje está guardado (en la dificultad que da la montura) aparece como *Locked out*, con su reset, y no como Ready |
| AC-05 | En el modelo `perBoss`, matar a otro boss no bloquea la fuente del boss que da la montura |
| AC-06 | Un requisito con alcance `unknown` o no verificable produce *Verification Required*, nunca Ready |
| AC-07 | Las fuentes con *Unlock Required* explican qué falta |
| AC-08 | La lista agrupa por continente y zona; la zona actual va primero |
| AC-09 | El orden manual, las ocultas y las hechas persisten tras un `/reload`, un cierre de sesión y un cambio de personaje |
| AC-10 | Después de un reset se **propone** actualizar la lista; no cambia sola |
| AC-11 | El waypoint nativo lleva a la entrada de la instancia; no pisa un waypoint del jugador sin confirmación |
| AC-12 | Con TomTom activado se crea un waypoint de TomTom; sin TomTom todo funciona igual |
| AC-13 | La Colección muestra todas las monturas, con filtros independientes de colección y de estado |
| AC-14 | Con el cliente en esES o esMX, los nombres de monturas, instancias y bosses salen traducidos sin estar en el dataset |
| AC-15 | Abrir la ventana no causa tirones perceptibles; no hay trabajo en `OnUpdate` |
| AC-16 | Ningún error de Lua en una sesión normal con `/console scriptErrors 1` |

## Entregables

| Versión | Entregable | Contenido | Hecho cuando |
|---|---|---|---|
| **v0.1** | Foundation | TOC, bus de eventos, SavedVariables y migraciones, adaptador del Mount Journal, ventana de totales, `/aplan probe` | ✅ validado en 12.1.5 (probe 2026-11-05) |
| **v0.2** | Datos del piloto | Scan en el cliente → `pipeline/build_dataset.py` → `Data/Dataset.lua`; overrides curados; reporte de huecos | AC-03 · 🟡 dataset generado; faltan 5 entradas, 2 entradas dudosas y los lockout models |
| **v0.3** | Elegibilidad y lockouts | `Lockouts.lua`, `Eligibility.lua`, `FarmList.lua`, `Navigation.lua`; comandos `/aplan now` y `/aplan go <n>` para probar | AC-04 a AC-07 · 🟡 implementado; falta probarlo en el cliente |
| **v0.4** | Farmeable ahora y navegación | `FarmList.lua`, la pantalla, el waypoint nativo, el adaptador de TomTom y la persistencia de las ediciones | AC-08 a AC-12 |
| **v0.5** | UI completa | Inicio, Colección virtualizada, Detalle de montura, Ajustes con Ace3 y LibDBIcon | AC-13, AC-15 |
| **v0.6** | Cobertura legacy | Todas las raids y mazmorras legacy con montura; revisión de datos; localización completa | AC-14 |
| **v1.0** | Release del MVP | Pruebas con 3 o más personajes de distintas facciones y niveles, empaquetado, CHANGELOG y publicación en CurseForge/Wago | AC-01 a AC-16 |

## Roadmap después del MVP
1. **Fase 2 — Planificación inteligente:** scoring calibrado (factores normalizados de 0–100, penalizaciones con unidades definidas, el puntaje de actividades separado del orden de la ruta), modos Hoy/Semana y duración estimada.
2. **Fase 3 — Mundo abierto:** world bosses, rares, eventos y seguimiento de disponibilidad.
3. **Fase 4 — Cobertura total:** reputaciones, renombre, logros, profesiones, PvP, Trading Post y promociones.
4. **Fase 5:** optimización entre personajes y grafo de viajes.

## Validación técnica
Se completa con los resultados de `/aplan probe` en el cliente 12.1.5.70783.

| Ítem | Estado |
|---|---|
| Las 52 APIs del diseño existen; 0 eventos desconocidos; 0 errores | ✅ probe del 2026-11-05 |
| `GetMountInfoByID` devuelve **13** valores: los 12 documentados más un booleano extra al final (probablemente *isSteadyFlight*); el orden de los 12 coincide | ✅ |
| `GetMountInfoExtraByID` devuelve 9 valores; el 3.º (`sourceText`) se puede parsear (`Vendor:`, `Zone:`, `Cost:`); las retiradas dicen `Legacy` | ✅ |
| `shouldHideOnChar` = true también en monturas **no obtenibles** (p. ej. Gray Wolf, White Stallion), no solo de otra facción | ✅ se corrigió el texto de la UI |
| `sourceType` ↔ `BATTLE_PET_SOURCE_n` (1 Drop … 12 Trading Post; 0 = desconocido, 44 monturas) | ✅ |
| El EJ lista las 13 raids del piloto (IDs: 745, 749, 760, 759, 758, 74, 78, 187, 317, 362, 369, 669, 946) | ✅ |
| El EJ incluye pseudoinstancias de world bosses (Pandaria 322, Draenor 557, Broken Isles 822, Azeroth 1028…), un tier "Current Season" duplicado y "Keystone Dungeons" 1319 | ✅ hay que filtrarlas o deduplicarlas |
| `GetDungeonEntrancesForMap`: devuelve `areaPoiID`, `name`, `journalInstanceID` y `position` (0–1) | ✅ |
| El EJ muestra las monturas en el botín legacy | ✅ el scan encontró 66 monturas en 50 instancias, con las 13 del piloto completas |
| `GetSavedInstanceInfo`: 14 valores; `[14]` = mapID de la instancia (= `mapID` del EJ); los encuentros tienen `isKilled` por boss | ✅ 4 lockouts reales |
| Matriz de lockouts | 🟡 regla por boss validada (FL, ICC, Ulduar, UP); falta el caso 10/25 compartido de Cata/MoP |
| Waypoint nativo: `CanSetUserWaypointOnMap` = true en Silvermoon; falta probar el comportamiento con un waypoint existente | 🟡 (v0.4) |
| TomTom `AddWaypoint` | ✅ firma verificada en el código de v4.3.13 y cargado en el cliente |
| `IsAccountWideReputation` y `IsQuestFlaggedCompletedOnAccount` existen | ✅ (falta probar su comportamiento) |

## Preguntas abiertas
1. **Reparto de roles en el equipo:** pipeline (Python), motor (Lua), UI (Lua) y curación de datos.
2. ¿Sumamos 2 o 3 mazmorras al piloto para cubrir el modelo `daily`?
3. Nombre público: ¿"AnimalitosPlanner" u otro? El repo se llama `animalitos_addon`.
4. ¿Dónde se publica: CurseForge, Wago o ambos? ¿Desde qué versión?
5. API key de Battle.net para validación cruzada: ¿quién la gestiona?
