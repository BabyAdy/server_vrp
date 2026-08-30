local PALETTE = Config.NameColors

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

local function sqlId(src)
    local ok, char = pcall(function()
        return exports['ph-core']:GetCharacter(src)
    end)
    if ok and type(char) == 'table' then return char.id end
    return nil
end

local function clean(s)
    s = s:gsub('%^%d', '')                       -- scoate codurile de culoare ^1..^9
    s = s:gsub('[%z\1-\9\11\12\14-\31]', '')     -- scoate caractere de control
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    return s:sub(1, Config.MessageMaxLength)
end

-- ----------------------------------------------------------
--  Mesaje de la jucatori
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
        prefixColor = colorFor(id or src),
        text = msg,
        textColor = '#e8e6f0',
    })

    TriggerEvent('chatMessage', src, name, msg)   -- compat cu resurse care asculta `chatMessage`
    print(('[chat] %s: %s'):format(name, msg))
end)

-- ----------------------------------------------------------
--  Anunturi intrare / iesire
-- ----------------------------------------------------------
AddEventHandler('ph-core:playerLoaded', function(src, char)
    TriggerClientEvent('ph_chat:receive', -1, {
        stamp = roStamp(),
        text = ('%s [ID: %s] s-a conectat.'):format(
            (char and char.username) or GetPlayerName(src) or src,
            (char and char.id) or '?'),
        textColor = '#8ce07a',
    })
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    TriggerClientEvent('ph_chat:receive', -1, {
        stamp = roStamp(),
        text = ('%s s-a deconectat (%s)'):format(
            GetPlayerName(src) or ('Player_' .. src), reason or 'quit'),
        textColor = '#e07a7a',
    })
end)

-- ----------------------------------------------------------
--  Exports server -> chat
--  target: -1 pentru toti, sau un player id
-- ----------------------------------------------------------
exports('send', function(target, payload)
    TriggerClientEvent('ph_chat:receive', target or -1, payload)
end)
