# 01 — Producto (PRD) · v1.2

## 1. Visión
Mount Planner es un planificador de colección y farmeo de monturas que funciona dentro de World of Warcraft retail. Combina el catálogo de la cuenta, la elegibilidad del personaje activo, una lista de actividades que se pueden hacer ahora y la navegación con waypoints.

> *"Sabe qué puedes conseguir. Planea cómo conseguirlo."*

## 2. Problema
Las herramientas actuales explican de dónde sale una montura, pero mandan al jugador a contenido al que todavía no puede acceder, o que ya hizo esta semana. Mount Planner distingue **lo que se puede farmear ahora** de **lo que requiere desbloqueo** y de **lo que no está disponible**.

## 3. Principios
1. **Lo accionable primero**: priorizar lo que el personaje activo realmente puede intentar.
2. **Colección por cuenta**: una montura conseguida por cualquier personaje cuenta para toda la cuenta.
3. **Elegibilidad por personaje**: en el MVP se evalúa solo el personaje activo.
4. **Elegibilidad por fuente**: una montura puede tener una fuente lista y otra bloqueada.
5. **Incertidumbre honesta**: lo desconocido se etiqueta y **nunca se trata como "listo"**.
6. **El jugador tiene el control**: el addon propone y nunca reescribe en silencio lo que el jugador editó.
7. **Funciona offline**: no hace llamadas HTTP; el dataset va empaquetado con el addon.

## 4. Alcance

### MVP (v1.0)
- Monturas de **raids y mazmorras legacy**.
- Seguimiento de la colección de la cuenta y elegibilidad del personaje activo.
- Lockouts según la dificultad.
- Lista de **"farmeable ahora"**, agrupada por continente o zona, con waypoints.
- Pantallas: Inicio, Farmeable ahora, Colección, Detalle de montura y Ajustes.

### Después del MVP (ver [roadmap](05-mvp-y-roadmap.md#roadmap))
World bosses, rares, eventos, reputaciones, logros, profesiones, PvP, Trading Post, promociones, scoring, planes Hoy/Semana/Custom, optimización de rutas y optimización entre personajes.

El **catálogo completo** de monturas se muestra desde el MVP (lo da el Mount Journal), pero solo las fuentes legacy de raid y mazmorra tienen datos de farmeo. Las demás aparecen como *Sin datos de fuente*, que es distinto de "no disponible".

## 5. Estados de elegibilidad (por fuente)

| Estado | Significado | ¿Entra en "farmeable ahora"? |
|---|---|---|
| **Ready** (Listo para farmear) | Los requisitos conocidos se cumplen y el intento de botín está disponible | Sí |
| **Locked out** (En lockout) | Los requisitos se cumplen, pero el intento de esta semana o de hoy ya se usó | No; se muestra cuándo se reinicia |
| **Unlock Required** (Requiere desbloqueo) | Falta al menos un requisito conocido | No; se muestra el siguiente paso |
| **Unavailable** (No disponible) | La fuente no se puede obtener actualmente | No |
| **Verification Required** (Requiere verificación) | No se puede confirmar la elegibilidad o el lockout | No por defecto; se explica el motivo |

> **Novedad de v1.2:** *Locked out* pasa a ser un estado propio, en lugar de un caso de *Unavailable*. En un MVP de raids es el estado más frecuente y el jugador necesita ver cuándo vuelve a estar disponible.

**Estado agregado de una montura:** la toma el estado de su mejor fuente, en este orden: Ready → Locked out → Unlock Required → Verification Required → Unavailable.

## 6. Reglas de negocio
1. La colección del Mount Journal es la fuente de verdad. Nunca se recomienda una montura que la cuenta ya tiene.
2. Solo las fuentes **Ready** entran en "farmeable ahora" de forma automática.
3. El jugador puede agregar a mano una fuente que no está lista, después de ver una advertencia explícita.
4. Las ediciones manuales (orden, ocultar, marcar como hecho) persisten entre recargas, cierres de sesión y cambios de personaje.
5. Un cambio de zona o un reset **propone** actualizaciones; nunca modifica en silencio la lista que el jugador editó.
6. Los drop rates y demás datos externos llevan su procedencia y su nivel de confianza.
7. El addon no pisa un waypoint que el jugador puso con otro fin, salvo que el jugador lo pida.

## 7. Criterios de éxito del producto
- El jugador ve en menos de 5 segundos qué monturas faltantes puede intentar **hoy** con este personaje.
- Ninguna fuente bloqueada, en lockout o desconocida aparece como farmeable.
- La lista funciona igual con o sin TomTom.
- La colección es correcta al cambiar de personaje.
- Los datos no verificados se distinguen visualmente de los confirmados.

## 8. Fuera de alcance (permanente)
- Acciones automatizadas que jueguen por el usuario.
- Consultas en tiempo de ejecución a bases de datos externas.
- Usar datos de combate protegidos (Secret Values de Midnight).
