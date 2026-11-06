# AnimalitosPlanner

Addon de World of Warcraft retail (12.1.5) para **farmear monturas**. Te dice:
- qué raids y mazmorras legacy puedes hacer **ahora** con tu personaje para conseguir monturas que le faltan a tu cuenta;
- qué ya hiciste esta semana y cuándo se reinicia;
- y te pone un waypoint en la entrada.

Estado: **v0.4** (en desarrollo). Ver [docs/05-mvp-y-roadmap.md](docs/05-mvp-y-roadmap.md).

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
| **Farmable now** | Instancias agrupadas por continente (primero donde estás), cada una con su arte, sus monturas y los botones **Go** (waypoint) y **Hide** (ocultar hasta el reinicio). **Buscador** arriba: filtra por montura, instancia, zona o continente mientras escribes; ESC lo borra. Clic en una montura abre la **vista previa** con el modelo 3D y el botón para abrirla en el diario de monturas. |
| **Planner** | Ruta paso a paso por todas las instancias con monturas que te faltan, al estilo del planner de SimpleArmory: *Done · # · Step · Boss · Mount*. **El orden es fijo**: se calcula con todo el dataset (continentes en orden fijo desde tu capital y un recorrido geográfico fijo dentro de cada uno), nunca con tu posición, así que no se reordena mientras viajas. Los pasos de viaje dicen cómo llegar ("Portal to Uldum", "Hearthstone to Stormwind, then Portal to Caverns of Time", "Fly to Dustwallow Marsh"). Los **world bosses** (Sha of Anger, Galleon, Nalak, Oondasta, Rukhmar) se agregan con *Include world bosses*. Si un logro de montura tiene criterios en una instancia, el paso lo dice. Usa tus teletransportes de **Mythic+** ("Path of…"), la **Dalaran/Garrison Hearthstone** si las tienes, y rutas especiales por facción (Isle of Thunder por el portal de Townlong Steppes; Alianza a Zandalar en barco; Horda a Kul Tiras en el *Banshee's Wail*, a Mechagon con el Capitán Krooz y a Karazhan por el Portal Oscuro). Si eres **mago** usa tus teletransportes, y si hay un mago en el grupo te dice a quién pedirle el portal. Las casillas se marcan solas con el lockout o a mano hasta el reinicio (por personaje); **Reset all / dungeons / raids**, **Hide completed steps**, tiempo estimado y **Next step** (waypoint). |
| **Collection** | Todas las monturas del diario en una lista con buscador, filtro *All / Missing / Collected* y filtro por fuente. Las farmeables ahora se marcan en verde. La vista **Boss drops** agrupa por expansión las monturas de jefes del dataset (raids, mazmorras y world bosses); clic en una expansión filtra la lista. La vista **Achievements** lista todos los logros con montura de recompensa y tu progreso (clic: detalle de la montura; clic derecho: ventana de logros). La vista **Other drops** muestra las monturas de rares, trash y botín del mundo con quién la suelta y la zona, según el diario. Clic en cualquier montura abre su **detalle**: modelo 3D, estado, dónde conseguirla dificultad por dificultad (con **Go** o **Map**), logros y el texto del diario. |
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
| `/aplan probe` · `/aplan scan` | Herramientas de desarrollo (ver CLAUDE.md) |

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
