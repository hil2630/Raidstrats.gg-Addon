local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end

-- Boss overview database (editable by addon authors).
-- Key format: lowercase boss encounter name as shown in Encounter Journal.
Addon.BossOverviewData = {
    byName = {
        ["imperator averzian"] = "Custom overview pending.\n\nAdd strategy notes here (phase goals, key overlap windows, and assignment reminders).",
        ["vorasius"] = "Custom overview pending.\n\nAdd strategy notes here (phase goals, key overlap windows, and assignment reminders).",
        ["fallen-king salhadaar"] = "Custom overview pending.\n\nAdd strategy notes here (phase goals, key overlap windows, and assignment reminders).",
        ["vaelgor & ezzorak"] = "Custom overview pending.\n\nAdd strategy notes here (phase goals, key overlap windows, and assignment reminders).",
        ["lightblinded vanguard"] = "Custom overview pending.\n\nAdd strategy notes here (phase goals, key overlap windows, and assignment reminders).",
        ["crown of the cosmos"] = "Custom overview pending.\n\nAdd strategy notes here (phase goals, key overlap windows, and assignment reminders).",
        ["chimaerus the undreamt god"] = "Custom overview pending.\n\nAdd strategy notes here (phase goals, key overlap windows, and assignment reminders).",
        ["belo'ren, child of al'ar"] = "Custom overview pending.\n\nAdd strategy notes here (phase goals, key overlap windows, and assignment reminders).",
        ["midnight falls"] = "Custom overview pending.\n\nAdd strategy notes here (phase goals, key overlap windows, and assignment reminders).",
        ["rotmire"] = "Custom overview pending.\n\nAdd strategy notes here (phase goals, key overlap windows, and assignment reminders).",

        ["loom'ithar"] = "Custom overview pending.\n\nAdd strategy notes here (phase goals, key overlap windows, and assignment reminders).",
        ["forgeweaver araz"] = "Custom overview pending.\n\nAdd strategy notes here (phase goals, key overlap windows, and assignment reminders).",
        ["fractilus"] = "Custom overview pending.\n\nAdd strategy notes here (phase goals, key overlap windows, and assignment reminders).",
        ["plexus sentinel"] = "Custom overview pending.\n\nAdd strategy notes here (phase goals, key overlap windows, and assignment reminders).",
        ["soulbinder naazindhri"] = "Custom overview pending.\n\nAdd strategy notes here (phase goals, key overlap windows, and assignment reminders).",
        ["the soul hunters"] = "Custom overview pending.\n\nAdd strategy notes here (phase goals, key overlap windows, and assignment reminders).",
        ["nexus-king salhadaar"] = "Custom overview pending.\n\nAdd strategy notes here (phase goals, key overlap windows, and assignment reminders).",
        ["dimensius"] = "Custom overview pending.\n\nAdd strategy notes here (phase goals, key overlap windows, and assignment reminders).",
    }
}
