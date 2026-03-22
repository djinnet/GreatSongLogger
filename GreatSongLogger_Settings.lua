local addonName = ...
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

EmoteLoggerDB = EmoteLoggerDB or {}

-- =========================
-- Defaults
-- =========================
local defaults = {
    debug = false,
    experimental = false,
    showPersonalNumber = true,
    showGroupNumber = true,
}

local function InitSettings()
    EmoteLoggerDB.settings = EmoteLoggerDB.settings or {}

    for k, v in pairs(defaults) do
        if EmoteLoggerDB.settings[k] == nil then
            EmoteLoggerDB.settings[k] = v
        end
    end
end

-- =========================
-- Accessors
-- =========================
function EmoteLogger_IsDebug()
    return EmoteLoggerDB.settings and EmoteLoggerDB.settings.debug
end

function EmoteLogger_IsExperimental()
    return EmoteLoggerDB.settings and EmoteLoggerDB.settings.experimental
end

function EmoteLogger_ShowPersonalNumber()
    return EmoteLoggerDB.settings and EmoteLoggerDB.settings.showPersonalNumber
end

function EmoteLogger_ShowGroupNumber()
    return EmoteLoggerDB.settings and EmoteLoggerDB.settings.showGroupNumber
end

function ForcePrint(msg, type)
    local color = "|cFFFFFF00[GreatSongLogger]|r"
    if type == "debug" then
        color = "|cFF00FF00[GreatSongLogger Debug]|r"
    elseif type == "experimental" then
        color = "|cFFFFA500[GreatSongLogger Experimental]|r"
    end
    print(color .. " " .. msg)
end

local options = {
    name = "The Great Song Logger",
    type = 'group',
    args = {
        debug = {
            type = 'toggle',
            name = 'Enable Debug Mode',
            desc = 'Toggle debug mode for additional logging.',
            get = function() return EmoteLoggerDB.settings.debug end,
            set = function(_, val)
                EmoteLoggerDB.settings.debug = val
                ForcePrint("Debug mode set to " .. tostring(val), "debug")
            end,
            order = 1
        },
        experimental = {
            type = 'toggle',
            name = 'Enable Experimental Features',
            desc = 'Toggle experimental features for testing.',
            get = function() return EmoteLoggerDB.settings.experimental end,
            set = function(_, val)
                EmoteLoggerDB.settings.experimental = val
                ForcePrint("Experimental mode set to " .. tostring(val), "experimental")
            end,
            order = 2
        },
        showPersonalNumber = {
            type = 'toggle',
            name = 'Show Personal Number',
            desc = 'Toggle display of personal number in the UI.',
            get = function() return EmoteLoggerDB.settings.showPersonalNumber end,
            set = function(_, val)
                EmoteLoggerDB.settings.showPersonalNumber = val
                ForcePrint("Show Personal Number set to " .. tostring(val))
            end,
            order = 3
        },
        showGroupNumber = {
            type = 'toggle',
            name = 'Show Group Number',
            desc = 'Toggle display of group number in the UI.',
            get = function() return EmoteLoggerDB.settings.showGroupNumber end,
            set = function(_, val)
                EmoteLoggerDB.settings.showGroupNumber = val
                ForcePrint("Show Group Number set to " .. tostring(val))
            end,
            order = 4
        },
    },
}

local function CreateSettingsPanel()
    AceConfig:RegisterOptionsTable(addonName, options)
    AceConfigDialog:AddToBlizOptions(addonName, "The Great Song Logger")
end

-- =========================
-- Init
-- =========================
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")

f:SetScript("OnEvent", function(_, _, name)
    if name ~= addonName then return end

    InitSettings()
    CreateSettingsPanel()
end)
