local addonName = ...
local EmoteLogger = LibStub("AceAddon-3.0"):NewAddon("GreatSongLogger", "AceEvent-3.0", "AceConsole-3.0")


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
EmoteLogger.playerIndex = {}

-- =========================
-- player buff cache
-- =========================
EmoteLogger.playerBuffData = {}

-- Common emotes in The Great Song context
-- Applaud, Violin, Sing, Roar, congrats/congratulates, dance, play, cheer, kneel, laugh, cry, no, yes
local emotes = {
    CHEER = { command = "CHEER", display = "/cheer", spellId = 1266756 },
    SING = { command = "SING", display = "/sing", spellId = 1266760 },
    DANCE = { command = "DANCE", display = "/dance", spellId = 1266758 },
    VIOLIN = { command = "VIOLIN", display = "/violin", spellId = 1266761 },
    APPLAUD = { command = "APPLAUD", display = "/applaud", spellId = 1266754 },
    CONGRATS = { command = "CONGRATS", display = "/congrats", spellId = 1266755 },
    ROAR = { command = "ROAR", display = "/roar", spellId = 1266759 },
    BOW = { command = "BOW", display = "/bow", spellId = nil },
    UNKNOWN = { command = nil, display = "?", spellId = nil },
}


local PREFIX = "GSL";

-- =========================
-- Debug
-- =========================
function EmoteLogger:DebugPrint(...)
    if EmoteLogger_IsDebug and EmoteLogger_IsDebug() then
        print("|cff8888ff[DEBUG]|r", ...)
    end
end

function EmoteLogger:AssignRaidIndices()
    wipe(self.playerIndex)

    local count = GetNumGroupMembers()

    if count == 0 then
        self:DebugPrint("Not in a raid group, skipping raid index assignment.")
        return
    end

    local isRaid = IsInRaid()

    for i = 1, count do
        local unit = isRaid and ("raid" .. i) or ("party" .. i)
        if UnitName(unit) then
            local name = UnitName(unit)
            self.playerIndex[name] = i
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

    local emoteKeys = { "cheer", "sing", "dance", "violin", "applaud", "congrats", "roar", "bow", "cry", "no", "yes" }

    for _, e in ipairs(emoteKeys) do
        if message:find(e) then
            return e
        end
    end

    return nil
end

function EmoteLogger:GetRaidPosition(name)
    if not IsInRaid() then return nil end

    for i = 1, GetNumGroupMembers() do
        local raidName, _, subgroup = GetRaidRosterInfo(i)

        self:DebugPrint(string.format("Checking raid member %d: %s (looking for %s)", i, raidName or "nil", name))
        self:DebugPrint(string.format("Ambiguated raid member name: %s", Ambiguate(raidName, "short") or "nil"))
        self:DebugPrint(string.format("Is this the player we're looking for? %s",
            (Ambiguate(raidName, "short") == name) and "Yes" or "No"))
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
function EmoteLogger:CreateUI()
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

    -- Status indicator (circle)
    frame.statusDot = frame:CreateTexture(nil, "OVERLAY")
    frame.statusDot:SetSize(12, 12)
    frame.statusDot:SetPoint("TOPLEFT", 15, -15)

    -- Status text
    frame.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.statusText:SetPoint("LEFT", frame.statusDot, "RIGHT", 5, 0)
    frame.statusText:SetText("Song Inactive")

    -- Close button
    CreateFrame("Button", nil, frame, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -5, -5)

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
        self:Clear()
    end)

    local shareBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    shareBtn:SetSize(80, 22)
    shareBtn:SetPoint("LEFT", clearBtn, "LEFT", -90, 0)
    shareBtn:SetText("Share")

    shareBtn:SetScript("OnClick", function()
        self:ShareSequences()
    end)

    local viewSeqBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    viewSeqBtn:SetSize(80, 22)
    viewSeqBtn:SetPoint("LEFT", shareBtn, "LEFT", -90, 0)
    viewSeqBtn:SetText("View Seqs")

    viewSeqBtn:SetScript("OnClick", function()
        self:ViewAllSequences()
    end)

    local viewGroupBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    viewGroupBtn:SetSize(90, 22)
    viewGroupBtn:SetPoint("LEFT", viewSeqBtn, "LEFT", -100, 0)
    viewGroupBtn:SetText("View Group")

    viewGroupBtn:SetScript("OnClick", function()
        self:ViewGroupMembers()
    end)

    self.frame = frame
end

function EmoteLogger:GetGroupNumber(playername)
    local group, _ = self:GetRaidPosition(playername)
    local groupText = group and ("Group" .. group .. " ") or ""
    return groupText
end

function EmoteLogger:GetPlayerPersonalNumber(playername)
    local personalNumberText = ""
    local idx = self.playerIndex[playername]
    self:DebugPrint(string.format("Player %s has raid index: %s", playername, idx or "nil"))
    if idx then
        personalNumberText = string.format(" |cffffff00#%d|r", idx)
    end
    return personalNumberText
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

    local groupText = ""
    local personalNumberText = ""

    if EmoteLogger_ShowGroupNumber() then
        groupText = self:GetGroupNumber(entry.name)
    end

    if EmoteLogger_ShowPersonalNumber() then
        personalNumberText = self:GetPlayerPersonalNumber(entry.name)
    end

    text:SetText(string.format(
        "|cffaaaaaa[%s]|r %s|cff00ff00%s|r%s: %s",
        entry.time,
        groupText,
        entry.name,
        personalNumberText,
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

function EmoteLogger:SavePlayerSessions()
    for p, s in pairs(self.playerSessions) do
        if s.active and #s.sequence > 0 then
            self.completedSequences[p] = self.completedSequences[p] or {}
            table.insert(self.completedSequences[p], s.sequence)
        end

        s.active = false
    end
end

-- =========================
-- Sequence
-- =========================
function EmoteLogger:ProcessSequence(playerName, emote)
    if not emote then return end

    local session = self.playerSessions[playerName]
    local group, _ = self:GetGroupNumber(playerName)
    local personalNumberText = self:GetPlayerPersonalNumber(playerName)

    if not session then
        session = { active = false, sequence = {} }
        self.playerSessions[playerName] = session
    end

    -- START sequence
    if emote == "bow" then
        if not self.songActive then
            self.songActive = true
            self:UpdateSongStatusUI()

            -- Reset all sessions when a new song starts
            wipe(self.playerSessions)

            self.playerSessions[playerName] = {
                active = true,
                sequence = { "bow" }
            }

            self:DebugPrint(playerName .. " started The Great Song")

            local entry = {
                name = playerName,
                emote = "|cff00ff00started The Great Song|r",
                time = date("%H:%M:%S")
            }

            table.insert(self.logs, entry)
            if self.frame and self.frame:IsShown() then
                self:AddRow(entry)
            end
            return
        end

        if self.songActive then
            self.songActive = false
            self:UpdateSongStatusUI()

            self:DebugPrint(playerName .. " ended The Great Song")

            -- Save ALL active sessions
            self:SavePlayerSessions()

            local entry = {
                name = playerName,
                emote = "|cffffff00ended The Great Song|r",
                time = date("%H:%M:%S")
            }

            table.insert(self.logs, entry)
            if self.frame and self.frame:IsShown() then
                self:AddRow(entry)
            end

            return
        end
    end

    if not self.songActive then return end
    if not session or not session.active then return end

    -- CANCEL sequence
    if emote == "cry" or emote == "no" then
        self:DebugPrint(string.format("%s (Group %d) failed The Great Song", playerName, group or 0))

        self:SavePlayerSessions()

        session.active = false
        self.songActive = false
        self:UpdateSongStatusUI()

        local entry = {
            name = playerName,
            emote = "|cffff0000 cancelled The Great Song|r",
            time = date("%H:%M:%S")
        }

        table.insert(self.logs, entry)
        if self.frame and self.frame:IsShown() then
            self:AddRow(entry)
        end
        return
    end

    -- Append emote
    table.insert(session.sequence, emote)
    self:DebugPrint(string.format("%s %s%s performed emote: %s (current sequence: %s)", playerName, group or "",
        personalNumberText, emote, table.concat(session.sequence, " -> ")))
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
        self:DebugPrint("The Great Song has unsuccessfully concluded. Resetting state.")
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

    self:DebugPrint(string.format("Received emote from %s: %s (extracted key: %s)", sender, message, emoteKey or "nil"))

    local groupmember = self.groupMembers[nameshort]
    self:DebugPrint(string.format("Is %s a group member? %s", nameshort, groupmember and "Yes" or "No"))
    if groupmember == true then
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
    self:AssignRaidIndices() -- Update player index mapping for personal number display
end

local function SendToChat(msg)
    if IsInRaid() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "RAID")
    elseif IsInGroup() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "PARTY")
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

function EmoteLogger:FindLuckyNumbers(id)
    -- ID is a number ranged from 1 to 1000
    local firstluckynumber = math.floor(id / 100)
    local secondluckynumber = (id - 1) % 20 + 1
    local measurenumber = math.floor((id - 1) / 40) + 1
    local singernumber = ((id - 1) % 40) + 1

    self:DebugPrint(string.format("ID: %d → Measure: %d, Singer: %d, Lucky1: %d, Lucky2: %d",
        id, measurenumber, singernumber, firstluckynumber, secondluckynumber))

    self:PerformEmote(measurenumber, singernumber)
end

function EmoteLogger:PerformEmote(measure, singer)
    local row = EmoteTableDB[measure]
    if row then
        local emote = row[singer]

        if emote == "UNKNOWN" then
            self:DebugPrint(string.format("Emote for Measure %d Singer %d is UNKNOWN. Cannot perform emote.", measure,
                singer))
            print("|cffffcc00Emote for Measure " ..
            measure .. " Singer " .. singer .. " is UNKNOWN. Cannot perform emote.|r")
            return
        end

        if emote then
            DoEmote(emote)
            return
        end
    end

    print("|cffffcc00No emote set for Measure " .. measure .. " Singer " .. singer .. ".|r")
end

function EmoteLogger:Clear(args)
    wipe(self.logs)
    self:RefreshUI()
    print("Emote log cleared.")
end

-- =========================
-- Slash Commands
-- =========================
function EmoteLogger:SlashCmdList(input)
    if not self.frame then
        self:CreateUI()
    end

    local cmd, arg = input:match("^(%S*)%s*(.-)$")

    if cmd == "clear" then
        self:Clear()
        return
    end

    if cmd == "viewallsequences" then
        self:ViewAllSequences()
        return
    end

    if cmd == "viewgroup" then
        self:ViewGroupMembers()
        return
    end

    if cmd == "share" then
        self:ShareSequences()
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
        print("/elog findln <number> - Find lucky numbers for a given ID (1-1000)")
        print("/elog findms <measure> <singer> - Find lucky numbers for a given measure and singer")
        return
    end

    if cmd == "findms" then
        local measure, singer = arg:match("^(%d+)%s+(%d+)$")
        measure = tonumber(measure)
        singer = tonumber(singer)

        if measure and singer then
            self:DebugPrint(string.format("Finding emote for Measure %d Singer %d", measure, singer))
            self:PerformEmote(measure, singer)
        else
            print("Usage: /elog findms <measure> <singer>")
        end
        return
    end

    if cmd == "findln" then
        local idvalue = tonumber(arg)
        if idvalue then
            self:FindLuckyNumbers(idvalue)
        else
            print("Usage: /elog findln <number>")
        end
        return
    end

    -- SEQUENCE VIEW
    if cmd == "seq" and arg ~= "" then
        self:ViewPlayerSequences(arg)
        return
    end

    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
        self:RefreshUI()
        self:UpdateSongStatusUI()
    end
end

-- =========================
-- Lifecycle
-- =========================
function EmoteLogger:OnInitialize()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    self:RegisterChatCommand("elog", "SlashCmdList")
    self:UpdateGroup()
end

function EmoteLogger:OnEnable()
    self:RegisterEvent("CHAT_MSG_TEXT_EMOTE")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")

    self:DebugPrint("Addon Enabled")
end

function EmoteLogger:OnDisable()
    self:UnregisterEvent("CHAT_MSG_TEXT_EMOTE")
    self:UnregisterEvent("GROUP_ROSTER_UPDATE")

    self:DebugPrint("Addon Disabled")
end
