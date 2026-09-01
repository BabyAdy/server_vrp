-- ==========================================================
--  ph_world - server gol
--  Fara NPC-uri (pietoni, politie, scenarii), fara trafic ambient
--  (masini, parcate, camioane de gunoi, trenuri, barci).
--  Vehiculele jucatorilor / factiunilor sunt marcate ca "mission entity"
--  la spawn, deci NU se sterg de aici.
-- ==========================================================

local CLEAN_INTERVAL = 750   -- ms

-- ----------------------------------------------------------
--  Blocheaza aparitia de entitati ambientale (fiecare frame)
-- ----------------------------------------------------------
CreateThread(function()
    -- bugete de populatie la minim
    SetPedPopulationBudget(0)
    SetVehiclePopulationBudget(0)

    while true do
        SetPedDensityMultiplierThisFrame(0.0)
        SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
        SetVehicleDensityMultiplierThisFrame(0.0)
        SetRandomVehicleDensityMultiplierThisFrame(0.0)
        SetParkedVehicleDensityMultiplierThisFrame(0.0)
        SetAmbientVehicleRangeMultiplierThisFrame(0.0)
        Wait(0)
    end
end)

-- ----------------------------------------------------------
--  Setari one-time (se reaplica la schimbarea de sesiune)
-- ----------------------------------------------------------
local function applyWorldSettings()
    SetGarbageTrucks(false)
    SetRandomBoats(false)
    SetRandomTrains(false)
    SetCreateRandomCops(false)
    SetCreateRandomCopsNotOnScenarios(false)
    SetCreateRandomCopsOnScenarios(false)
    DistantCopCarSirens(false)
    SetPoliceIgnorePlayer(PlayerId(), true)
    SetDispatchCopsForPlayer(PlayerId(), false)
    for i = 1, 15 do EnableDispatchService(i, false) end
end

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(200) end
    applyWorldSettings()
end)

AddEventHandler('ph-core:client:playerLoaded', applyWorldSettings)

-- ----------------------------------------------------------
--  Curatare periodica a ce a mai aparut totusi
-- ----------------------------------------------------------
local function isPlayerVehicle(veh)
    for _, p in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(p)
        if ped ~= 0 and GetVehiclePedIsIn(ped, false) == veh then return true end
        if ped ~= 0 and GetVehiclePedIsIn(ped, true) == veh then return true end
    end
    return false
end

CreateThread(function()
    while true do
        Wait(CLEAN_INTERVAL)

        -- pietoni: sterge tot ce nu e jucator si nu e "mission entity"
        for _, ped in ipairs(GetGamePool('CPed')) do
            if DoesEntityExist(ped) and not IsPedAPlayer(ped) and not IsEntityAMissionEntity(ped) then
                SetEntityAsMissionEntity(ped, true, true)
                DeleteEntity(ped)
            end
        end

        -- vehicule: pastreaza doar mission entities (spawn de jucator/factiune)
        -- si vehiculele in care sta cineva
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            if DoesEntityExist(veh)
               and not IsEntityAMissionEntity(veh)
               and not isPlayerVehicle(veh) then
                SetEntityAsMissionEntity(veh, true, true)
                DeleteEntity(veh)
            end
        end
    end
end)

-- ==========================================================
--  TIMP & VREME  (stare autoritara pe server -> ph_world/server.lua)
--    /time    [HH:MM | HH]   (staff >= Config.StaffPerm)
--    /weather [type]         (staff >= Config.StaffPerm)
-- ==========================================================
local SECS_PER_GAME_MIN = (Config.Time and Config.Time.RealSecondsPerGameMinute) or 2.0

local timeState = {
    h = (Config.Time and Config.Time.StartHour) or 12,
    m = (Config.Time and Config.Time.StartMinute) or 0,
    running = not (Config.Time and Config.Time.KeepRunning == false),
}
local timeAcc = 0.0   -- secunde reale acumulate spre urmatorul minut de joc

RegisterNetEvent('ph_world:cl:syncTime', function(h, m, running)
    timeState.h = tonumber(h) or timeState.h
    timeState.m = tonumber(m) or timeState.m
    timeState.running = running == true
    timeAcc = 0.0
end)

-- ceasul: override in fiecare frame ca toti clientii sa arate la fel
CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(200) end
    -- cere starea curenta (in caz ca resursa a pornit dupa ce jucatorul era deja in joc)
    TriggerServerEvent('ph_world:sv:reqSync')

    while true do
        Wait(0)
        if timeState.running then
            timeAcc = timeAcc + GetFrameTime()
            while timeAcc >= SECS_PER_GAME_MIN do
                timeAcc = timeAcc - SECS_PER_GAME_MIN
                timeState.m = timeState.m + 1
                if timeState.m >= 60 then
                    timeState.m = 0
                    timeState.h = (timeState.h + 1) % 24
                end
            end
        end
        local secs = math.floor((timeAcc / SECS_PER_GAME_MIN) * 60) % 60
        NetworkOverrideClockTime(timeState.h, timeState.m, secs)
    end
end)

AddEventHandler('ph-core:client:playerLoaded', function()
    TriggerServerEvent('ph_world:sv:reqSync')
end)

-- ----------------------------------------------------------
--  Vreme
-- ----------------------------------------------------------
local currentWeather = (Config.Weather and Config.Weather.Start) or 'EXTRASUNNY'

local function applyWeather(w, transitionSec)
    currentWeather = w
    if transitionSec and transitionSec > 0 then
        SetWeatherTypeOverTime(w, transitionSec + 0.0)
        SetTimeout(math.floor(transitionSec * 1000) + 200, function()
            if currentWeather == w then SetWeatherTypeNowPersist(w) end
        end)
    else
        ClearOverrideWeather()
        ClearWeatherTypePersist()
        SetWeatherTypeNowPersist(w)
        SetWeatherTypeNow(w)
        SetWeatherTypePersist(w)
    end
end

RegisterNetEvent('ph_world:cl:syncWeather', function(w, transitionSec)
    if type(w) ~= 'string' or w == '' then return end
    applyWeather(w, tonumber(transitionSec) or 0)
end)

-- reaplica periodic ca sa nu porneasca ciclul automat de vreme din GTA
CreateThread(function()
    local every = (Config.Weather and Config.Weather.ReassertMs) or 30000
    while true do
        Wait(every)
        if currentWeather then
            SetWeatherTypeNowPersist(currentWeather)
            SetWeatherTypePersist(currentWeather)
        end
    end
end)

-- sugestii in chat
AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    TriggerEvent('chat:addSuggestion', '/time', 'Staff: set the world time', {
        { name = 'HH:MM', help = 'e.g. 21:30 or 8' },
    })
    local wtypes = (Config.Weather and Config.Weather.Types) or {}
    TriggerEvent('chat:addSuggestion', '/weather', 'Staff: set the world weather', {
        { name = 'type', help = table.concat(wtypes, ', ') },
    })
end)
