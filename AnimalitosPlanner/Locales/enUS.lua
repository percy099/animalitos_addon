-- enUS: base strings. Always loaded; other locale files override.
local _, ns = ...
local L = ns.L

L["TITLE"] = "AnimalitosPlanner"
L["COLLECTED"] = "Collected"
L["COLLECTION_PROGRESS"] = "Collection progress (account-wide)"
L["MISSING"] = "Missing"
L["MISSING_FOR_CHAR"] = "Missing, visible for this character"
L["HIDDEN_FOR_CHAR"] = "Missing, hidden in the journal for this character (other faction, class or unobtainable)"
L["MISSING_BY_SOURCE"] = "Missing by source type (Mount Journal)"
L["UNKNOWN_SOURCE"] = "Unknown source"
L["REFRESH"] = "Refresh"
L["DATASET_NONE"] = "Dataset: not loaded yet (Foundation v0.1)"
L["JOURNAL_NOT_READY"] = "Mount Journal data is not available yet. Try again in a few seconds."
L["LOADED"] = "v%s loaded. Type /aplan to open."
L["NEW_MOUNT"] = "New mount collected. Totals updated."
L["PROBE_DONE"] = "Diagnostics saved. Type /reload so they are written to SavedVariables."
L["PROBE_WAITING_RAID"] = "Diagnostics: waiting for saved-instance data..."
L["HELP"] = "Commands: /aplan (toggle window), /aplan probe (API diagnostics), /aplan scan (dev: build raw dataset), /aplan reset (reset window position)"
L["RESET_POS"] = "Window position reset."
L["NOTE_TOTALS"] = "The headline matches your Mount Journal (mounts visible for this character)."
L["ACCOUNT_LINE"] = "Account total: %s collected (%s hidden for this character). Hidden and missing: %s (other faction, class or unobtainable)."
