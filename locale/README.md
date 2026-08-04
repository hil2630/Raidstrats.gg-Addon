# Locales

English source strings live in `enUS.lua`. Other languages override the translated side of each entry.

## Add a language

1. Copy `enUS.lua` to a Blizzard locale code, e.g. `frFR.lua` / `deDE.lua` / `koKR.lua`.
2. At the bottom, change the register call:
   ```lua
   RaidstratsggLocale:Register("frFR", L)
   ```
3. Translate the **right-hand** side only. Leave keys (the English text in `L["..."]`) unchanged.
   ```lua
   L["Save"] = "Save"          -- enUS
   L["Save"] = "Sauvegarder"   -- frFR
   ```
4. Load the file in `Raidstratsgg.toc` (after `enUS.lua`):
   ```
   locale\frFR.lua
   ```
5. Add it to the picker in `Locale.lua`:
   ```lua
   { code = "frFR", labelKey = "LANGUAGE_FRFR" },
   ```
6. Add the picker label in `enUS.lua` (and ideally every locale):
   ```lua
   L["LANGUAGE_FRFR"] = "Français"
   ```

Missing keys fall back to English. Keep color codes (`|cff…|r`), `%s` / `%d`, and slash commands as-is.

## Edit an existing language

Change values in that locale file only. No code changes needed.
