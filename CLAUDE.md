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
| Rediseño de la UI (rama `josemaria`, v0.4.7–0.6.5) | 🟡 validado en el cliente; pendiente revisar y fusionar con un PR (ver §10) |
| v0.5 Colección virtualizada, Detalle de montura | 🟡 Colección hecha en la rama `josemaria` (lista, filtros, vista por expansión); falta el Detalle de montura |
| Planner (rama `josemaria`, v0.6.0–0.6.5) | ✅ validado en el cliente, también con mago |
| v0.6 Cobertura legacy completa y curación | ⏳ |
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
| `Integrations/Lockouts.lua` | Instancias guardadas → `byMap[instanceMapID][difficultyID] = { killed[bossName], resetAt }` |
| `Modules/Collection.lua` | Totales; el número principal coincide con el diario de Blizzard (visibles para el personaje) |
| `Modules/Eligibility.lua` | Estado por (fuente, dificultad): `ready`, `lockedOut`, `verificationRequired`, `unavailable`, `collected`, `outOfScope` |
| `Modules/FarmList.lua` | Agrupa por instancia, ordena (zona actual → continente → número de monturas → expansión) y oculta hasta el reset |
| `Modules/Planner.lua` | Ruta **estática** del planner (orden fijo por facción, nunca por posición), pasos de viaje (portales de capital, portales de zona de Cata, teletransportes de mago, mago en el grupo), marcas manuales por personaje hasta el reset |
| `Integrations/Navigation.lua` | Waypoint nativo (`C_Map.SetUserWaypoint` + `C_SuperTrack`) o TomTom; aviso si el destino está en otro continente; `Debug()` |
| `Integrations/MinimapButton.lua` | Botón del minimapa vía LibDBIcon + LibDataBroker **si otro addon ya los carga** (dependencia blanda, no se incluyen; ver §10) |
| `Modules/Probe.lua` | `/aplan probe`: firmas de API, EJ, mapa, lockouts y TomTom → `AnimalitosPlannerDB.diagnostics` |
| `Modules/DevScan.lua` | `/aplan scan`: construye el dataset en bruto desde el cliente → `AnimalitosPlannerDB.scan` |
| `UI/Style.lua` | Sistema visual compartido (`ns.UI`): paleta, fuentes, paneles redondeados, botones, interruptor (`UI.Switch`), slider, scroll fino, buscador, círculos, recorte del arte del EJ. Se carga antes que los paneles |
| `UI/FarmPanel.lua` | *Farmable now*: buscador, grupos por continente, tarjetas con arte, secciones "Locked out" / "Needs verification" (pools) |
| `UI/HomePanel.lua` | *Home*: saludo con banner, anillo de colección, casillas de estado, "Start here", reinicios |
| `UI/MountPreview.lua` | Panel lateral con el modelo 3D (ModelScene, como el diario) y "Open in Mount Journal" |
| `UI/SettingsPanel.lua` | *Settings*: navegación, expansión máxima, minimapa, tamaño y posición de la ventana |
| `UI/CollectionPanel.lua` | *Collection*: lista virtualizada de todo el diario, buscador, filtros, vista por expansión (solo drops del dataset) |
| `UI/PlannerPanel.lua` | *Planner*: tabla de pasos (pools), reinicios, Reset all/dungeons/raids, Hide completed, Next step |
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
- Datos de terceros: **no importar** Rarity, SimpleArmory ni HandyNotes sin revisar su licencia (somos MIT). Wowhead solo para verificar a mano; nunca scraping.
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
4. v0.5: falta el Detalle de montura (fuentes y explicación por dificultad, como `/aplan why`); la Colección ya está en la rama `josemaria`.
5. Planner: más portales escritos a mano (Horda, Kul Tiras/Zandalar, Shadowlands, druidas, Dalaran Hearthstone, juguetes de teletransporte). Los casos no cubiertos dicen "Travel to …".
6. Preguntas abiertas: reparto de roles en el equipo, nombre público, publicar en CurseForge, en Wago o en ambos.

## 10. Rediseño de la UI (rama `josemaria`)
Hecho por Josemaria Vives con Claude, guiado por el vision board del producto (`01_Mount_Planner_Product_Vision_Board.png`, fuera del repo) y con **ideas** de EllesmereUI. EllesmereUI es "all rights reserved": no se copió código ni arte, solo técnicas (bordes de 1 px, jerarquía de texto por transparencia, línea de brillo, botones planos, títulos en mayúsculas).

**Decisiones:**
- Ventana 720×500; siempre abre en *Farmable now*; orden de la barra lateral Home → Farmable now → Planner → Collection → Settings.
- **Planner:** el orden de la ruta es fijo a propósito (pedido del jugador: si vas a Stormwind por los portales, la lista no puede reordenarse). Se calcula una vez por facción con todo el dataset: continentes en orden fijo (`ORDER`), y dentro de cada uno, vecino más cercano desde un hub fijo (`HUBS`). Lo hecho se marca o se oculta, sin mover el resto. Los textos de viaje vienen de tablas escritas a mano (`ZONE_PORTALS`, `CONTINENT_PORTALS`, `MAGE`); lo que no está cubierto cae en "Travel to …". Reglas de mago validadas: un teletransporte que deja en la zona de la instancia gana siempre (Theramore para Onyxia); un teletransporte lejano no gana a un portal de capital (Stormwind → Caverns of Time, no Theramore + vuelo); el mago usa el viaje gratis a la capital para tomar portales de zona (Uldum). Un portal que deja en el mapa padre (Tanaris) cuenta como llegada a la subzona (Caverns of Time).
- Fuentes del cliente: Friz Quadrata para títulos y números, Arial Narrow para el texto.
- Horas con el mismo reloj que el minimapa (`Lockouts:FormatClock`: hora del reino o local y 12/24 h según la opción del jugador). `date()` solo usa la zona horaria de Windows y salía desfasado.
- Botón del minimapa: **LibDataBroker no tiene licencia**, así que no se incluye; LibDBIcon (BSD) tampoco, para no depender de LDB. El botón aparece solo si otro addon ya cargó ambas.
- El buscador de *Farmable now* solo redibuja con el último `FarmList:Build()`; no recalcula por tecla.

**Entorno de Josemaria (Windows):** repo en `C:\Users\Josemaria Vives\animalitos_addon`, junction `AddOns\AnimalitosPlanner` → `<repo>\AnimalitosPlanner`. Python 3.13 se llama con `python` (no `python3`). En PowerShell 5.1:
- mensajes de commit de varias líneas: escribir a un archivo y usar `git commit -F`;
- no usar `Get-Content`/`Set-Content` para reescribir el `.toc` u otros archivos con acentos: los lee como ANSI y los guarda con BOM. Usar `[System.IO.File]::ReadAllText/WriteAllText` con UTF-8 sin BOM.

**Pendiente:** abrir el PR `main...josemaria` y que el equipo lo revise; probar los textos en esES/esMX.
