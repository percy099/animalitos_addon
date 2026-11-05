# 04 — Arquitectura técnica · v1.2

## 1. Principios
- Lua modular, separado en capas: presentación, aplicación, datos e integraciones.
- Todas las llamadas a APIs de Blizzard pasan por **adaptadores**, para corregir en un solo lugar si cambian entre builds.
- Dataset estático y versionado, generado por un pipeline fuera del juego.
- Nada de datos de combate protegidos (Secret Values de Midnight).
- Los eventos se registran de forma tolerante: si un evento no existe, se registra y el addon sigue.

## 2. Estructura del repo
```
AnimalitosPlanner/                  <- carpeta del addon (lo que se distribuye)
  AnimalitosPlanner.toc             Interface 120105
  Core.lua                     namespace, bus de eventos, helpers
  Locales/                     enUS, esES, esMX
  Storage/SavedVariables.lua   schema + migraciones
  Integrations/
    MountJournal.lua           adaptador C_MountJournal
    EncounterJournal.lua       (v0.2) instancias, encuentros, entradas
    Lockouts.lua               (v0.3) instancias guardadas
    Navigation.lua             (v0.4) waypoint nativo + adaptador TomTom
  Data/                        (v0.2) archivos .lua GENERADOS por el pipeline, no editar
  Modules/
    Collection.lua             totales account-wide
    Eligibility.lua            (v0.3)
    FarmList.lua               (v0.4) lista "farmeable ahora"
    Probe.lua                  /aplan probe (diagnóstico)
  UI/                          MainFrame + pantallas + Widgets
  Bootstrap.lua                eventos + slash commands (se carga al final)
  Libs/                        (v0.5) Ace3 y librerías relacionadas, empaquetadas
pipeline/                      (v0.2) scripts Python que generan AnimalitosPlanner/Data/
data/curated/                  (v0.2) JSON curado a mano, con procedencia
docs/                          esta documentación
```

## 3. APIs (candidatas; se confirman con `/aplan probe`)

| Capacidad | API |
|---|---|
| Monturas | `C_MountJournal.GetMountIDs`, `GetMountInfoByID`, `GetMountInfoExtraByID`, `GetMountFromItem`, `GetMountFromSpell` |
| Instancias y botín | `EJ_GetNumTiers`, `EJ_SelectTier`, `EJ_GetInstanceByIndex`, `EJ_SelectInstance`, `EJ_SetDifficulty`, `EJ_GetEncounterInfoByIndex`, `EJ_GetNumLoot`, `C_EncounterJournal.GetLootInfoByIndex` |
| Entradas | `C_EncounterJournal.GetDungeonEntrancesForMap(uiMapID)` |
| Lockouts | `RequestRaidInfo`, `GetNumSavedInstances`, `GetSavedInstanceInfo`, `GetSavedInstanceEncounterInfo` |
| Requisitos | `C_QuestLog.IsQuestFlaggedCompleted[OnAccount]`, `C_Reputation.GetFactionDataByID`, `C_Reputation.IsAccountWideReputation`, `C_MajorFactions.*`, `GetAchievementInfo`, `UnitLevel`, `UnitFactionGroup` |
| Mapa y waypoint | `C_Map.GetBestMapForUnit`, `GetMapInfo`, `CanSetUserWaypointOnMap`, `SetUserWaypoint`, `HasUserWaypoint`, `C_SuperTrack.SetSuperTrackedUserWaypoint`, `UiMapPoint.CreateFromCoordinates` |
| TomTom | `TomTom:AddWaypoint(m, x, y, opts)` y `TomTom:RemoveWaypoint(uid)`; verificado en el código de TomTom v4.3.13 |

**Nota sobre el Encounter Journal:** la carga del botín es asíncrona (evento `EJ_LOOT_DATA_RECIEVED`, con esa ortografía en la API). Seleccionar un tier o una instancia cambia el estado del Encounter Journal de la interfaz, así que siempre se restaura el estado anterior.

## 4. Identificadores
| Campo | Uso |
|---|---|
| `mountID` | Clave canónica (Mount Journal) |
| `spellID`, `itemID` | Referencias cruzadas opcionales |
| `journalInstanceID`, `journalEncounterID`, `difficultyID` | Relación instancia / boss / dificultad |
| `uiMapID` + `x`, `y` normalizados (0–1) | Ubicación de la entrada y waypoints |
| `instanceID` (mapa de la instancia) | Para relacionar con `GetSavedInstanceInfo` (14.º valor de retorno; a validar) |

## 5. Pipeline de datos

**Fuentes:**

| Fuente | Uso | Licencia / condiciones |
|---|---|---|
| wago.tools (DB2 en CSV) | Mount, JournalInstance, JournalEncounter, JournalEncounterItem, ItemEffect/ItemXMount, UiMap, Map | Datos del juego; se citan como fuente |
| Blizzard Game Data API | Validación cruzada de monturas y del journal | Requiere API key gratuita |
| JSON curado (`data/curated/`) | lockoutModel, requisitos, ajustes de coordenadas, drop rates con procedencia | Nuestro (MIT) |
| Rarity / SimpleArmory / HandyNotes | **No se importan** mientras no se revise la licencia de cada uno y su compatibilidad con MIT (o se pida permiso a sus autores) | Por ahora solo como referencia de verificación manual |
| Wowhead | Solo verificación manual; prohibido el scraping | Términos de uso de Wowhead |

**Pasos:**
1. **Extraer:** descargar los CSV de las tablas DB2 del build objetivo, con versión fija (`12.1.5.70783`).
2. **Relacionar:** montura → ítem que la enseña → botín del encuentro (JournalEncounterItem) → encuentro → instancia, incluyendo dificultades.
3. **Combinar con el JSON curado:** lockoutModel, requisitos, entradas y drop rates.
4. **Validar:** detectar duplicados, campos faltantes y fuentes sin entrada; generar un reporte.
5. **Generar** `AnimalitosPlanner/Data/*.lua` y `DataVersion.lua` (build, fecha y hash).
6. **Comprobar en el juego:** `/aplan probe` contrasta el dataset con el Encounter Journal y reporta discrepancias.

**Cada dato curado lleva:** `confidence` (`verified` | `estimated` | `community_reported` | `unknown`), `provenance` (URL o descripción), `reviewedAt` y `reviewedBy`.

## 6. SavedVariables (`AnimalitosPlannerDB`, por cuenta)
```lua
AnimalitosPlannerDB = {
  version = 1,                      -- schema; migraciones secuenciales
  settings = { navigation = "native" },
  characterData = { ["Nombre-Reino-US"] = { level, faction, class, lastSeen } },
  farmList = { order = {}, hidden = {}, done = {}, manualAdds = {} }, -- v0.4
  userData = { favorites = {}, excludedMounts = {} },
  ui = { point = {...} },
  diagnostics = { ... },            -- /aplan probe
}
```
- **Fuera de las SavedVariables:** la colección (se lee del journal) y los lockouts (se leen del juego; como mucho se guardan en caché para mostrarlos).
- **Migraciones:** `migrations[n]` lleva el esquema de n-1 a n. La versión se escribe solo si la migración funcionó, y nunca se edita una migración ya publicada.

## 7. Librerías
- **v0.1–v0.4:** sin librerías; la entrada al addon va por AddonCompartment.
- **v0.5:** Ace3 (AceDB para perfiles, AceConfig/AceConfigDialog para Ajustes) y LibDataBroker con LibDBIcon. Se empaquetan en `Libs/` y la lógica del addon no depende de ellas.

## 8. Rendimiento
- Nunca se crea un frame por montura: las listas son virtualizadas.
- Las evaluaciones se disparan por eventos y con debounce; no hay cálculos en `OnUpdate`.
- Hay índices precalculados en el dataset (por instancia, por montura y por `uiMapID`).
- Al recibir un evento solo se recalculan las fuentes afectadas.

## 9. Riesgos
| Riesgo | Mitigación |
|---|---|
| Cambios de API entre builds | Adaptadores, registro tolerante de eventos y `/aplan probe` |
| Lockouts mal interpretados | Un `lockoutModel` por fuente; `unknown` → Verification Required; pruebas con personajes reales |
| El Encounter Journal no muestra todo el botín legacy | Usar las tablas DB2 como base y el JSON curado para los huecos |
| Licencias de datos de terceros | No importarlos; solo verificación manual |
| Cambios del esquema de SavedVariables | Versión de esquema y migraciones |
