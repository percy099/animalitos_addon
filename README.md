# AnimalitosPlanner — código fuente

Estado: **Foundation v0.1** (esqueleto). La documentación de producto y técnica (v1.2) está en [`docs/`](docs/README.md).

## Estructura
```
AnimalitosPlanner/            <- carpeta del addon (enlazada a WoW con un junction)
  AnimalitosPlanner.toc       Interface 120105 (12.1.5)
  Core.lua               namespace, bus de eventos tolerante a eventos inexistentes, helpers
  Locales/               enUS (base), esES, esMX (hereda esES)
  Storage/               SavedVariables con versión de esquema y migraciones secuenciales
  Integrations/          adaptador del Mount Journal (único lugar con llamadas a C_MountJournal)
  Modules/Collection.lua totales account-wide (la fuente de verdad es el journal; nada se cachea)
  Modules/Probe.lua      /aplan probe: valida las APIs del diseño en el cliente real
  UI/MainFrame.lua       ventana mínima con los totales (paleta del doc 02)
  Bootstrap.lua          eventos y slash commands; se carga al final
```

## Instalación para desarrollo
`C:\World of Warcraft\_retail_\Interface\AddOns\AnimalitosPlanner` es un **junction** que apunta a
`F:\WowAddons\MountPlanner\AnimalitosPlanner`. Lo que se edita en F: se ve en el juego con `/reload`.
La primera vez hay que reiniciar el cliente para que detecte el addon nuevo.

## Comandos
- `/aplan`: abre o cierra la ventana (también desde el menú de addons del minimapa).
- `/aplan probe`: diagnóstico de APIs. Se guarda en `AnimalitosPlannerDB.diagnostics`.
- `/aplan reset`: reinicia la posición de la ventana.

## Ciclo de validación con el probe
1. En el juego: `/aplan probe`, esperar el mensaje "Diagnostics saved" y luego `/reload`.
2. El resultado queda en
   `C:\World of Warcraft\_retail_\WTF\Account\<CUENTA>\SavedVariables\AnimalitosPlanner.lua`.
3. Claude lee ese archivo y contrasta firmas, el Encounter Journal, las entradas a instancias,
   los lockouts y TomTom con lo que asumen los documentos.

Tip: corre el probe estando en una zona con entradas a mazmorras o raids (por ejemplo Tanaris o
Icecrown) y con algún lockout activo, para que haya datos de entradas y de instancias guardadas.

## Decisiones de v0.1 (revisables)
- Sin librerías externas todavía. Ace3 entra en v0.2 junto con la pantalla de Ajustes; el
  esquema de SavedVariables es pequeño, así que migrar a AceDB después es barato.
- Botón en el menú de addons del minimapa (AddonCompartment) en lugar de LibDBIcon.
- No hay dataset estático todavía: los totales salen al 100% del Mount Journal.
