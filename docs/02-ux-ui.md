# 02 — UX/UI · v1.2

## 1. Objetivo de UX
La interfaz responde rápido a tres preguntas:
1. ¿Cómo va mi colección?
2. ¿Qué puedo farmear **ahora** con este personaje?
3. ¿Adónde voy primero?

## 2. Navegación (MVP)

| Pantalla | Propósito |
|---|---|
| **Inicio** | Progreso de la colección, conteo por estado y un acceso a "farmeable ahora" |
| **Farmeable ahora** | Lista de actividades Ready agrupadas por continente o zona, con waypoint |
| **Colección** | Catálogo completo con filtros independientes de colección y de elegibilidad |
| **Detalle de montura** | Todas las fuentes de la montura, con sus requisitos, lockout, confianza del dato y acciones |
| **Ajustes** | Navegación (nativa o TomTom), filtros por defecto y datos del dataset |

Se abre con `/mplan` o desde el menú de addons del minimapa (AddonCompartment). La ventana se puede mover y cerrar con ESC.

## 3. Inicio
- Monturas conseguidas de la cuenta / total del journal, con su porcentaje y una barra de progreso.
- Tarjetas con el conteo de cada estado: Ready · Locked out · Unlock Required · Sin datos.
- Un resumen de "farmeable ahora": cuántas instancias y monturas hay, y cuáles son las 3 primeras.
- La fecha y hora del próximo reset semanal y diario.

## 4. Farmeable ahora (el "planner" del MVP)
- Agrupa por **continente → zona → instancia**. Cada instancia muestra:
  - las monturas que faltan, con la dificultad y el boss de cada una;
  - el estado del lockout por dificultad;
  - la cantidad de monturas, porque juntar varias en una misma instancia aumenta su valor.
- **Acciones por instancia:** poner un waypoint en la entrada, marcar como hecha, ocultar hasta el reset, ocultar siempre y ver el detalle.
- **Reordenar:** el jugador puede cambiar el orden y ese orden persiste.
- **Pie de la lista:** las instancias en *Locked out* aparecen colapsadas, con su hora de reset; las que requieren *Unlock Required* aparecen colapsadas, con el siguiente paso.
- **Al cambiar de zona:** el grupo de la zona actual se resalta, sin reordenar la lista del jugador.
- **Después de un reset:** aparece un aviso de que hay N instancias disponibles de nuevo y un botón "Actualizar". La lista no se cambia sola.

## 5. Colección
Muestra **todas** las monturas del journal. La colección y la elegibilidad son filtros independientes:
- Búsqueda por nombre.
- Conseguida / Faltante.
- Estado de elegibilidad, incluido *Sin datos de fuente*.
- Expansión.
- Tipo de fuente del journal.
- Favoritas.
- Ocultas por facción o clase.

La lista es virtualizada: se reutilizan las filas y no se crea un frame por montura.

## 6. Detalle de montura
- Nombre, icono y descripción, tomados del journal.
- **Todas las fuentes conocidas.** Por cada una: instancia, boss, dificultad, estado, la explicación del estado, el lockout y su reset, el drop rate con su confianza y procedencia, y la fecha de la última revisión.
- **Acciones:** waypoint a la entrada, agregar a "farmeable ahora" (con advertencia si la fuente no está Ready) y favorito.
- Si la montura no tiene datos en el dataset, se muestra el texto de fuente del journal (`sourceText`) con la etiqueta *Sin datos de fuente*.

## 7. Navegación con waypoints
1. **Por defecto, el waypoint nativo de Blizzard:** `C_Map.SetUserWaypoint` + `C_SuperTrack.SetSuperTrackedUserWaypoint(true)`.
2. **TomTom es opcional** (si está instalado y se activa en Ajustes): `TomTom:AddWaypoint(uiMapID, x, y, { title = ... })`.
3. **Si el jugador ya tiene un waypoint propio,** se le pregunta antes de reemplazarlo.
4. **Si no se puede poner un waypoint en ese mapa,** se muestra la zona y las coordenadas en texto.
5. **Coordenadas:** las de la entrada vienen de `C_EncounterJournal.GetDungeonEntrancesForMap` cuando están disponibles; si no, del dataset curado.

## 8. Dirección visual
- Frames nativos con una estética sobria: jerarquía clara, tipografía legible y pocos adornos.
- Los vision boards son referencia de **layout**, no de renderizado.

**Paleta:**

| Token | Color |
|---|---|
| background | `#1B1828` |
| surface | `#302A40` |
| accent | `#A88AD7` |
| success | `#8DD3A8` |

**Badges de estado:**

| Estado | Color |
|---|---|
| Ready | verde (success) |
| Locked out | ámbar |
| Unlock Required | azul |
| Verification Required | gris con un "?" |
| Unavailable | gris tenue |

- Componentes reutilizables: MountRow, StatusBadge, ProgressBar, InstanceGroup, SourceCard, RequirementList, FilterBar, EmptyState y ConfirmDialog.
- **No se distribuyen logos ni marcas de Blizzard.**

## 9. Localización
- Locales: **enUS** (base), **esES** y **esMX** (hereda de esES y sobrescribe solo lo que cambia).
- Los nombres de monturas, instancias y bosses se leen de las APIs del juego en el idioma del cliente.
- Solo los textos propios del addon van en `Locales/`.

## 10. Principios de UX
- Lo accionable se ve primero; lo bloqueado nunca se mezcla con lo Ready.
- Cada estado viene con su **por qué**.
- Nunca se cambia en silencio lo que el jugador editó.
- Se usan etiquetas de incertidumbre en lugar de certezas falsas.
