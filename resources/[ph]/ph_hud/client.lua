local RES = GetCurrentResourceName()

local hudReady = false
local data = { id = 0, name = '-', money = 0, bank = 0, level = 1 }
local online = 1
local needs = { hunger = Config.Needs.start, thirst = Config.Needs.start }
local paycheckLeft = Config.Paycheck.intervalSec
local statuses = {}   -- [id] = { label, value, expiresAt (GetGameTimer ms) | nil }

-- baza de timp real Romania, trimisa de server (epoch UTC + offset ore);
-- interpolam local intre update-uri. `os` nu exista pe client, deci calculam manual.
local timeBase = { epoch = 0, offset = 2, at = GetGameTimer() }

RegisterNetEvent('ph_hud:time', function(epoch, offset)
    timeBase = { epoch = tonumber(epoch) or 0, offset = tonumber(offset) or 2, at = GetGameTimer() }
end)

-- zile de la 1970-01-01 -> an, luna, zi (algoritmul civil al lui H. Hinnant)
local function civilFromDays(z)
    z = z + 719468
    local era = math.floor((z >= 0 and z or (z - 146096)) / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = (mp < 10) and (mp + 3) or (mp - 9)
    if m <= 2 then y = y + 1 end
    return y, m, d
end

--- Data/ora curenta Bucuresti ca tabel { year, month, day, hour, min, wday(0=Duminica) }
local function romaniaNow()
    if timeBase.epoch == 0 then return nil end
    local secs = timeBase.epoch
        + timeBase.offset * 3600
        + math.floor((GetGameTimer() - timeBase.at) / 1000)

    local days = math.floor(secs / 86400)
    local rem = secs % 86400
    local y, m, d = civilFromDays(days)
    return {
        year = y, month = m, day = d,
        hour = math.floor(rem / 3600),
        min = math.floor((rem % 3600) / 60),
        wday = (days % 7 + 4) % 7,   -- 1970-01-01 = Joi ; 0=Duminica .. 6=Sambata
    }
end

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
local function fmtClock(sec)
    if sec < 0 then sec = 0 end
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = math.floor(sec % 60)
    if h > 0 then
        return ('%d:%02d:%02d'):format(h, m, s)
    end
    return ('%02d:%02d'):format(m, s)
end

local function pushStatic()
    SendNUIMessage({
        type = 'static',
        id = data.id, name = data.name, level = data.level,
        money = data.money, bank = data.bank,
        online = online, server = Config.ServerName,
    })
end

-- ----------------------------------------------------------
--  Legatura cu ph-core
-- ----------------------------------------------------------
AddEventHandler('ph-core:client:playerLoaded', function(char)
    if type(char) ~= 'table' then return end
    data.id    = char.id or 0
    data.name  = char.username or GetPlayerName(PlayerId())
    data.money = char.money or 0
    data.bank  = char.bank or 0
    data.level = char.level or 1

    hudReady = true
    SendNUIMessage({ type = 'show' })
    pushStatic()
    TriggerServerEvent('ph_hud:requestOnline')
end)

AddEventHandler('ph-core:client:dataChanged', function(key, value)
    if key == 'money' then data.money = value
    elseif key == 'bank' then data.bank = value
    elseif key == 'level' then data.level = value
    else return end
    pushStatic()
end)

RegisterNetEvent('ph_hud:online', function(n)
    online = tonumber(n) or online
    pushStatic()
end)

-- ----------------------------------------------------------
--  API status (RENTED VEHICLE / WEARING HOOD / OIL EXTRACTION ...)
-- ----------------------------------------------------------
local function addStatus(id, label, opts)
    opts = opts or {}
    statuses[tostring(id)] = {
        label = tostring(label or id),
        value = opts.value,
        expiresAt = opts.durationSec and (GetGameTimer() + math.floor(opts.durationSec * 1000)) or nil,
    }
end

local function removeStatus(id)
    statuses[tostring(id)] = nil
end

exports('addStatus', addStatus)
exports('removeStatus', removeStatus)

RegisterNetEvent('ph_hud:status', function(action, id, label, opts)
    if action == 'add' then addStatus(id, label, opts)
    elseif action == 'remove' then removeStatus(id) end
end)

-- ----------------------------------------------------------
--  Loop principal (bare, ceas, status)
-- ----------------------------------------------------------
CreateThread(function()
    while true do
        Wait(Config.RefreshMs)
        if not (hudReady and exports['ph-core']:IsLoaded()) then goto continue end

        local ped = PlayerPedId()

        local rawHp = GetEntityHealth(ped)
        local maxHp = GetEntityMaxHealth(ped)
        local hp = 0
        if maxHp > 100 then
            hp = math.floor(math.max(0, rawHp - 100) / (maxHp - 100) * 100 + 0.5)
        end
        local armor = math.floor(GetPedArmour(ped) + 0.5)

        local rt = romaniaNow()
        local timeStr, dateStr = '--:--', '...'
        if rt then
            timeStr = ('%02d:%02d'):format(rt.hour, rt.min)
            dateStr = ('%s, %d %s'):format(
                Config.Days[rt.wday] or '?', rt.day, Config.Months[rt.month - 1] or '?')
        end

        -- status list cu timp ramas
        local now = GetGameTimer()
        local list = {}
        for sid, st in pairs(statuses) do
            local remain
            if st.expiresAt then
                remain = math.floor((st.expiresAt - now) / 1000)
                if remain <= 0 then
                    statuses[sid] = nil
                    goto skip
                end
            end
            list[#list + 1] = { label = st.label, value = st.value, remain = remain }
            ::skip::
        end

        SendNUIMessage({
            type = 'tick',
            hp = hp,
            armor = armor,
            hunger = math.floor(needs.hunger + 0.5),
            thirst = math.floor(needs.thirst + 0.5),
            time = timeStr,
            date = dateStr,
            talking = NetworkIsPlayerTalking(PlayerId()) == 1 or NetworkIsPlayerTalking(PlayerId()) == true,
            paycheck = fmtClock(paycheckLeft),
            statuses = list,
        })

        ::continue::
    end
end)

-- ----------------------------------------------------------
--  Countdown salariu + decadere nevoi (1s)
-- ----------------------------------------------------------
CreateThread(function()
    while true do
        Wait(1000)
        if hudReady then
            paycheckLeft = paycheckLeft - 1
            if paycheckLeft <= 0 then
                paycheckLeft = Config.Paycheck.intervalSec
                TriggerServerEvent('ph_hud:paycheckDue')
            end

            if Config.Needs.enable then
                needs.hunger = math.max(0, needs.hunger - Config.Needs.decayPerMin.hunger / 60)
                needs.thirst = math.max(0, needs.thirst - Config.Needs.decayPerMin.thirst / 60)
            end
        end
    end
end)

-- ----------------------------------------------------------
--  Ascunde afisajul de bani nativ
-- ----------------------------------------------------------
CreateThread(function()
    while true do
        if hudReady and Config.HideNativeCash then
            HideHudComponentThisFrame(3)   -- CASH
            HideHudComponentThisFrame(4)   -- MP_CASH
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ----------------------------------------------------------
--  Comanda de test
-- ----------------------------------------------------------
RegisterCommand('hudtest', function()
    addStatus('rent', 'RENTED VEHICLE', { durationSec = 3300 })
    addStatus('hood', 'WEARING HOOD')
    addStatus('oil', 'OIL EXTRACTION', { durationSec = 6600 })
end, false)
