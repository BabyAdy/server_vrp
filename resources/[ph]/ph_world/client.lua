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
