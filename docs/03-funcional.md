# 03 — Especificación funcional · v1.2

## 1. Modelo
El modelo separa **Montura**, **Fuente** y **Elegibilidad**. Una montura tiene N fuentes y cada fuente se evalúa por separado para el personaje activo.

## 2. Entidades

| Entidad | Campos clave |
|---|---|
| **Mount** | `mountID` (clave canónica), `spellID?`, `itemID?`, `expansion`, `sourceIDs[]`, `dataVersion` |
| **Source** | `sourceID`, `mountID`, `sourceType` (`raid` \| `dungeon` en el MVP), `journalInstanceID`, `journalEncounterID`, `difficultyIDs[]`, `lockoutModel`, `requirements[]`, `entrance` {`uiMapID`, `x`, `y`}, `dropRate?`, `confidence`, `provenance`, `reviewedAt` |
| **Requirement** | `type` (`level` \| `quest` \| `reputation` \| `renown` \| `achievement` \| `faction` \| `class`), `id`, `value`, `scope` (`character` \| `account` \| `warband` \| `unknown`) |
| **Eligibility** (en memoria) | `sourceID`, `state`, `reasons[]`, `missing[]`, `resetsAt?`, `checkedAt` |
| **UserList** (SavedVariables) | `order[]`, `hidden{}` (`untilReset` \| `forever`), `done{}`, `manualAdds{}` |

No se guardan nombres en el dataset. Se resuelven en tiempo de ejecución: la montura con `C_MountJournal`, y la instancia y el boss con el Encounter Journal.

## 3. Motor de elegibilidad

### Entradas
Nivel, facción y clase del personaje; la colección del journal; las misiones completadas (de personaje o de la cuenta); reputación y renombre; logros; las instancias guardadas.

### Algoritmo por fuente
1. ¿La montura ya está en la colección? → la fuente se descarta.
2. ¿La fuente está marcada como no obtenible en el dataset? → **Unavailable**.
3. Evaluar cada requisito:
   - **Cumplido y verificado** → continúa.
   - **Incumplido y verificado** → **Unlock Required**, con el detalle de lo que falta.
   - **No verificable** (API ausente, alcance `unknown` o dato incompleto) → **Verification Required**.
4. Evaluar el lockout según el `lockoutModel` (sección 4):
   - **Intento disponible** → **Ready**.
   - **Intento usado** → **Locked out**, con `resetsAt`.
   - **No se puede determinar** → **Verification Required**.

**Reglas que no se rompen:**
- Lo desconocido nunca es verdadero.
- No se infiere *Ready* por la ausencia de un bloqueo conocido.

## 4. Lockouts (requisito crítico del MVP)
Cada fuente declara un `lockoutModel`. Los modelos candidatos son los siguientes; **la tabla se valida en el cliente** (ver la matriz de lockouts en [05](05-mvp-y-roadmap.md)):

| Modelo | Significado | Cómo se detecta |
|---|---|---|
| `instance` | Una sola ID de instancia para la dificultad; una vez guardado, no hay más botín hasta el reset | `GetSavedInstanceInfo` con `locked = true` para (instancia, dificultad) |
| `perBoss` | Botín por boss: cada boss se puede saquear una vez por reset | `GetSavedInstanceEncounterInfo(i, j)` con `isKilled` para el boss que da la montura |
| `daily` | Mazmorra heroica con reset diario | `GetSavedInstanceInfo` + el reset diario |
| `none` | Sin lockout de botín | — |
| `unknown` | Todavía no está validado | → Verification Required |

**Detalles a resolver:**
- Las dificultades legacy (10/25 normal o heroica frente a Normal/Heroic/Mythic flexibles) y si la ID se comparte entre tamaños.
- Cómo relacionar el nombre o ID de la instancia guardada con su `journalInstanceID`.
- Las entradas expiradas de la lista de instancias guardadas, que se deben ignorar.

## 5. Lista "farmeable ahora"
1. Recorrer las monturas faltantes que tienen al menos una fuente en el dataset.
2. Evaluar la elegibilidad de cada fuente.
3. Tomar las fuentes **Ready** y agruparlas por (instancia, dificultad); una instancia puede dar varias monturas.
4. Agrupar las instancias por continente y zona usando el `uiMapID` de la entrada y su mapa padre.
5. Orden por defecto:
   1. la zona actual primero;
   2. luego el mismo continente;
   3. a igual ubicación, la instancia con más monturas;
   4. después, por expansión.
6. Aplicar las ediciones del jugador: orden manual, ocultas y hechas.
7. Si hay diferencias con la lista guardada (por un reset o un lockout nuevo), **proponer** los cambios.

Sin scoring y sin estimación de duración en el MVP.

## 6. Eventos y refresco

| Evento | Acción |
|---|---|
| `ADDON_LOADED` | Inicializar las SavedVariables y las migraciones |
| `PLAYER_LOGIN` | Registrar el personaje y escanear la colección |
| `PLAYER_ENTERING_WORLD` | Volver a escanear la colección (con debounce) y pedir `RequestRaidInfo()` |
| `UPDATE_INSTANCE_INFO` | Recalcular los lockouts y el estado de las fuentes |
| `NEW_MOUNT_ADDED` | Quitar la montura de la lista y actualizar los totales |
| `PLAYER_LEVEL_UP` | Volver a evaluar los requisitos de nivel |
| `QUEST_TURNED_IN` | Volver a evaluar las fuentes que dependen de esa misión |
| `ZONE_CHANGED_NEW_AREA` | Resaltar el grupo de la zona; no reordenar |
| `BOSS_KILL` / `ENCOUNTER_END` | Pedir `RequestRaidInfo()` para ver el lockout nuevo, **sin leer datos de combate** |

Los eventos que no existan en el cliente se registran como desconocidos y no rompen el addon (ver `ns:On` en `Core.lua`).

## 7. Criterios de aceptación
Están en [05-mvp-y-roadmap.md](05-mvp-y-roadmap.md#criterios-de-aceptación-del-mvp).
