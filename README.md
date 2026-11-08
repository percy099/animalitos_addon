# AnimalitosPlanner

Addon de World of Warcraft retail (12.1.5) para **farmear monturas**. Te dice:
- qué raids y mazmorras legacy puedes hacer **ahora** con tu personaje para conseguir monturas que le faltan a tu cuenta;
- qué ya hiciste esta semana y cuándo se reinicia;
- te pone un waypoint en la entrada y la dificultad correcta;
- y te avisa de los jefes de eventos de temporada y de las monturas de vendedor que ya puedes comprar.

Estado: **v0.29.0** (en desarrollo, rama `josemaria`). Ver [docs/05-mvp-y-roadmap.md](docs/05-mvp-y-roadmap.md).

## Probar esta versión (si te la pasaron)
La versión en prueba está en la rama **`josemaria`**, no en `main`.

1. **Descárgala**, de una de estas dos formas:
   - **Enlace directo (lo más fácil):** <https://github.com/percy099/animalitos_addon/archive/refs/heads/josemaria.zip>. Siempre baja la última versión.
   - Con git: `git clone -b josemaria https://github.com/percy099/animalitos_addon.git`
   - Ojo: el botón **Code → Download ZIP** de la página principal baja `main`, que está desactualizada. Si lo usas, antes cambia la rama a `josemaria`.
2. **Descomprime y cierra WoW.** Dentro del zip hay una carpeta `animalitos_addon-josemaria`; copia **solo** la carpeta `AnimalitosPlanner` que está adentro en `World of Warcraft\_retail_\Interface\AddOns\` (debe quedar `AddOns\AnimalitosPlanner\AnimalitosPlanner.toc`). Si ya tenías una versión anterior, bórrala y pon esta.
3. **Abre WoW.** En el chat debe salir `AnimalitosPlanner: v0.29.0 loaded`. Escribe `/aplan`.
4. **Para ver errores:** `/console scriptErrors 1` y `/reload`. Si sale un error de Lua, manda captura del primero.
5. **Para actualizar** más adelante: `git pull` (o vuelve a bajar el zip del enlace directo), copia la carpeta otra vez y **reinicia el juego** (si solo cambió código ya cargado, basta `/reload`; si hay archivos nuevos, no).

El ícono del addon no viene en el repo (ver *Instalación*); sin él funciona igual.

**Si usas Claude Code:** abre el repo y pídele que lea `CLAUDE.md`; ahí está todo el contexto (estado, decisiones y qué falta probar).

### Qué falta probar
| Qué | Cómo |
|---|---|
| **Ordenar Collection** (v0.29.0) | En Collection, clic en *Mount*, *Source* o *Status* sobre la lista: ordena por esa columna (flecha); otro clic invierte. También en las vistas *Achievements* y *Other drops*. |
| **My route** (v0.28.0) | Clic en una montura que te falte → botón de **ruta de vuelo** junto a la estrella (también en las filas de Collection). Agrega 3–4. En **Planner** elige **My route (n)**: solo deben salir esas, en orden lógico; la mini sigue el mismo modo. |
| **Ruta de grupo** (dos personas con esta versión, en grupo) | `/aplan group` en los dos: cada uno debe ver al otro. En el Planner aparece el switch **Group** (a la derecha, en la línea de progreso): actívenlo. *Ya visto funcionando: presencia y pasos del otro.* Cada uno comparte la ruta que tenga elegida (*Full route* o *My route*, con su propio filtro **Show:**), así los dos ven los mismos pasos; con un mago en el grupo se viaja con su portal, no con teleports personales (*Path of…*); el líder tiene **Set H** aunque el paso solo le sirva al otro; la ruta junta los pasos de los dos (orden de la facción del líder) y cada paso dice *Group: You ✓ · Nombre (locked)*. **Falta confirmar:** si el líder marca **Done**, al otro se le marca en unos segundos. |
| **Mago en grupo** | Con un mago en el grupo, los pasos de viaje dicen qué portal pedirle; si el mago tiene el addon, la línea de la mini abre el portal. |
| **Atajos de mago** (un mago sin Invincible) | De ICC a Utgarde Pinnacle pasando por Dalaran; al salir de Return to Karazhan, teleport y volar a Zul'Gurub. |
| **Tamaño 10/25** (falta una montura de un solo tamaño) | Obsidian Sanctum, Karazhan (Attumen) o The Eye (Kael'thas): en la entrada, el botón de dificultad debe poner el tamaño correcto. |

Cuando algo no cuadre: captura, y si es de una montura, `/aplan why <montura>`.
## Instalación
1. Copia (o enlaza) la carpeta `AnimalitosPlanner/` en `World of Warcraft\_retail_\Interface\AddOns\`.
2. **El ícono no está en el repo** (es arte local). Pídeselo al equipo y ponlo en `AnimalitosPlanner\Media\icon.tga`, o genera uno desde cualquier PNG:
   ```
   python3 pipeline/png2tga.py ruta/a/imagen.png
   ```
   Sin ícono, el addon funciona igual; solo el logo queda vacío.
3. Reinicia el juego: un addon nuevo no se detecta con `/reload`.

### Para desarrollar (Windows)
Enlaza la carpeta en lugar de copiarla; así los cambios se ven con `/reload`:
```
mklink /J "C:\World of Warcraft\_retail_\Interface\AddOns\AnimalitosPlanner" "<ruta al repo>\AnimalitosPlanner"
```
Archivos nuevos (`.lua` o texturas) solo se cargan al **reiniciar el juego**. Para ver errores de Lua: `/console scriptErrors 1`.

### Botón del minimapa (opcional)
Usa **LibDBIcon** y **LibDataBroker** si otro addon ya los carga (casi todos los populares lo hacen). No vienen incluidas en el repo; si no están, el botón no aparece, pero el addon sigue disponible desde `/aplan` y el menú de addons del minimapa.

## Uso
### La ventana
Se abre con `/aplan`, con el **botón del minimapa** o desde el **menú de addons del minimapa**. Clic izquierdo en el botón abre o cierra la ventana; clic derecho la abre en Home. Siempre empieza en *Farmable now*.

| Sección | Qué muestra |
|---|---|
| **Home** | Saludo con tu personaje, anillo de progreso de la colección, casillas *Missing / Farmable now / Locked out / To verify*, las 5 primeras instancias recomendadas ("Start here") y los próximos reinicios diario y semanal. El botón **Update lockouts** vuelve a pedir tus lockouts al servidor. |
| **Farmable now** | Arriba, los **jefes de eventos de temporada** activos (Headless Horseman, Coren Direbrew, Crown Chemical Co.) con el botón **Queue**, que abre el buscador de mazmorras. Debajo, instancias agrupadas por continente (primero donde estás), cada una con su arte, sus monturas y los botones **Go** (waypoint) y **Hide** (ocultar hasta el reinicio). Si la dificultad en la que caen las monturas no está puesta, aparece **Set 25H** (o la que toque) para ponerla antes de entrar, solo o como líder del grupo. **Buscador** arriba: filtra por montura, instancia, zona o continente mientras escribes; ESC lo borra. Clic en una montura abre la **vista previa** con el modelo 3D y el botón para abrirla en el diario de monturas. |
| **Planner** | Ruta paso a paso por todas las instancias con monturas que te faltan, al estilo del planner de SimpleArmory: *Done · # · Step · Boss · Mount*. **El orden es fijo**: se calcula con todo el dataset (continentes en orden fijo desde tu capital y un recorrido geográfico fijo dentro de cada uno), nunca con tu posición, así que no se reordena mientras viajas. Los pasos de viaje dicen cómo llegar ("Portal to Uldum", "Hearthstone to Stormwind, then Portal to Caverns of Time", "Fly to Dustwallow Marsh"). **Full route | My route** elige entre la ruta completa y **tu ruta**: solo las monturas que agregaste con el botón de ruta de vuelo (en el detalle de cada montura y en Collection), en el mismo orden automático. El menú **Show:** elige qué entra en la ruta: raids, mazmorras, **world bosses** (Sha of Anger, Galleon, Nalak, Oondasta, Rukhmar…) y *solo favoritos*. En grupo con alguien que tenga el addon aparece el switch **Group**: una ruta común con lo que cada uno eligió (su ruta completa o su *My route*), en el orden del líder, que avanza cuando el líder marca un paso. Los jefes de eventos de temporada activos van primero, con **Queue**. Si un logro de montura tiene criterios en una instancia, el paso lo dice. Usa tus teletransportes de **Mythic+** ("Path of…"), la **Dalaran/Garrison Hearthstone** si las tienes, y rutas especiales por facción (Isle of Thunder por el portal de Townlong Steppes; Alianza a Zandalar en barco; Horda a Kul Tiras en el *Banshee's Wail*, a Mechagon con el Capitán Krooz y a Karazhan por el Portal Oscuro). Con **Mini window** (o `/aplan mini`) tienes una ventana pequeña y movible con el siguiente paso, cómo llegar, sus monturas (clic: modelo 3D), **Go**, **Done** y **Back**, y el paso de después. Las líneas que se pueden pulsar tienen un contorno. En la mini, **las líneas de viaje que puedes hacer tú se pulsan**: teletransporte de mago (en grupo, el portal), *Path of…*, Hearthstone, Dalaran/Garrison Hearthstone. En la entrada o dentro de la instancia, la mini dice en qué dificultad caen las monturas (con botón para ponerla) y qué jefe suelta cada una; dentro ya no muestra el viaje, y la montura cuyo jefe ya mataste en esta run queda en gris con ✓. Si eres **mago** usa tus teletransportes, y si hay un mago en el grupo te dice a quién pedirle el portal. Las casillas se marcan solas con el lockout o a mano hasta el reinicio (por personaje); **Clear marks**, **Hide done** (la mini lo sigue también), y el tiempo estimado para terminar la ruta (cada paso tiene su **Go**). |
| **Collection** | Todas las monturas del diario en una lista con buscador, filtro *All / Missing / Collected / ★* (favoritos del addon: la estrella en cada fila y en el detalle; al lado, el botón de ruta de vuelo agrega la montura a *My route*) y el menú **View:** con las vistas. **Encabezados para ordenar**, como en Excel: *Mount*, *Source* y *Status* (primero *Farmable now*, luego *Missing*, luego *Collected*); otro clic invierte el orden y se recuerda entre sesiones. En el menú de fuente, **Ready to buy** lista las monturas de vendedor que te faltan y cuyo precio y requisitos cumples. Las farmeables ahora se marcan en verde. La vista **Boss drops** agrupa por expansión las monturas de jefes del dataset (raids, mazmorras y world bosses); clic en una expansión filtra la lista. La vista **Achievements** lista todos los logros con montura de recompensa y tu progreso (clic: detalle de la montura; clic derecho: ventana de logros). La vista **Other drops** muestra las monturas de rares, trash y botín del mundo con quién la suelta y la zona, según el diario. Clic en cualquier montura abre su **detalle**: modelo 3D, estado, dónde conseguirla dificultad por dificultad (con **Go** o **Map**), **requisitos y precio del vendedor** (reputación, renombre, facción, clase, logro, oro y monedas: ✓ / ✗ / ?), logros y el texto del diario. |
| **Settings** | Waypoint de Blizzard o flecha de TomTom, hasta qué expansión entra en la lista, botón del minimapa, tamaño de la ventana (80–130 %) y restablecer posición. |

El botón **↻** de la cabecera vuelve a escanear la colección y los lockouts.

### Comandos
| Comando | Qué hace |
|---|---|
| `/aplan` (o `/animalitos`) | Abre o cierra la ventana |
| `/aplan now` | Muestra la lista "farmeable ahora" en el chat |
| `/aplan go <n>` | Pone un waypoint en la entrada de la instancia número *n* de la lista |
| `/aplan why <montura>` | Explica, dificultad por dificultad, por qué una montura está o no disponible |
| `/aplan nav native` · `/aplan nav tomtom` | Elige entre el waypoint nativo de Blizzard y la flecha de TomTom |
| `/aplan maxtier <n>` | Define hasta qué expansión entra en la lista (por defecto 10 = Dragonflight) |
| `/aplan navdebug` | Diagnóstico para cuando no se ve el waypoint |
| `/aplan mini` | Abre o cierra la ventana mini del Planner |
| `/aplan events` · `/aplan events test` | Estado de los jefes de eventos; `test` los simula activos (solo la sesión) |
| `/aplan group` | Quién del grupo tiene el addon (versión, facción, si es líder, cuántos pasos necesita y cuántos marcó hechos) y el estado del canal |
| `/aplan skips` | Misiones de skip de raid: título en tu cliente y si están hechas |
| `/aplan probe` · `/aplan scan` · `/aplan scan items` · `/aplan curated` · `/aplan unknown` | Herramientas de desarrollo (ver CLAUDE.md) |

## Estructura del repo
```
AnimalitosPlanner/   el addon (lo que se instala)
pipeline/            scripts Python: parser de SavedVariables, generador del dataset, conversor de ícono,
                     generador de texturas de la UI (gen_ui_textures.py)
data/                snapshot del scan, correcciones curadas y reporte de huecos
docs/                documentación de producto y técnica (v1.2, en español)
CLAUDE.md            contexto completo para quien continúe el proyecto (personas o Claude)
```

Licencia: [MIT](LICENSE).
