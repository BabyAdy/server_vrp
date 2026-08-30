-- ==========================================================
--  chat / server
--  Portat de pe vRP pe framework-ul Purple Havoc (ph-core).
--  Contractul catre NUI ramane identic: { time, rank, name, id, text }
-- ==========================================================

-- ----------------------------------------------------------
--  Ora Bucuresti / Romania (EET / EEST, cu DST UE) -> "HH:MM"
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

local function getTime()
    local epoch = os.time()
    local u = os.date('!*t', epoch)
    local offset = 2 + (euDstActive(u) and 1 or 0)
    local b = os.date('!*t', epoch + offset * 3600)
    return ('%02d:%02d'):format(b.hour, b.min)
end

-- ----------------------------------------------------------
--  Date jucator din ph-core
-- ----------------------------------------------------------
local function getCharacter(src)
    local ok, char = pcall(function()
        return exports['ph-core']:GetCharacter(src)
    end)
    if ok and type(char) == 'table' then return char end
    return nil
end

--- Label-ul gradului de staff (users.staff) sau nil pentru jucator normal
local function getPlayerRank(char)
    if not char or not char.staff or char.staff == '' then return nil end
    local ok, g = pcall(function()
        return exports['ph-core']:GetStaffGrade(char.staff)
    end)
    if ok and type(g) == 'table' then return g.label end
    return nil
end

local function sanitize(msg)
    msg = tostring(msg or '')
    msg = msg:gsub('[\r\n\t]', ' ')
    msg = msg:gsub('%s+', ' ')
    msg = msg:gsub('^%s+', ''):gsub('%s+$', '')
    if #msg > 256 then
        msg = msg:sub(1, 256)
    end
    return msg
end

-- rate limit (inlocuieste statebag-ul vRP)
local lastSend = {}

RegisterNetEvent('chat:sendMessage', function(raw)
    local src = source
    if type(raw) ~= 'string' then return end

    local text = sanitize(raw)
    if text == '' then return end

    local char = getCharacter(src)
    if not char then return end

    -- rate limit
    local now = os.time()
    if now - (lastSend[src] or 0) < 1 then return end
    lastSend[src] = now

    local payload = {
        time = getTime(),
        rank = getPlayerRank(char),
        name = char.username or GetPlayerName(src),
        id   = char.id,
        text = text,
    }

    TriggerClientEvent('chat:addMessage', -1, payload)
    TriggerEvent('chatMessage', src, payload.name, text)   -- compat cu resurse care asculta `chatMessage`
end)

AddEventHandler('playerDropped', function()
    lastSend[source] = nil
end)

RegisterCommand('clearchat', function(src)
    if src == 0 then
        TriggerClientEvent('chat:clear', -1)
        return
    end
    if IsPlayerAceAllowed(src, 'ph.admin') then
        TriggerClientEvent('chat:clear', -1)
    end
end, false)

exports('addMessage', function(payload)
    if type(payload) ~= 'table' then return end
    TriggerClientEvent('chat:addMessage', -1, {
        time = payload.time or getTime(),
        rank = payload.rank,
        name = payload.name or 'SYSTEM',
        id = payload.id or 0,
        text = payload.text or '',
    })
end)

print('^2[chat]^7 loaded (ph-core)')
