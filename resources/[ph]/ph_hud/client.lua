local RES = GetCurrentResourceName()

local hudReady = false
local data = { id = 0, name = '-', money = 0, bank = 0, level = 1 }
local online = 1
local needs = { hunger = Config.Needs.start, thirst = Config.Needs.start }
local paycheckLeft = Config.Paycheck.intervalSec
local statuses = {}   -- [id] = { label, value, expiresAt (GetGameTimer ms) | nil }

-- baza de timp real Romania, trimisa de server; interpolam local intre update-uri
local timeBase = { epoch = os.time(), offset = 2, at = GetGameTimer() }

RegisterNetEvent('ph_hud:time', function(epoch, offset)
    timeBase = { epoch = tonumber(epoch) or os.time(), offset = tonumber(offset) or 2, at = GetGameTimer() }
end)

--- Data/ora curenta pentru Bucuresti, ca tabel os.date
local function romaniaNow()
    local secs = timeBase.epoch + math.floor((GetGameTimer() - timeBase.at) / 1000)
    return os.date('!*t', secs + timeBase.offset * 3600)
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
        -- os.date wday: 1=Duminica..7=Sambata ; month: 1..12
        local dowName = Config.Days[(rt.wday - 1) % 7] or '?'
        local monName = Config.Months[rt.month - 1] or '?'

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
            time = ('%02d:%02d'):format(rt.hour, rt.min),
            date = ('%s, %d %s'):format(dowName, rt.day, monName),
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
