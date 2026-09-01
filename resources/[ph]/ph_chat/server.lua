local PALETTE = Config.NameColors
local PH = 'ph-core'

-- ----------------------------------------------------------
--  Ora Bucuresti / Romania (EET / EEST cu DST UE) -> "HH:MM"
-- ----------------------------------------------------------
local function dow(y, m, d)
    local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
    if m < 3 then y = y - 1 end
    return (y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) + t[m] + d) % 7
end

local function lastSunday(y, m)
    for d = 31, 25, -1 do
        if dow(y, m, d) == 0 then return d end
    end
    return 31
end

local function euDstActive(u)
    if u.month < 3 or u.month > 10 then return false end
    if u.month > 3 and u.month < 10 then return true end
    if u.month == 3 then
        local ml = lastSunday(u.year, 3)
        return (u.day > ml) or (u.day == ml and u.hour >= 1)
    end
    local ol = lastSunday(u.year, 10)
    return (u.day < ol) or (u.day == ol and u.hour < 1)
end

local function roStamp()
    local epoch = os.time()
    local u = os.date('!*t', epoch)
    local offset = 2 + (euDstActive(u) and 1 or 0)
    local b = os.date('!*t', epoch + offset * 3600)
    return ('%02d:%02d'):format(b.hour, b.min)
end

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
local function colorFor(key)
    key = tostring(key or '0')
    local sum = 0
    for i = 1, #key do sum = sum + key:byte(i) end
    return PALETTE[(sum % #PALETTE) + 1]
end

--- session id -> SQL id (users.id) prin ph-core
local function sqlId(src)
    local ok, id = pcall(function() return exports[PH]:GetUserId(src) end)
    if ok and id then return id end
    local ok2, char = pcall(function() return exports[PH]:GetCharacter(src) end)
    if ok2 and type(char) == 'table' then return char.id end
    return nil
end

local function srcOf(userId)
    local ok, s = pcall(function() return exports[PH]:GetSource(userId) end)
    return (ok and s) or nil
end

local function clean(s)
    s = s:gsub('%^%d', '')                       -- scoate codurile de culoare ^1..^9
    s = s:gsub('[%z\1-\9\11\12\14-\31]', '')     -- scoate caractere de control
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    return s:sub(1, Config.MessageMaxLength)
end

local function isStaff(src)
    local ok, r = pcall(function()
        return exports[PH]:HasStaffRank(src, Config.PremiumChat.MinStaffGrade)
    end)
    return ok and r == true
end

local function hasSub(userId)
    if not userId then return false end
    local ok, r = pcall(function() return exports['ph_subscriptions']:HasSubscription(userId) end)
    return ok and r == true
end

-- ----------------------------------------------------------
--  Optiuni de chat per user  (Lines 5..20 + Premium Chat vizibil/ascuns)
--  persistate in users.chat_lines / users.pc_hidden
-- ----------------------------------------------------------
local SETTINGS = {}   -- [userId] = { lines = 10, pcHidden = false }

local function clampLines(n)
    n = math.floor(tonumber(n) or Config.VisibleLines)
    if n < Config.LinesMin then n = Config.LinesMin end
    if n > Config.LinesMax then n = Config.LinesMax end
    return n
end

local function clampScale(n)
    n = math.floor(tonumber(n) or Config.ScaleDefault)
    if n < Config.ScaleMin then n = Config.ScaleMin end
    if n > Config.ScaleMax then n = Config.ScaleMax end
    return n
end

--- payload standard pentru evenimentul ph_chat:options
local function optionsPayload(src, uid, st)
    return {
        lines      = st.lines,
        pcHidden   = st.pcHidden,
        scale      = st.scale,
        canPC      = isStaff(src) or hasSub(uid),
        linesMin   = Config.LinesMin,
        linesMax   = Config.LinesMax,
        scaleMin   = Config.ScaleMin,
        scaleMax   = Config.ScaleMax,
        scaleStep  = Config.ScaleStep,
        scrollback = Config.ScrollbackLines,
    }
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(200) end
    while GetResourceState(PH) ~= 'started' do Wait(200) end

    local ok = pcall(function()
        MySQL.query.await([[
            ALTER TABLE `users`
              ADD COLUMN IF NOT EXISTS `chat_lines` SMALLINT   NOT NULL DEFAULT 10,
              ADD COLUMN IF NOT EXISTS `pc_hidden`  TINYINT(1)  NOT NULL DEFAULT 0,
              ADD COLUMN IF NOT EXISTS `chat_scale` SMALLINT   NOT NULL DEFAULT 100
        ]])
    end)
    if not ok then
        for _, col in ipairs({
            { 'chat_lines', "SMALLINT NOT NULL DEFAULT 10" },
            { 'pc_hidden',  "TINYINT(1) NOT NULL DEFAULT 0" },
            { 'chat_scale', "SMALLINT NOT NULL DEFAULT 100" },
        }) do
            pcall(function()
                local has = MySQL.scalar.await([[
                    SELECT COUNT(*) FROM information_schema.columns
                    WHERE table_schema = DATABASE() AND table_name = 'users' AND column_name = ?]], { col[1] })
                if (tonumber(has) or 0) == 0 then
                    MySQL.query.await(('ALTER TABLE `users` ADD COLUMN `%s` %s'):format(col[1], col[2]))
                end
            end)
        end
    end
end)

local function loadSettings(src, uid)
    local row
    pcall(function()
        row = MySQL.single.await('SELECT chat_lines, pc_hidden, chat_scale FROM users WHERE id = ?', { uid })
    end)
    local st = {
        lines    = clampLines(row and row.chat_lines),
        pcHidden = (row and tonumber(row.pc_hidden) or 0) ~= 0,
        scale    = clampScale(row and row.chat_scale),
    }
    SETTINGS[uid] = st
    TriggerClientEvent('ph_chat:options', src, optionsPayload(src, uid, st))
end

--- re-trimite optiunile (recalculeaza canPC) cand se schimba abonamentul
AddEventHandler('ph_subscriptions:bonusChanged', function(userId)
    local s = srcOf(userId)
    local st = s and SETTINGS[userId]
    if not s or not st then return end
    TriggerClientEvent('ph_chat:options', s, optionsPayload(s, userId, st))
end)

RegisterNetEvent('ph_chat:requestOptions', function()
    local src = source
    local uid = sqlId(src)
    if uid then loadSettings(src, uid) end
end)

RegisterNetEvent('ph_chat:setOption', function(opt)
    local src = source
    local uid = sqlId(src)
    if not uid then return end
    opt = opt or {}
    local st = SETTINGS[uid] or { lines = Config.VisibleLines, pcHidden = false, scale = Config.ScaleDefault }
    if opt.lines ~= nil then st.lines = clampLines(opt.lines) end
    if opt.pcHidden ~= nil then st.pcHidden = opt.pcHidden == true end
    if opt.scale ~= nil then st.scale = clampScale(opt.scale) end
    st.scale = st.scale or Config.ScaleDefault
    SETTINGS[uid] = st
    MySQL.update('UPDATE users SET chat_lines = ?, pc_hidden = ?, chat_scale = ? WHERE id = ?',
        { st.lines, st.pcHidden and 1 or 0, st.scale, uid })
end)

-- ----------------------------------------------------------
--  Mesaje normale de la jucatori
-- ----------------------------------------------------------
RegisterNetEvent('ph_chat:submit', function(raw)
    local src = source
    if type(raw) ~= 'string' then return end

    local msg = clean(raw)
    if msg == '' then return end

    local name = GetPlayerName(src) or ('Player_' .. src)
    local id = sqlId(src)
    local prefix = (Config.ShowIdInChat and id) and ('[%s] %s'):format(id, name) or name

    TriggerClientEvent('ph_chat:receive', -1, {
        stamp = roStamp(),
        prefix = prefix,
        prefixColor = colorFor(id or 0),
        text = msg,
        textColor = '#e8e6f0',
    })

    TriggerEvent('chatMessage', src, name, msg)   -- compat cu resurse care asculta `chatMessage`
    print(('[chat] %s: %s'):format(name, msg))
end)

-- ----------------------------------------------------------
--  Comenzile / (/pc) sunt in  commands.lua .
--  Helperele de care au nevoie se dau prin tabelul global CHATENV.
-- ----------------------------------------------------------
CHATENV = {
    PH       = PH,
    clean    = clean,
    sqlId    = sqlId,
    srcOf    = srcOf,
    isStaff  = isStaff,
    hasSub   = hasSub,
    roStamp  = roStamp,
    settings = function() return SETTINGS end,
}

-- ----------------------------------------------------------
--  Conectare: anunt public + mesaje private de bun venit
-- ----------------------------------------------------------
AddEventHandler('ph-core:playerLoaded', function(src, char)
    local uid = char and char.id

    -- anunt public
    TriggerClientEvent('ph_chat:receive', -1, {
        stamp = roStamp(),
        text = ('%s [ID: %s] has connected.'):format(
            (char and char.username) or GetPlayerName(src) or src, uid or '?'),
        textColor = '#8ce07a',
    })

    -- optiuni de chat
    if uid then loadSettings(src, uid) end

    -- mesaje private (doar pentru el)
    local function line(text, color)
        TriggerClientEvent('ph_chat:receive', src, { stamp = roStamp(), text = text, textColor = color or '#e8e6f0' })
    end
    local function seg(segments)
        TriggerClientEvent('ph_chat:receive', src, { stamp = roStamp(), segments = segments })
    end

    line('You have logged in to Purple Havoc Community', '#cfc9e6')

    if uid then
        local subs
        pcall(function() subs = exports['ph_subscriptions']:GetSubscriptions(uid) end)
        if type(subs) == 'table' then
            if subs.gold and subs.gold.active then
                seg({ { t = 'You have a ', c = '#cfc9e6' }, { t = 'Gold', c = '#FCD600' }, { t = ' subscription', c = '#cfc9e6' } })
            end
            if subs.platinum and subs.platinum.active then
                seg({ { t = 'You have a ', c = '#cfc9e6' }, { t = 'Platinum', c = '#8F00FC' }, { t = ' subscription', c = '#cfc9e6' } })
            end
        end
    end

    if isStaff(src) then
        line('Staff: loading permissions...', '#7f30ff')
        SetTimeout(700, function()
            local pub = exports[PH]:GetPublicPlayer(src)
            local key = pub and pub.staff
            if key and key ~= '' then
                seg({ { t = 'Staff: ', c = '#7f30ff' }, { t = '#' .. key, c = (pub.staffColor or '#37ff00') }, { t = ' permission = true', c = '#37ff00' } })
            end
        end)
    end
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    TriggerClientEvent('ph_chat:receive', -1, {
        stamp = roStamp(),
        text = ('%s has disconnected (%s)'):format(
            GetPlayerName(src) or ('Player_' .. src), reason or 'quit'),
        textColor = '#e07a7a',
    })
    local uid = sqlId(src)
    if uid then SETTINGS[uid] = nil end
end)

-- sugestii de comenzi
AddEventHandler('ph-core:playerLoaded', function(src)
    TriggerClientEvent('chat:addSuggestion', src, '/pc', 'Premium Chat (subscribers / staff)', { { name = 'message' } })
end)

-- ----------------------------------------------------------
--  Export server -> chat
--  target: -1 pentru toti, sau un server id
-- ----------------------------------------------------------
exports('send', function(target, payload)
    TriggerClientEvent('ph_chat:receive', target or -1, payload)
end)

--- varianta pe SQL id
exports('sendToUser', function(userId, payload)
    local s = srcOf(userId)
    if s then TriggerClientEvent('ph_chat:receive', s, payload) end
end)
