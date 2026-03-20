local addonName = ...
local EmoteLogger = LibStub("AceAddon-3.0"):NewAddon("GreatSongLogger", "AceEvent-3.0")


-- =========================
-- Saved Data
-- =========================
EmoteLoggerDB = EmoteLoggerDB or {}
EmoteLogger.logs = EmoteLoggerDB.logs or {}
EmoteLoggerDB.logs = EmoteLogger.logs

local MAX_LOGS = 500

-- =========================
-- Sequence Tracking
-- =========================
EmoteLogger.playerSessions = {}
EmoteLogger.completedSequences = {}
EmoteLogger.songActive = false

-- =========================
-- Group Cache (optimized)
-- =========================
EmoteLogger.groupMembers = {}

-- =========================
-- player buff cache
-- =========================
EmoteLogger.playerBuffData = {}

-- =========================
-- Debug
-- =========================
function EmoteLogger:DebugPrint(...)
    if EmoteLogger_IsDebug and EmoteLogger_IsDebug() then
        print("|cff8888ff[DEBUG]|r", ...)
    end
end

-- =========================
-- Spell ID for The Great Song buff
-- =========================
local SPELL_ID = 1266536

function EmoteLogger:ScanRaidBuffs()
    wipe(self.playerBuffData)

    if not IsInRaid() then return end

    for i = 1, GetNumGroupMembers() do
        local unit = "raid" .. i
        local name = UnitName(unit)

        if name then
            local fullName = Ambiguate(name, "none")
            local hasBuff = false
            local numbers = {}

            for j = 1, 40 do
                local aura = C_UnitAuras.GetAuraDataByIndex(unit, j, "HELPFUL")
                if not aura then break end

                if aura.spellId == SPELL_ID then
                    hasBuff = true

                    -- Extract numbers from description
                    if aura.description then
                        for num in aura.description:gmatch("%d+") do
                            table.insert(numbers, tonumber(num))
                        end
                    end

                    break
                end
            end


            if EmoteLogger_IsDebug() then
                print(string.format("|cff00ffff[EmoteLogger]|r Scanned %s: hasBuff=%s, numbers={%s}", fullName,
                    tostring(hasBuff), table.concat(numbers, ", ")))
            end

            -- Store result
            self.playerBuffData[fullName] = {
                hasBuff = hasBuff,
                numbers = numbers
            }

            -- Missing buff warning
            if not hasBuff then
                print("|cffff0000[EmoteLogger]|r " .. fullName .. " is missing Gift of Oddsight!")
            end
        end
    end
end

local function IsInGroupOrRaid()
    return IsInGroup() or IsInRaid()
end

local function NormalizeName(name)
    if not name then return nil end
    return Ambiguate(name, "none")
end

function EmoteLogger:UpdateGroup()
    wipe(self.groupMembers)

    if not IsInGroupOrRaid() then return end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name = GetRaidRosterInfo(i)
            if name then
                self.groupMembers[Ambiguate(name, "short")] = true
            end
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            local name = UnitName("party" .. i)
            if name then
                self.groupMembers[name] = true
            end
        end
        self.groupMembers[UnitName("player")] = true
    end
end

local function ExtractEmote(message)
    message = message:lower()

    -- Common emotes in The Great Song context
    -- Applaud, Violin, Sing, Roar, congrats/congratulates, dance, play, cheer, kneel, laugh, cry, no, yes
    local emotes = {
        "bow", "dance", "cheer", "kneel",
        "laugh", "cry", "roar",
        "applaud", "violin", "congrats",
        "no", "yes", "sing", "play", "congratulates"
    }

    for _, e in ipairs(emotes) do
        if message:find(e) then
            return e
        end
    end

    return nil
end

local function GetRaidPosition(name)
    if not IsInRaid() then return nil end

    for i = 1, GetNumGroupMembers() do
        local raidName, _, subgroup = GetRaidRosterInfo(i)

        if EmoteLogger_IsDebug() then
            print(string.format("|cff00ffff[EmoteLogger]|r Checking raid member %d: %s (Group %d)", i, raidName or "nil",
                subgroup or 0))
            print(string.format("|cff00ffff[EmoteLogger]|r Comparing with: %s", name))
            print(string.format("|cff00ffff[EmoteLogger]|r Ambiguated raid name: %s",
                Ambiguate(raidName, "short") or "nil"))
        end
        if raidName and Ambiguate(raidName, "short") == name then
            return subgroup, i
        end
    end

    return nil
end

function EmoteLogger:UpdateSongStatusUI()
    if not self.frame then return end

    if self.songActive then
        -- Green
        self.frame.statusDot:SetColorTexture(0, 1, 0, 1)
        self.frame.statusText:SetText("Song Active")
    else
        -- Red
        self.frame.statusDot:SetColorTexture(1, 0, 0, 1)
        self.frame.statusText:SetText("Song Inactive")
    end
end

-- =========================
-- UI Creation
-- =========================
local function CreateUI()
    local frame = CreateFrame("Frame", "EmoteLoggerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(500, 300)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)

    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame:Hide()

    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", 0, -10)
    frame.title:SetText("The Great Song Logger")

    -- Status indicator (dot)
    frame.statusDot = frame:CreateTexture(nil, "OVERLAY")
    frame.statusDot:SetSize(12, 12)
    frame.statusDot:SetPoint("TOPLEFT", 15, -15)

    -- Status text
    frame.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.statusText:SetPoint("LEFT", frame.statusDot, "RIGHT", 5, 0)
    frame.statusText:SetText("Song Inactive")

    -- Close button
    CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        :SetPoint("TOPRIGHT", -5, -5)

    -- ScrollFrame
    frame.scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    local scrollFrame = frame.scrollFrame
    scrollFrame:SetPoint("TOPLEFT", 10, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)

    -- Sticky scroll tracking
    scrollFrame.atBottom = true
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        local maxScroll = self:GetVerticalScrollRange()
        self.atBottom = (maxScroll - offset <= 5)
    end)

    -- Content
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)

    frame.content = content
    frame.rows = {}

    -- Clear button
    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    clearBtn:SetText("Clear")

    clearBtn:SetScript("OnClick", function()
        wipe(EmoteLogger.logs)
        EmoteLogger:RefreshUI()
    end)

    local shareBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    shareBtn:SetSize(80, 22)
    shareBtn:SetPoint("LEFT", clearBtn, "LEFT", -90, 0)
    shareBtn:SetText("Share")

    shareBtn:SetScript("OnClick", function()
        EmoteLogger:ShareSequences()
    end)

    local viewSeqBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    viewSeqBtn:SetSize(80, 22)
    viewSeqBtn:SetPoint("LEFT", shareBtn, "LEFT", -90, 0)
    viewSeqBtn:SetText("View Seqs")

    viewSeqBtn:SetScript("OnClick", function()
        -- For simplicity, just show all sequences in chat for now
        EmoteLogger:ViewAllSequences()
    end)

    local viewGroupBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    viewGroupBtn:SetSize(90, 22)
    viewGroupBtn:SetPoint("LEFT", viewSeqBtn, "LEFT", -100, 0)
    viewGroupBtn:SetText("View Group")

    viewGroupBtn:SetScript("OnClick", function()
        EmoteLogger:ViewGroupMembers()
    end)

    EmoteLogger.frame = frame
end

-- =========================
-- Add Row (real-time)
-- =========================
function EmoteLogger:AddRow(entry)
    if not self.frame then return end

    local content = self.frame.content
    local scrollFrame = self.frame.scrollFrame

    local rowHeight = 20
    local index = #self.frame.rows + 1
    local yOffset = -(index - 1) * rowHeight - 5

    local row = CreateFrame("Frame", nil, content)
    row:SetSize(440, rowHeight)
    row:SetPoint("TOPLEFT", 0, yOffset)

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetAllPoints()
    text:SetJustifyH("LEFT")

    local group, _ = GetRaidPosition(entry.name)
    local groupText = group and ("G" .. group .. " ") or ""

    local buffData = EmoteLogger.playerBuffData[entry.name]

    local numberText = ""
    if buffData and buffData.numbers and #buffData.numbers > 0 then
        numberText = " |cff00ffff[" .. table.concat(buffData.numbers, ",") .. "]|r"
    end

    text:SetText(string.format(
        "|cffaaaaaa[%s]|r %s|cff00ff00%s|r%s: %s",
        entry.time,
        groupText,
        entry.name,
        numberText,
        entry.emote
    ))

    table.insert(self.frame.rows, row)

    -- Resize content
    local newHeight = index * rowHeight + 10
    content:SetHeight(newHeight)

    -- Sticky auto-scroll
    if scrollFrame.atBottom then
        C_Timer.After(0, function()
            scrollFrame:SetVerticalScroll(scrollFrame:GetVerticalScrollRange())
        end)
    end
end

-- =========================
-- Sequence
-- =========================
function EmoteLogger:ProcessSequence(playerName, emote)
    if not emote then return end

    local session = self.playerSessions[playerName]
    local group, _ = GetRaidPosition(playerName)

    -- START sequence
    if emote == "bow" then
        self.songActive = true
        self:UpdateSongStatusUI()

        self.playerSessions[playerName] = {
            active = true,
            sequence = { "bow" }
        }

        print(string.format("|cff00ffff[EmoteLogger]|r %s (Group %d) started The Great Song", playerName, group or 0))
        return
    end

    if not self.songActive then return end
    if not session or not session.active then return end

    -- CANCEL sequence
    if emote == "cry" then
        print(string.format("|cffff0000[EmoteLogger]|r %s (Group %d) failed The Great Song", playerName, group or 0))

        -- Save failed attempt
        self.completedSequences[playerName] = self.completedSequences[playerName] or {}
        table.insert(self.completedSequences[playerName], session.sequence)

        session.active = false

        self:UpdateSongStatusUI()
        return
    end

    -- Append emote
    table.insert(session.sequence, emote)
end

-- =========================
-- Full Refresh (fallback)
-- =========================
function EmoteLogger:RefreshUI()
    if not self.frame then return end

    for _, row in ipairs(self.frame.rows) do
        row:Hide()
    end
    wipe(self.frame.rows)

    self.frame.content:SetHeight(1)

    for i = 1, #self.logs do
        self:AddRow(self.logs[i])
    end

    local scrollFrame = self.frame.scrollFrame
    C_Timer.After(0, function()
        scrollFrame:SetVerticalScroll(scrollFrame:GetVerticalScrollRange())
    end)
end

function EmoteLogger:CHAT_MSG_TEXT_EMOTE(_, message, sender)
    local name = NormalizeName(sender)
    local emoteKey = ExtractEmote(message)
    local lowerMsg = message:lower()

    -- Ignore before song starts
    if not self.songActive and emoteKey ~= "bow" then return end

    if lowerMsg:find("the great song has unsuccessfully concluded") then
        self.songActive = false
        self:UpdateSongStatusUI()
        -- end all active sessions
        for player, session in pairs(self.playerSessions) do
            if session.active then
                -- Save failed attempt
                self.completedSequences[player] = self.completedSequences[player] or {}
                table.insert(self.completedSequences[player], session.sequence)
                session.active = false
            end
        end
        print(string.format("|cffff0000[EmoteLogger]|r The Great Song has ended for all players."))
        return
    end

    -- SOLO BEHAVIOR
    if not IsInGroupOrRaid() then
        if name == NormalizeName(UnitName("player")) and emoteKey == "bow" then
            print("|cffffcc00You must be in a raid group.")
            print("|cffffcc00Bow to the great flame to begin the sequence.")
        end
        return
    end

    local nameshort = Ambiguate(sender, "short")

    if EmoteLogger_IsDebug() then
        print(string.format("|cff00ffff[EmoteLogger]|r Detected emote from %s: %s", name, message))
    end

    if self.groupMembers[nameshort] == true then
        local entry = {
            name = name,
            emote = message,
            time = date("%H:%M:%S")
        }

        table.insert(self.logs, entry)

        -- Limit log size
        if #self.logs > MAX_LOGS then
            table.remove(self.logs, 1)
            if self.frame and self.frame:IsShown() then
                self:RefreshUI()
            end
            return
        end

        -- Sequence tracking
        self:ProcessSequence(name, emoteKey)

        -- Real-time UI update
        if self.frame and self.frame:IsShown() then
            self:AddRow(entry)
        end
    end
end

function EmoteLogger:GROUP_ROSTER_UPDATE()
    self:UpdateGroup()
    self:ScanRaidBuffs()
end

function EmoteLogger:UNIT_AURA(_, unit)
    if unit and unit:match("^raid%d+$") then
        self:ScanRaidBuffs()
    end
end

local function SendToChat(msg)
    if IsInRaid() then
        C_ChatInfo.SendChatMessage(msg, "RAID")
    elseif IsInGroup() then
        C_ChatInfo.SendChatMessage(msg, "PARTY")
    else
        print(msg)
    end
end

function EmoteLogger:ShareSequences()
    if (not next(self.completedSequences)) then
        SendToChat("|cffffff00No completed sequences to share.|r")
        return
    end
    SendToChat("=== The Great Song Attempts ===")

    for player, sequences in pairs(self.completedSequences) do
        for i, seq in ipairs(sequences) do
            SendToChat(player .. ": " .. table.concat(seq, " → "))
        end
    end
end

function EmoteLogger:ViewPlayerSequences(arg)
    local name = NormalizeName(arg)
    local sequences = self.completedSequences[name]

    if not sequences or #sequences == 0 then
        print("|cffffff00No sequences found for " .. name)
        return
    end

    print("|cff00ffffSequences for " .. name .. ":")
    for i, seq in ipairs(sequences) do
        print(i .. ": " .. table.concat(seq, " → "))
    end
end

function EmoteLogger:ViewGroupMembers()
    if not IsInGroupOrRaid() then
        print("|cffffff00You are not in a group or raid.|r")
        return
    end

    print("|cff00ffffCurrent Group Members:|r")
    for member, _ in pairs(self.groupMembers) do
        print("- " .. member)
    end
end

function EmoteLogger:ViewAllSequences()
    if (not next(self.completedSequences)) then
        print("|cffffff00No completed sequences found.|r")
        return
    end

    print("|cff00ffffAll Completed Sequences:|r")
    for player, sequences in pairs(self.completedSequences) do
        for i, seq in ipairs(sequences) do
            print(player .. ": " .. table.concat(seq, " → "))
        end
    end
end

-- =========================
-- Slash Commands
-- =========================
SLASH_EMOTELOGGER1 = "/elog"

SlashCmdList["EMOTELOGGER"] = function(msg)
    if not EmoteLogger.frame then
        CreateUI()
    end

    local cmd, arg = msg:match("^(%S*)%s*(.-)$")

    if cmd == "clear" then
        wipe(EmoteLogger.logs)
        EmoteLogger:RefreshUI()
        print("Emote log cleared.")
        return
    end

    if cmd == "viewallsequences" then
        EmoteLogger:ViewAllSequences()
        return
    end

    if cmd == "viewgroup" then
        EmoteLogger:ViewGroupMembers()
        return
    end

    if cmd == "share" then
        EmoteLogger:ShareSequences()
        return
    end

    if cmd == "help" then
        print("|cff00ffffEmote Logger Commands:|r")
        print("/elog - Toggle log window")
        print("/elog clear - Clear the log")
        print("/elog seq <player> - View sequences for a player")
        print("/elog viewallsequences - View all completed sequences")
        print("/elog share - Share completed sequences in chat")
        print("/elog viewgroup - View current group members")
        return
    end

    -- SEQUENCE VIEW
    if cmd == "seq" and arg ~= "" then
        EmoteLogger:ViewPlayerSequences(arg)
        return
    end

    if EmoteLogger.frame:IsShown() then
        EmoteLogger.frame:Hide()
    else
        EmoteLogger.frame:Show()
        EmoteLogger:RefreshUI()
        EmoteLogger:UpdateSongStatusUI()
    end
end

-- =========================
-- Lifecycle
-- =========================
function EmoteLogger:OnInitialize()
    self:UpdateGroup()
end

function EmoteLogger:OnEnable()
    self:RegisterEvent("CHAT_MSG_TEXT_EMOTE")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("UNIT_AURA")

    self:DebugPrint("Addon Enabled")
end
