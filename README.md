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

## Uso
| Comando | Qué hace |
|---|---|
| `/aplan` (o `/animalitos`, o el menú de addons del minimapa) | Abre la ventana, con las pestañas **Farmeable ahora** y **Resumen** |
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
pipeline/            scripts Python: parser de SavedVariables, generador del dataset, conversor de ícono
data/                snapshot del scan, correcciones curadas y reporte de huecos
docs/                documentación de producto y técnica (v1.2, en español)
CLAUDE.md            contexto completo para quien continúe el proyecto (personas o Claude)
```

Licencia: [MIT](LICENSE).
