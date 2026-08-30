-- ==========================================================
--  Timp real Bucuresti / Romania (EET / EEST cu DST UE)
-- ==========================================================
local function dow(y, m, d)                       -- 0=Duminica .. 6=Sambata (Sakamoto)
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

--- DST UE: din ultima duminica din martie 01:00 UTC pana in ultima duminica din octombrie 01:00 UTC
local function euDstActive(u)                     -- u = os.date('!*t')
    if u.month < 3 or u.month > 10 then return false end
    if u.month > 3 and u.month < 10 then return true end
    if u.month == 3 then
        local ml = lastSunday(u.year, 3)
        return (u.day > ml) or (u.day == ml and u.hour >= 1)
    end
    local ol = lastSunday(u.year, 10)            -- u.month == 10
    return (u.day < ol) or (u.day == ol and u.hour < 1)
end

--- @return epoch (UTC, secunde), offset (ore) pentru Romania
local function romaniaClock()
    local epoch = os.time()
    local u = os.date('!*t', epoch)
    local offset = 2 + (euDstActive(u) and 1 or 0)
    return epoch, offset
end

local function pushTime(target)
    local epoch, offset = romaniaClock()
    TriggerClientEvent('ph_hud:time', target or -1, epoch, offset)
end

-- ----------------------------------------------------------
--  Numar de jucatori online + timp -> catre clienti
-- ----------------------------------------------------------
local function broadcastOnline(target)
    TriggerClientEvent('ph_hud:online', target or -1, #GetPlayers())
end

CreateThread(function()
    while true do
        broadcastOnline(-1)
        pushTime(-1)
        Wait(Config.OnlineRefreshMs)
    end
end)

RegisterNetEvent('ph_hud:requestOnline', function()
    local src = source
    broadcastOnline(src)
    pushTime(src)
end)

-- ----------------------------------------------------------
--  Salariu (stub - sistemul propriu-zis vine mai tarziu)
-- ----------------------------------------------------------
RegisterNetEvent('ph_hud:paycheckDue', function()
    local src = source
    -- exemplu viitor:
    -- exports['ph-core']:AddMoney(src, 'bank', 500)
    -- exports['ph_chat']:send(src, { text = 'Ai primit salariul: $500', textColor = '#8ce07a' })
    if Config and Config.Debug then
        print(('[ph_hud] paycheck due pentru src %s'):format(src))
    end
end)

-- ----------------------------------------------------------
--  Export server: seteaza / sterge un status pentru un jucator
--  exports['ph_hud']:setStatus(src, 'rent', 'RENTED VEHICLE', { durationSec = 3300 })
-- ----------------------------------------------------------
exports('setStatus', function(src, id, label, opts)
    TriggerClientEvent('ph_hud:status', src, 'add', id, label, opts)
end)

exports('clearStatus', function(src, id)
    TriggerClientEvent('ph_hud:status', src, 'remove', id)
end)
