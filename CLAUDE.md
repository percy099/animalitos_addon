# CLAUDE.md — AnimalitosPlanner

Contexto para quien continúe el proyecto, sea una persona del equipo o Claude. Léelo entero antes de cambiar código. Si una decisión de aquí choca con lo que te piden, pregunta antes de actuar.

## 1. Qué es
Addon de WoW **retail** para farmear monturas. Se hizo con un grupo de amigos; el repo es `percy099/animalitos_addon` (público, licencia **MIT**). Antes se llamaba **Mount Planner**: la carpeta raíz local sigue siendo `F:\WowAddons\MountPlanner` y los `.docx` originales usan ese nombre.

**MVP:** con cualquier personaje, mostrar qué **raids y mazmorras legacy** se pueden hacer **ahora** para conseguir monturas que le faltan a la **cuenta**, qué está en lockout y cuándo se reinicia, y poner un waypoint en la entrada.

La especificación vigente es `docs/` (v1.2, en español). El documento más útil es `docs/05-mvp-y-roadmap.md`, con el MVP, los criterios de aceptación AC-01..AC-16, los entregables por versión y la tabla de validación técnica.

## 2. Estado (2026-11-06)
| Versión | Estado |
|---|---|
| v0.1 Foundation (SavedVariables, Mount Journal, ventana, probe) | ✅ validada en el cliente |
| v0.2 Dataset desde el scan en el juego + pipeline | ✅ 67 fuentes, 66 monturas, 50 instancias |
| v0.3 Lockouts + elegibilidad + `/aplan now` / `go` / `why` | ✅ validada en el cliente (Dragon Soul, Firelands, ICC, Ulduar, Utgarde Pinnacle) |
| v0.4 Pestaña "Farmeable ahora" (tarjetas, Ir, Ocultar hasta el reset) | 🟡 funciona; **pendiente**: la flecha del waypoint nativo no se vio (diagnosticar con `/aplan navdebug`, ver §9) y reordenar a mano |
| Rediseño de la UI (rama `josemaria`, v0.4.7–0.12.2) | 🟡 validado en el cliente; pendiente revisar y fusionar con un PR (ver §10) |
| v0.5 Colección virtualizada, Detalle de montura | ✅ rama `josemaria`: Colección (List, Boss drops, Achievements, Other drops) y Detalle de montura (estado, dónde conseguirla por dificultad, logros, texto del diario) |
| Planner (rama `josemaria`, v0.6.0–0.12.2) | ✅ validado en el cliente, con mago y con Horda |
| v0.6 Cobertura legacy completa y curación | 🟡 rama `josemaria` v0.7–0.8: world bosses (6 monturas, lockout validado con Galleon) y logros con montura (lista + enlace a instancias). Rares y otros drops: solo quién y zona desde el diario (vista *Other drops*, botón Map). Kraulok por su misión de mundo (v0.11.0; abre sin errores, estados por validar cuando esté en rotación) |
| Rama `josemaria` v0.13–0.25 | ✅ validado en el cliente: iconos de viaje, menú *Show:* del Planner (raid/mazmorra/world boss/favoritos), favoritos del addon, inferencia de fuente, jefes de eventos de temporada, requisitos y precio de vendedor (*Ready to buy*), ayuda de dificultad, viaje con clic en la mini, pasada de rendimiento, skips de raid (IDs confirmados con `/aplan skips`), botón *Set* de dificultad, vuelta a la capital según la piedra de hogar (en un personaje sin piedra en Stormwind) |
| Rama `josemaria` v0.25.1–0.30.2 | 🟡 subido. **Confirmado en el cliente:** jefe muerto en gris (raids Heroic/Normal y dungeon Normal sin lockout), *Back*, orden de jefes, clicables con contorno, clic en logros, botón de dificultad, vuelta a casa por hubs, Firelands → Onyxia, orden de Northrend, Throne of the Four Winds, Ny'alotha, Stratholme Service Entrance, Silvermoon → Plaguelands volando. **Por probar:** *My route* (v0.28.0), Freehold auto-hecho con el lockout *Lord Harlan Sweete* (v0.27.4), ruta de grupo y presencia (`Comm.lua`, hace falta otro jugador con el addon), texto de portal del mago en grupo, atajos de mago (ICC → Utgarde, Return to Karazhan → Zul'Gurub), tamaño 10/25 de raid legacy, *Done today* de eventos, Kraulok |
| v1.0 Release (CurseForge/Wago) | ⏳ |

## 3. Entorno
- Cliente objetivo: **12.1.5.70783**, `## Interface: 120105`, cliente en **enUS** (los locales esES y esMX existen, pero no se han probado en el juego).
- WoW instalado en `C:\World of Warcraft\_retail_`. La carpeta del addon es un **junction**: `AddOns\AnimalitosPlanner` → `F:\WowAddons\MountPlanner\AnimalitosPlanner`. Lo que se edite en el repo se ve con `/reload`, pero un addon nuevo o renombrado requiere reiniciar el juego.
- Desde WSL: `/mnt/c/...` y `/mnt/f/...`. SavedVariables en `C:\World of Warcraft\_retail_\WTF\Account\309771233#1\SavedVariables\AnimalitosPlanner.lua`.
- No hay intérprete de Lua local, así que la sintaxis se valida en el juego. Al menos revisa que los bloques estén balanceados (`function/if/do` contra `end`).
- Git: el push funciona con el Git Credential Manager de Windows, configurado solo en este repo. Autor: `percy099 <percy.quezada@pucp.pe>`.

## 4. Arquitectura del addon (`AnimalitosPlanner/`)
El orden de carga está en el `.toc` y **importa**:

| Archivo | Rol |
|---|---|
| `Core.lua` | Namespace `ns`, `ns.L` (fallback a la clave), bus de eventos `ns:On(event, fn)` tolerante a eventos inexistentes, `ns:Debounce`, `ns:GetCharacterKey` |
| `Locales/enUS, esES, esMX` | enUS es la base; esES se aplica también a esMX; esMX solo sobrescribe lo que difiere |
| `Data/Dataset.lua` | **GENERADO**, no se edita a mano. `ns.Data = { version, instances[jid], sources[] }` |
| `Storage/SavedVariables.lua` | `AnimalitosPlannerDB` (por cuenta), versión de esquema, `migrations[n]` y `fillDefaults` |
| `Integrations/MountJournal.lua` | Único lugar con llamadas a `C_MountJournal` |
| `Integrations/Lockouts.lua` | Instancias guardadas → `byMap[instanceMapID][difficultyID] = { killed[bossName], resetAt }`. `Refresh()` devuelve si cambió algo (firma): solo entonces se redibuja |
| `Integrations/Holidays.lua` | Jefes de eventos de temporada por el buscador de mazmorras (LFG 285/287/288): activo = la cola aparece en `GetLFGRandomDungeonInfo`; hecho hoy = `GetLFGDungeonRewards`; `OpenQueue`. `/aplan events test` los simula activos |
| `Integrations/Wallet.lua` | Precio desde el texto del diario (oro, monedas enlazadas (`Hcurrency:`), objetos (`Hitem:`), monedas por icono) y cuánto tiene el personaje |
| `Integrations/Requirements.lua` | Requisitos de vendedor: tooltip del objeto de la montura (`C_TooltipInfo`, rojo = no cumple), renombre y logro del texto del diario, requisitos curados (`ns.Data.vendorReqs`), precio (Wallet). Remix se ignora. `VendorSet()` en segundo plano para *Ready to buy* |
| `Integrations/Difficulty.lua` | Dificultad: `Pick` (la que da más monturas Ready), `Inside`, `IsSet`, `Set` (legacy = modo 14/15 + tamaño 3/4), `Blocked` (combate, dentro, no líder). Skips de raid: `Skips`/`SkipNote` (misión de esa dificultad o una más alta, de cuenta si el cliente lo dice), `DebugSkips` (`/aplan skips`) |
| `Integrations/Comm.lua` | Mensajes ocultos entre addons del grupo (`C_ChatInfo.SendAddonMessage`, prefijo `AnimPlan`, canal party/raid/instance). `HELLO`/`HI` con versión y facción; nunca en combate (se encola); `Peers()`; `/aplan group` |
| `Modules/Collection.lua` | Totales; el número principal coincide con el diario de Blizzard (visibles para el personaje) |
| `Modules/Eligibility.lua` | Estado por (fuente, dificultad): `ready`, `lockedOut`, `verificationRequired`, `unavailable`, `collected`, `outOfScope` |
| `Modules/FarmList.lua` | Agrupa por instancia, ordena (zona actual → continente → número de monturas → expansión) y oculta hasta el reset |
| `Modules/Planner.lua` | Ruta **estática** del planner (orden fijo por facción, nunca por posición), pasos de viaje (portales de capital, portales de zona de Cata, teletransportes de mago, mago en el grupo), marcas manuales por personaje hasta el reset |
| `Integrations/Achievements.lua` | Logros con montura de recompensa (todas las categorías), progreso por criterio, criterios pendientes, abrir en la ventana de logros |
| `Integrations/Navigation.lua` | Waypoint nativo (`C_Map.SetUserWaypoint` + `C_SuperTrack`) o TomTom; aviso si el destino está en otro continente; `Debug()` |
| `Integrations/MinimapButton.lua` | Botón del minimapa vía LibDBIcon + LibDataBroker **si otro addon ya los carga** (dependencia blanda, no se incluyen; ver §10) |
| `Modules/Probe.lua` | `/aplan probe`: firmas de API, EJ, mapa, lockouts y TomTom → `AnimalitosPlannerDB.diagnostics` |
| `Modules/DevScan.lua` | `/aplan scan`: construye el dataset en bruto desde el cliente → `AnimalitosPlannerDB.scan` |
| `UI/Style.lua` | Sistema visual compartido (`ns.UI`): paleta, fuentes, paneles redondeados, botones, interruptor (`UI.Switch`), slider, scroll fino, buscador, círculos, recorte del arte del EJ. Se carga antes que los paneles |
| `UI/FarmPanel.lua` | *Farmable now*: buscador, grupos por continente, tarjetas con arte, secciones "Locked out" / "Needs verification" (pools) |
| `UI/HomePanel.lua` | *Home*: saludo con banner, anillo de colección, casillas de estado, "Start here", reinicios |
| `UI/MountPreview.lua` | Detalle de montura: modelo 3D (ModelScene), estado, dónde conseguirla (fuentes del dataset con estado por dificultad y Go, u "Other drops" con Map), logros, texto del diario |
| `UI/SettingsPanel.lua` | *Settings*: navegación, expansión máxima, minimapa, tamaño y posición de la ventana |
| `UI/CollectionPanel.lua` | *Collection*: lista virtualizada de todo el diario, buscador, filtros, vista por expansión (solo drops del dataset) |
| `UI/PlannerPanel.lua` | *Planner*: tabla de pasos (pools), reinicios, Clear marks, Mini window, *Full route | My route*, Hide done; switch *Group* a la derecha de la línea de progreso; clic en una montura abre su detalle con el 3D |
| `UI/PlannerMini.lua` | Ventana mini movible (`/aplan mini`): siguiente paso (viaje, instancia, monturas clicables con modelo 3D en un popup, Go, Done, Undo) y el paso de después. En la entrada o dentro: dificultad (con botón) y jefe de cada montura; dentro no muestra el viaje. Líneas de viaje con clic (botones seguros, ver §10). Posición y estado abierto en `db.ui.miniPoint` / `miniShown` |
| `UI/MainFrame.lua` | Ventana 720×500: cabecera de una línea (título › sección, personaje, ↻, ✕), barra lateral, sin pie. Escala en `db.ui.scale` |
| `Bootstrap.lua` | Se carga al final: eventos, comandos `/aplan` y `/animalitos`, AddonCompartment |

**Reglas de producto que no se rompen:**
- Lo desconocido **nunca** es Ready.
- La elegibilidad se evalúa **por fuente y por dificultad**.
- La colección es por cuenta; la elegibilidad, del personaje activo.
- Nada de datos de combate protegidos (Secret Values de Midnight); `ENCOUNTER_END`/`BOSS_KILL` solo disparan `RequestRaidInfo()`.
- El addon no hace llamadas de red.
- No se pisa un waypoint sin una acción explícita del jugador.

## 5. Conocimiento validado en el cliente (no lo re-descubras)
- `GetMountInfoByID` devuelve **13** valores; los 12 primeros siguen el orden documentado (`[10]` shouldHideOnChar, `[11]` isCollected, `[12]` mountID).
- `shouldHideOnChar` = true también en monturas **no obtenibles**, no solo de otra facción o clase. El contador del diario de Blizzard excluye las ocultas, por eso el addon muestra 372 y no 389.
- `GetMountInfoExtraByID`: el 3.º valor es `sourceText` con formato `|cFFFFD200Drop:|r … Location: …`; las monturas retiradas dicen `Legacy`.
- `sourceType` ↔ `_G["BATTLE_PET_SOURCE_"..n]` (1 Drop … 12 Trading Post; 0 = desconocido).
- **Encounter Journal:** después de `EJ_SetDifficulty`, el botín se reconstruye **de forma asíncrona**; hay que esperar unos 0,3 s antes de leer. `GetMountFromItem` devuelve nil si el objeto no está en caché: hay que pedirlo con `C_Item.RequestLoadItemDataByID` y releer.
- El EJ trae pseudoinstancias de world bosses (Pandaria 322, Draenor 557, Broken Isles 822, Invasion Points 959, Azeroth 1028, Shadowlands 1192, Dragon Isles 1205, Khaz Algar 1278, Midnight 1312), un tier "Current Season" duplicado y "Keystone Dungeons" 1319.
- `GetDungeonEntrancesForMap(uiMapID)` → `{areaPoiID, name, journalInstanceID, position}`. La misma entrada aparece cerca del borde de mapas vecinos; el pipeline elige la más alejada del borde.
- `GetSavedInstanceInfo` devuelve 14 valores: `[3]` segundos hasta el reset, `[4]` difficultyID, `[5]` locked, `[14]` **mapID de la instancia = `mapID` del EJ** (así se cruzan). `GetSavedInstanceEncounterInfo(i,j)` → `(bossName, fileDataID, isKilled, …)`.
- **Lockouts:**
  - Es por boss: estar guardado en la raid no bloquea a los bosses que siguen vivos.
  - En raids legacy, **10N/25N/10H/25H (dificultades 3–6) son UN solo lockout**. Validado: Ultraxion, muerto en DS 25H, seguía muerto en 25N. El juego solo registra la dificultad en la que se jugó, así que la regla está en `Eligibility.lua`.
  - Las dificultades flex (14/15/16) y las de mazmorra (1/2/23) tienen lockouts separados.
  - Las mazmorras heroicas legacy se reinician a diario.
- Waypoints: la flecha nativa y la de TomTom **solo se ven en el mismo continente** que el destino.
- En los textos de chat, `|t` inicia un código de textura: no escribas `native|tomtom`, usa `/`.

## 6. Dataset y pipeline
```
En el juego:  /aplan scan  (Guía de aventuras cerrada, fuera de combate, ~5–8 min)  →  /reload
python3 pipeline/build_dataset.py "/mnt/c/World of Warcraft/_retail_/WTF/Account/309771233#1/SavedVariables/AnimalitosPlanner.lua"
   → data/raw/scan-<build>.json         snapshot normalizado (se versiona)
   → AnimalitosPlanner/Data/Dataset.lua  generado
   → data/reports/dataset-report.md     huecos a curar
Sin el juego:  python3 pipeline/build_dataset.py --from-raw data/raw/scan-12.1.5.70783.json
```
- Las correcciones van en `data/curated/overrides.json`, **siempre con `reason`**: pseudoinstancias, `entranceOverrides`, `lockoutModels` y `currentExpansionTier`.
- **Huecos actuales:**
  - 5 instancias sin entrada: Throne of the Four Winds, Magisters' Terrace viejo (249, posiblemente reemplazado por la versión de Midnight 1300), Return to Karazhan, Ny'alotha y Stratholme Service Entrance.
  - 2 entradas dudosas: Vortex Pinnacle (Uldum, probablemente bien) y Nerub-ar Palace.
- **Drops curados** (`extraSources` en `overrides.json`): monturas de jefes que el EJ no lista (Bronze Drake, Smoldering Ember Wyrm, Aerial Unit R-21/X, los otros 3 jefes de Vault of Archavon). Verificados a mano en Wowhead y warcraft.wiki.gg; en el juego `FarmList:ResolveCurated` comprueba el mountID desde el objeto y busca el journalEncounterID por dungeonEncounterID. Jefes ocultos (`hiddenBoss`) quedan siempre en To verify. Un segundo `/aplan scan` (2026-11-06, otra cuenta) dio **los mismos drops** y menos entradas (170 contra 181), así que se mantuvo el scan anterior.
- Datos de terceros: **no importar** Rarity, SimpleArmory ni HandyNotes sin revisar su licencia (somos MIT). Wowhead solo para verificar a mano; nunca scraping.
- **Objetos de montura:** `/aplan scan items` (~1 minuto) recorre los IDs de objeto con `GetItemInfoInstant` (subclase Mount), los carga y los relaciona con `GetMountFromItem` → `AnimalitosPlannerDB.mountItems` → `data/raw/mountitems-<build>.json` → `ns.Data.mountItems[mountID] = itemID` (1 591 monturas). **Ojo:** pasar el archivo de SavedVariables al pipeline también reescribe `data/raw/scan-*.json` con el scan de esa cuenta; si es más viejo, restáuralo con `git checkout` y vuelve a generar con `--from-raw` (que toma el `mountitems-*.json` más reciente).
- `holidayBosses` (jefes de eventos con su lfgDungeonID) y `vendorRequirements` (requisitos que el tooltip no muestra; hoy: las 3 Armored Vorquin, Exalted con Obsidian Warders/Dark Talons salvo Dracthyr), `raidSkips` (misión de skip por dificultad 14/15/16 y jefe al que salta; 8 raids, IDs de warcraft.wiki.gg confirmados con `/aplan skips`) e `instanceDifficulties` (dificultades que una instancia tiene de verdad: Zul'Gurub y Zul'Aman solo Heroic, porque el diario devuelve botín también para la dificultad que no existe) también viven en `overrides.json`, con `reason`.
- `pipeline/savedvars.py` parsea SavedVariables. Ojo: el cliente escribe `nil,` como relleno en los arrays.

## 7. Ciclo de validación con el jugador
Claude no puede ejecutar el juego. Para validar algo:
1. Se agrega un diagnóstico (probe, scan, why, navdebug).
2. El jugador lo corre y hace `/reload`, que escribe las SavedVariables.
3. Se lee el archivo con `pipeline/savedvars.py`, o el jugador manda capturas.

Personajes de prueba: **Pennyus** (druida 90, con lockouts en FL H, ICC 25H, Ulduar N, UP H y DS 25H 5/8) y Aetana (sacerdote 82).

## 8. Convenciones
- Código, identificadores y comentarios del código en **inglés**; docs y conversación con el equipo en **español**.
- Textos del jugador siempre vía `ns.L["KEY"]`, con la clave agregada en `enUS.lua` **y** en `esES.lua`.
- Toda llamada nueva a una API de Blizzard va en un adaptador de `Integrations/`. Las listas no crean un frame por montura (se usan pools). Nada en `OnUpdate`.
- Al cambiar el esquema de SavedVariables: subir `SCHEMA_VERSION` y agregar `migrations[n]`; nunca editar una migración ya publicada.
- Subir `## Version` en el `.toc` en cada entrega. Los commits terminan con la línea `Co-Authored-By` de Claude.
- **UI:** todo widget sale de `UI/Style.lua`; nada de plantillas visuales de Blizzard (botones rojos, casillas, scroll) ni de arte externo. Solo texturas del cliente (arte del EJ, iconos) y las nuestras de `Media/`. Ojo con los nombres en `ns.UI`: los widgets (`UI.Switch`, `UI.Button`…) y los métodos de la ventana (`UI:Toggle`, `UI:Open`…) comparten tabla; un nombre repetido pisa al otro sin aviso (pasó con `Toggle`).
- **Texturas propias:** `python pipeline/gen_ui_textures.py` genera `Media/round-*.tga` (esquinas redondeadas, 9-slice) y `Media/nav-*.tga` (iconos planos: casa, herradura, libro, engranaje, ↻). Son arte original (MIT) y **sí** van al repo.
- **Ícono:** `AnimalitosPlanner/Media/icon.tga` está en `.gitignore` porque usa a Plim Plim (personaje con copyright) y fotos del equipo. **No lo subas al repo público.** Para regenerarlo: `python3 pipeline/png2tga.py C:\Users\User\Desktop\animalitos_caras.png` (128×128). Si algún día se publica en CurseForge, hace falta otro ícono.

## 9. Próximos pasos
1. **Flecha del waypoint nativo:** no se vio en Eastern Kingdoms. Pedir `/aplan navdebug` y revisar la opción `showInGameNavigation`, si `IsSuperTrackingUserWaypoint` está activo y la distancia de `C_Navigation`. Alternativa: `/aplan nav tomtom`.
2. Terminar la v0.4: reordenar la lista a mano (AC-09) y probar Ocultar y "Mostrar ocultas" entre reinicios del juego.
3. Curar los huecos del reporte (entradas) y validar la lista en esES/esMX.
4. Datos: validar Kraulok en el juego cuando esté en rotación (Ready con la misión activa, Locked al completarla, "Not this week" fuera de rotación). Rares: **no** replicar RareScanner (decisión del jugador): el addon dice qué rares faltan y en qué zona; RareScanner hace el resto.
5. Planner: Horda → Isle of Thunder sin coordenadas del portal Sunreaver; el norte de los Reinos del Este con Horda (Silvermoon, Tirisfal) cae en "Travel to …". Los casos no cubiertos dicen "Travel to …".
6. Preguntas abiertas: reparto de roles en el equipo, nombre público, publicar en CurseForge, en Wago o en ambos.

## 10. Rediseño de la UI (rama `josemaria`)
Hecho por Josemaria Vives con Claude, guiado por el vision board del producto (`01_Mount_Planner_Product_Vision_Board.png`, fuera del repo) y con **ideas** de EllesmereUI. EllesmereUI es "all rights reserved": no se copió código ni arte, solo técnicas (bordes de 1 px, jerarquía de texto por transparencia, línea de brillo, botones planos, títulos en mayúsculas).

**Decisiones:**
- Ventana 720×500; siempre abre en *Farmable now*; orden de la barra lateral Home → Farmable now → Planner → Collection → Settings.
- **Planner:** el orden de la ruta es fijo a propósito (pedido del jugador: si vas a Stormwind por los portales, la lista no puede reordenarse). Se calcula una vez por facción con todo el dataset: continentes en orden fijo (`ORDER`), y dentro de cada uno, vecino más cercano desde un hub fijo (`HUBS`). Lo hecho se marca o se oculta, sin mover el resto. Los textos de viaje vienen de tablas escritas a mano (`ZONE_PORTALS`, `CONTINENT_PORTALS`, `MAGE`); lo que no está cubierto cae en "Travel to …". Reglas de mago validadas: un teletransporte que deja en la zona de la instancia gana siempre (Theramore para Onyxia); un teletransporte lejano no gana a un portal de capital (Stormwind → Caverns of Time, no Theramore + vuelo); el mago usa el viaje gratis a la capital para tomar portales de zona (Uldum). Un portal que deja en el mapa padre (Tanaris) cuenta como llegada a la subzona (Caverns of Time). Orden de prioridad en `TravelTexts`: teletransporte de Mythic+ conocido ("Path of…", leído de los flyouts del libro de hechizos por su descripción) → zonas solo por portal (`ZONE_ACCESS`: Isle of Thunder vía Townlong Steppes 49.7, 68.7 para Alianza) → rutas por cadena (`CONTINENT_ROUTES`: Alianza → Zandalar por Durotar y barco de las Islas del Eco; Horda → Kul Tiras con el *Banshee's Wail* desde Zuldazar; Horda → sur de los Reinos del Este (Karazhan, Zul'Gurub) por Shattrath y el Portal Oscuro; Horda → Mechagon con el Capitán Krooz, en `ZONE_ACCESS`, que es por facción). Portales extra por facción en `FACTION_ZONE_PORTALS` (Orgrimmar → Caverns of Time). Entradas distintas por facción en `FarmList` `FACTION_ENTRANCES` (Battle of Dazar'alor: la Horda entra en Dazar'alor 38.8, 2.4; la Alianza en Boralus) → teletransporte de mago a la zona → portales de zona/continente de la capital, teletransporte de mago al continente o `TRAVEL_ITEMS` (Dalaran y Garrison Hearthstone) → "Fly to".
- **World bosses:** el EJ los agrupa en pseudoinstancias por continente; el pipeline crea una entrada por jefe con clave `-journalEncounterID` (`ejInstance`, `encounter`, dificultad única `0` = semanal). La posición se toma en el juego del pin del EJ (`C_EncounterJournal.GetEncountersOnMap`); el kill semanal, de `GetSavedWorldBossInfo` (comparando el nombre del encuentro y de sus criaturas: Galleon se guarda como "Galleon", validado). Solo `worldBossLockouts = savedWorldBoss` o `worldQuest` puede ser Ready. `worldQuest` (BfA, Kraulok): el jefe rota cada semana y lo marca una misión de mundo épica con su nombre; `Lockouts:WorldQuestBoss` la busca por nombre en el mapa del jefe, guarda su ID en `AnimalitosPlannerDB.worldQuests` (la misión completada sale del mapa) y lee completada → Locked, activa → Ready, inactiva → Unavailable "Not this week", nunca vista → To verify. En el Planner son opcionales ("Include world bosses", apagado por defecto).
- **Logros:** se leen del cliente al vuelo, no van al dataset. Se construyen en una corrutina con `C_Timer.After(0)` (~6 ms por frame) porque recorrer todos los logros en un frame congelaba la pantalla. El enlace logro → instancia compara cada criterio pendiente (y el nombre/descripción del sublogro) con los nombres de jefes del EJ; es solo una pista.
- **Datos de terceros revisados:** Mount Route Planner (Data) y RareScanner son "All Rights Reserved": no se usan ni se abren sus datos.
- Fuentes del cliente: Friz Quadrata para títulos y números, Arial Narrow para el texto.
- Horas con el mismo reloj que el minimapa (`Lockouts:FormatClock`: hora del reino o local y 12/24 h según la opción del jugador). `date()` solo usa la zona horaria de Windows y salía desfasado.
- Botón del minimapa: **LibDataBroker no tiene licencia**, así que no se incluye; LibDBIcon (BSD) tampoco, para no depender de LDB. El botón aparece solo si otro addon ya cargó ambas.
- El buscador de *Farmable now* solo redibuja con el último `FarmList:Build()`; no recalcula por tecla.
- *Farmable now* sin números en el arte de las tarjetas; "Show hidden" va arriba de la lista (pedido del jugador).
- **Planner:** un solo botón "Clear marks" (los tres Reset solo quitaban marcas manuales, que igual caducan en el reinicio). **Ventana mini** (`Planner:Upcoming`): los dos siguientes pasos pendientes con el viaje desde donde terminó el paso anterior; "Done" marca a mano y "Undo" (hoy *Back*) deshace (pila de la sesión). El tiempo estimado de toda la ruta solo sale en el Planner ("~X to finish the route (estimate)"); en la mini se quitó en v0.28.3 porque no se entendía. El popup 3D (`MountPreview:TogglePopup`) no depende de la ventana principal.

**Entorno de Josemaria (Windows):** repo en `C:\Users\Josemaria Vives\animalitos_addon`, junction `AddOns\AnimalitosPlanner` → `<repo>\AnimalitosPlanner`. Python 3.13 se llama con `python` (no `python3`). En PowerShell 5.1:
- mensajes de commit de varias líneas: escribir a un archivo y usar `git commit -F`;
- no usar `Get-Content`/`Set-Content` para reescribir el `.toc` u otros archivos con acentos: los lee como ANSI y los guarda con BOM. Usar `[System.IO.File]::ReadAllText/WriteAllText` con UTF-8 sin BOM.

**Decisiones v0.13–0.25 (con el jugador):**
- Ideas de producto elegidas: 3 (eventos de temporada), 8 (vendedor) y 4 (ayuda de instancia). La 1 (lockouts de alts) se descartó: casi todas las monturas son de cuenta.
- **Favoritos** propios del addon (`db.favorites`): los del diario de Blizzard solo sirven para monturas ya conseguidas.
- **Vendedor:** el jugador descartó primero "puedes pagarla" porque dependía de reputación que no se leía; quedó *requisitos + precio*. Lo que el juego no dice en ningún lado va a `vendorRequirements` a mano; si una montura sale en *Ready to buy* y el vendedor no la vende, se agrega ahí. Nombre de la lista: *Ready to buy* / *Listas para comprar* (el jugador rechazó "Vendor: nothing missing").
- **Viaje con clic:** los hechizos solo se lanzan desde `SecureActionButtonTemplate`. Los botones viven en `UIParent` y se colocan por **coordenadas de pantalla** sobre la línea; anclarlos al texto de la mini rompió la ventana. Se ocultan en `PLAYER_REGEN_DISABLED` (todavía se permite ahí) y vuelven al salir de combate. Teletransportes con el mismo nombre en Alianza y Horda (Shattrath, Tol Barad, Valle) se resuelven con `KnowsSpell`; un mago en grupo lanza el portal (tabla `PORTAL` en `Planner.lua`).
- **Rendimiento:** `FarmList:Build()` se reutiliza dentro del mismo frame; `UPDATE_INSTANCE_INFO` y los eventos del buscador solo redibujan si cambió algo. Ojo con `("%d"):format` y valores grandes (precios en cobre pasan de 2^31): usa `%s`.
- **Skips de raid** (v0.25): lista curada, porque el juego no dice qué misión es el skip de qué raid. Nota *Skip to <jefe>* ✓/✗ en el paso (Planner y mini). Sin Tomb of Sargeras, Siege of Orgrimmar, Battle of Dazar'alor (su skip no llega al jefe de la montura, sin comprobar) ni las raids recientes (Nerub-ar, Undermine, Manaforge).
- **Vuelta a la capital** (v0.25.4): teleport de mago; piedra de hogar solo si `GetBindLocation()` es la capital; si no, portal de la ciudad principal del continente (Silvermoon, Dornogal, Valdrakken, Oribos…); si no, piedra a una de esas ciudades. El jugador eligió que la tabla del Planner también lo use, aunque alargue la ruta.
- **Mini dentro de una instancia:** la montura cuyo jefe ya murió en esta run sale en gris con ✓ (lockout de la dificultad en que estás; otra dificultad sin lockout la deja *Ready* en general). Zul'Gurub y Zul'Aman solo existen en Heroic (`instanceDifficulties`). Dentro de una instancia del dataset, el viaje de la mini parte de su entrada.

**Decisiones v0.26 (con el jugador):**
- **Ruta de grupo:** el jugador eligió la opción A, la *unión*: entra todo paso que le sirva a alguien, y cada paso dice a quién. Mismo orden para todos (facción y reglas de viaje del líder) y avance sincronizado desde el líder. Partes 1–3 hechas en v0.27.0. **Visto en juego (2026-11-08):** presencia y unión de pasos con "Group: <nombre> ✓"; falta confirmar que el *Done* del líder llegue al otro. `Comm.lua`: `HELLO`/`HI` (presencia), `NEED` (por instancia, monturas *ready* y *locked* de cada uno) y `DONE` (pasos hechos del líder), en piezas numeradas de 200 bytes. Switch *Group* en el Planner (solo si alguien más tiene el addon): unión de pasos en el orden de la facción del líder (`Route(fac)`), los viajes siguen siendo de la facción propia; cada paso dice *Grupo: Tú ✓ · Ana (bloqueado)*; un paso que solo otro necesita usa una entrada de relleno (`peerOnly`); el paso queda hecho si el líder lo marcó (o por tus propios lockouts/marcas).
- **Regla del mago:** "si con portal es más fácil, siempre portal". En el mismo continente se compara volar directo con cada teleport, y con teleport a la capital + uno de sus portales, por distancia real en el mapa (`C_Map.GetWorldPosFromMapPos`) más `HOP_COST` por salto. Solo gana si queda en menos de la mitad (Dalaran → Ulduar sigue volando). Si el paso empieza dentro de una instancia se suma `EXIT_COST` y basta con el 85 % (salir de Return to Karazhan es lento).
- **Clicables:** un jugador nuevo no sabía que el teleport se podía pulsar. Todo lo clicable debe *verse* clicable con `UI.Clickable`: contorno de 1 px del color de acento y relleno al pasar el mouse (el jugador rechazó el fondo morado con cursor). En la mini, los botones seguros se colocan **después** de fijar la altura de la ventana (está anclada por el centro; si no, quedan media línea corridos) y miden lo que el texto. Los logros del Planner llevan ícono, `>` y abren el logro (`ns.Achievements:Open` carga `Blizzard_AchievementUI`).
- **Monturas en orden de jefe** (orden de la Guía de aventuras, `FarmList:BossOrder`), no alfabético. *Undo* se llama *Back*.
- **Entradas que el scan no trae** (no hay marca en el mapa): Return to Karazhan (la puerta de Karazhan), Throne of the Four Winds (Uldum 38.5, 80.5), Ny'alotha (solo la de Uldum, 54 43, elección del jugador) y Stratholme Service Entrance (43, 18). Magisters' Terrace de Burning Crusade queda sin entrada: no está claro si se puede entrar tras Midnight.
- **Quel'Thalas** (Midnight, continente `2537`) es otro mapa de continente, pero está unido por tierra a Eastern Kingdoms: `FLY_ACROSS` en `Planner.lua` hace que entre Quel'Thalas y Eastern/Western Plaguelands se vuele, y que desde otro continente se llegue primero a Silvermoon (*Teleport: Silvermoon City* 1259190 / portal 1259200, ambas facciones, o el portal de la capital) y de ahí se vuele.
- **My route** (v0.28.0, opción B del jugador): lista propia de monturas (`db.myRoute`, de cuenta, aparte de favoritos), botón de ruta de vuelo (`UI.RouteToggle`) en el detalle de la montura y en las filas de Collection; solo para monturas que caen en una instancia del dataset. El Planner tiene *Full route | My route (n)*; en *My route* cada entrada se recorta a las monturas elegidas (`routeOnly`), así *hecho* y la lista de monturas solo miran esas. Orden automático, igual que la ruta completa (el jugador descartó el orden manual por ahora). **Grupo encima de cualquiera de las dos** (v0.28.2, elección del jugador): fila *[Full route | My route (n)]  Hide done [o]*, y el switch *Group* a la derecha de la línea de progreso, donde estaba *Next step* (v0.28.3: el jugador dijo que no sumaba; la mini ya no muestra el tiempo estimado, que no se entendía); el switch *Group* solo aparece con alguien más con el addon. Cada jugador comparte (`NEED`) la ruta que eligió: en *My route* solo las monturas elegidas; se reenvía al cambiar de modo o de lista. La ruta de grupo es la unión.
- **Ruta de grupo, arreglos v0.28.4** (probado con un amigo el 2026-11-08): (1) cada jugador filtra lo que comparte con *su* **Show:** y su modo (`Planner:OwnStep`); la unión no se vuelve a filtrar, así los dos ven los mismos pasos (Nalak salía solo al que tenía world bosses). **v0.29.1:** los world bosses tienen jid **negativo** (`-814` = Nalak) y `NEED` solo mandaba jids > 0: ahora se mandan y se leen con signo. (2) En grupo con un mago no se usan teleports personales de Mythic+ (*Path of…*): el jugador pidió portal siempre, aunque alguien tenga el teleport directo. (3) El líder no tenía **Set H** en un paso que solo necesitaba el otro: las dificultades del otro (`groupDiffs`, de las fuentes del dataset) cuentan para `Difficulty:Pick/Drops`, y la entrada de relleno trae `near` (`FarmList:Near`).
- **Ruta de grupo v0.30.0** (pedido del jugador: "que todos veamos lo mismo, que se fusionen las listas" y saber quién tiene CD y quién tiene la montura; eligió la vista A, una línea por jugador). Mensaje nuevo `STAT` (reemplaza `NEED`; números en base 36): por instancia, `pick` (monturas de su ruta, tras su modo y su **Show:**), `ready/locked/other` (**todas** las monturas del dataset que le faltan ahí) y `cd` (dificultades con lockout, aunque ya tenga la montura). Montura del paso en ninguna lista = la tiene. Paso = unión de los `pick` (`groupEntry`); filas por jugador (`groupRows`) dibujadas en la nota del paso. Hecho: con un líder con el addon decide el líder (más las marcas a mano); desde v0.30.1 (el jugador marcó Done sin ser líder y al otro no le llegó) cada *Done*/deshacer manual se manda como `MARK<TAB>jid<TAB>1|0` y quien tenga Group activo lo aplica a sus propias marcas, sin reenviarlo; v0.30.2: el portal de mago en grupo se busca también por nombre en el libro de hechizos (`Navigation:PortalLike`, "Teleport: X" -> "Portal: X"), porque el ID fijo de Portal: Silvermoon no lo reconocía; y el mini avisa (`MINI_DIFF_PARTIAL`, `Difficulty:Best`) si dentro de la instancia caen menos monturas que en otra dificultad (Dragon Soul 10N: 2 de 3, Heroic las 3); auto-hecho solo si nadie puede lootear y alguien lo mató. Las piezas salen por una cola: 6 de golpe y luego cada 1,2 s (el cliente descarta mensajes de addon tras una ráfaga).
- **Collection ordenable** (v0.29.0, opción A del jugador, "tipo Excel"): encabezados clicables sobre la lista (*Mount / Source / Status*; en *Achievements*: *Achievement / Mount / Status*; en *Other drops*: *Mount / Dropped by / Status*), alineados con las columnas de la fila. Otro clic invierte; empates de A a Z. `db.ui.collectionSort = { key, desc }`. Flecha: `Interface\Buttons\UI-SortArrow`.
- **Nombres de jefe en lockouts:** el lockout puede llamar distinto al jefe que la Guía (*Lord Harlan Sweete* / *Harlan Sweete*). `Lockouts:IsKilled` compara exacto y luego uno contenido en el otro.
- **Lua:** `obj:Metodo and ...` es error de sintaxis (un método con `:` hay que llamarlo); para comprobar si existe, `obj.Metodo`. Un error así tumba el archivo entero (v0.27.2 dejó sin mini ni `/aplan`). El conteo de bloques no lo detecta.

**Pendiente:** probar en el cliente lo que dice *Por probar* en la tabla de estado (la mayoría necesita a otro jugador); confirmar si Magisters' Terrace de Burning Crusade se puede entrar; abrir el PR `main...josemaria` cuando el jugador lo pida; probar los textos en esES/esMX.
