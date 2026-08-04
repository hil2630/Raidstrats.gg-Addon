-- Raidstrats.gg localization core

RaidstratsggLocale = RaidstratsggLocale or {}
local Locale = RaidstratsggLocale

Locale.locales = Locale.locales or {}
Locale._cache = nil
Locale._cacheCode = nil

-- Display order for the language picker. `auto` follows GetLocale().
Locale.OPTIONS = {
    { code = "auto", labelKey = "LANGUAGE_AUTO" },
    { code = "enUS", labelKey = "LANGUAGE_ENUS" },
    { code = "daDK", labelKey = "LANGUAGE_DADK" },
    { code = "zhTW", labelKey = "LANGUAGE_ZHTW" },
}

function Locale:Register(code, tbl)
    if type(code) ~= "string" or type(tbl) ~= "table" then return end
    self.locales[code] = tbl
    self._cache = nil
    self._cacheCode = nil
end

function Locale:NormalizeGameLocale(code)
    code = tostring(code or "")
    if code == "enGB" then return "enUS" end
    return code
end

function Locale:GetPreference()
    RaidstratsggSettings = RaidstratsggSettings or {}
    local pref = RaidstratsggSettings.locale
    if pref == nil or pref == "" then
        return "auto"
    end
    return tostring(pref)
end

function Locale:GetActiveCode()
    local pref = self:GetPreference()
    if pref == "auto" then
        return self:NormalizeGameLocale(GetLocale())
    end
    return pref
end

function Locale:Invalidate()
    self._cache = nil
    self._cacheCode = nil
end

function Locale:GetOptionLabel(code, translateFn)
    code = tostring(code or "auto")
    local translate = translateFn or function(key)
        return self:Translate(key)
    end
    for _, opt in ipairs(self.OPTIONS or {}) do
        if opt.code == code then
            return translate(opt.labelKey)
        end
    end
    return code
end

function Locale:GetTable()
    local pref = self:GetPreference()
    local code = self:GetActiveCode()
    -- Cache by preference + resolved code so Auto vs explicit enUS still refresh correctly.
    local cacheKey = pref .. "|" .. code
    if self._cache and self._cacheCode == cacheKey then
        return self._cache
    end
    -- Prefer the selected locale table; fall back to enUS for missing keys / unknown codes.
    local active = self.locales[code]
    if not active and pref ~= "auto" then
        active = self.locales[pref]
    end
    local fallback = self.locales.enUS or {}
    if not active then
        active = fallback
    end
    local view = setmetatable({}, {
        __index = function(_, key)
            key = tostring(key or "")
            local v = rawget(active, key)
            if v ~= nil then
                return v
            end
            if active ~= fallback then
                v = rawget(fallback, key)
                if v ~= nil then
                    return v
                end
            end
            return key
        end,
    })
    self._cache = view
    self._cacheCode = cacheKey
    return view
end

function Locale:Translate(key)
    return self:GetTable()[key]
end

--- Global shorthand used across addon files.
function RSGG_L(key)
    return RaidstratsggLocale:Translate(key)
end
