# Documentación — Mount Planner v1.2

Línea base consolidada de producto y técnica. **Reemplaza** a los paquetes v1.0 y v1.1 (`.docx`), cuyos cambios estaban añadidos como secciones "BASELINE UPDATE" encima del texto anterior. Aquí hay un solo texto vigente.

| Documento | Contenido |
|---|---|
| [01-producto.md](01-producto.md) | Visión, principios, alcance, estados de elegibilidad y reglas de negocio |
| [02-ux-ui.md](02-ux-ui.md) | Pantallas, interacción, navegación con waypoints, dirección visual y localización |
| [03-funcional.md](03-funcional.md) | Entidades, motor de elegibilidad, lockouts, lista "farmeable ahora" y eventos |
| [04-arquitectura.md](04-arquitectura.md) | Estructura del código, APIs, IDs canónicos, pipeline de datos y librerías |
| [05-mvp-y-roadmap.md](05-mvp-y-roadmap.md) | **Definición del MVP**, criterios de aceptación, entregables, roadmap y preguntas abiertas |

## Decisiones vigentes (resumen)
- MVP: **raids y mazmorras legacy**; piloto con ~13 raids clásicas de monturas.
- El "planner" del MVP es la **lista de "farmeable ahora"**: sin modos Hoy/Semana ni scoring.
- Colección account-wide; elegibilidad del **personaje activo**, evaluada **por fuente**.
- Clave canónica: `mountID` del Mount Journal.
- Navegación: **waypoint nativo** de Blizzard por defecto; TomTom opcional.
- Dataset estático offline, solo con IDs; los nombres se leen del juego en el idioma del cliente.
- Licencia **MIT**; repo público en GitHub.
- Cliente objetivo: **12.1.5** (build 70783, Interface 120105).

## Referencias visuales
Los vision boards originales (PNG) **no se suben al repo** porque contienen el logo de WoW Midnight. Siguen en la carpeta compartida del equipo como referencia interna de layout.

## Convenciones
- Los documentos están en español; el código, los identificadores y los comentarios del código, en inglés.
- Todo nombre de API o evento es un **candidato** hasta que `/mplan probe` lo confirme en el cliente objetivo. Las confirmaciones se anotan en [05-mvp-y-roadmap.md](05-mvp-y-roadmap.md#validación-técnica).
