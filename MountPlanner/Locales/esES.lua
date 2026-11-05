-- esES (also used as base for esMX).
local _, ns = ...
local locale = GetLocale()
if locale ~= "esES" and locale ~= "esMX" then return end
local L = ns.L

L["TITLE"] = "Mount Planner"
L["COLLECTED"] = "Conseguidas"
L["COLLECTION_PROGRESS"] = "Progreso de la colección (cuenta)"
L["MISSING"] = "Faltantes"
L["MISSING_FOR_CHAR"] = "Faltantes visibles para este personaje"
L["HIDDEN_FOR_CHAR"] = "Faltantes ocultas para este personaje (facción/clase)"
L["MISSING_BY_SOURCE"] = "Faltantes por tipo de fuente (diario de monturas)"
L["UNKNOWN_SOURCE"] = "Fuente desconocida"
L["REFRESH"] = "Actualizar"
L["DATASET_NONE"] = "Dataset: aún no cargado (Foundation v0.1)"
L["JOURNAL_NOT_READY"] = "Los datos del diario de monturas aún no están disponibles. Intenta en unos segundos."
L["LOADED"] = "v%s cargado. Escribe /mplan para abrir."
L["NEW_MOUNT"] = "Nueva montura conseguida. Totales actualizados."
L["PROBE_DONE"] = "Diagnóstico guardado. Escribe /reload para que se escriba en SavedVariables."
L["PROBE_WAITING_RAID"] = "Diagnóstico: esperando datos de instancias guardadas..."
L["HELP"] = "Comandos: /mplan (abrir/cerrar), /mplan probe (diagnóstico de API), /mplan reset (reiniciar posición)"
L["RESET_POS"] = "Posición de la ventana reiniciada."
L["NOTE_TOTALS"] = "Los totales vienen del diario de monturas y pueden diferir del conteo del logro de Blizzard."
