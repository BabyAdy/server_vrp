-- ==========================================================
--  ph_clans / client  (Faza 2)
--
--  - NUI-ul meniului /clan (7 tab-uri).  Comenzile ( /clan /clanmenu /cvr )
--    sunt in clan_cmd.lua (conform conventiei de layout).
--  - Vehiculele de clan : entitati "mission" (ph_world nu le sterge) cu un
--    lacat de sofer.  Spawn cerut de server, net id trimis inapoi; despawn
--    prin net id; auto-despawn cand raman goale prea mult.
-- ==========================================================
local RES = GetCurrentResourceName()

local menuOpen = false
local MY_CLAN  = 0                 -- clan-id-ul meu (pentru lacatul de sofer)
local MY_CV    = {}                -- [vehId] = { veh, netId, emptySince = os.time()|0 }

-- ----------------------------------------------------------
--  Clan-id primit de la server
-- ----------------------------------------------------------
RegisterNetEvent('ph_clans:cl:clan', function(clanId)
    MY_CLAN = tonumber(clanId) or 0
end)

-- ----------------------------------------------------------
--  NUI : deschidere / date / inchidere
-- ----------------------------------------------------------
RegisterNetEvent('ph_clans:cl:openMenu', function(data)
    if data and data.clan and data.clan.id then MY_CLAN = data.clan.id end
    menuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })
end)

RegisterNetEvent('ph_clans:cl:menuData', function(data)
    if data and data.clan and data.clan.id then MY_CLAN = data.clan.id end
    SendNUIMessage({ action = 'data', data = data })
end)

local function closeMenu()
    menuOpen = false
    SetNuiFocus(false, false)
end

RegisterNUICallback('close', function(_, cb)
    closeMenu()
    cb('ok')
end)

RegisterNUICallback('menu', function(d, cb)
    TriggerServerEvent('ph_clans:sv:menu', d or {})
    cb('ok')
end)

-- inchide cu ESC / Backspace
CreateThread(function()
    while true do
        if menuOpen then
            if IsControlJustReleased(0, 322) or IsControlJustReleased(0, 177) then
                closeMenu()
                SendNUIMessage({ action = 'forceClose' })
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- ----------------------------------------------------------
--  Vehicule de clan : spawn / despawn
-- ----------------------------------------------------------
local function applyProps(veh, props)
    if type(props) ~= 'table' then return end
    if props.primary then SetVehicleColours(veh, props.primary, props.secondary or props.primary) end
    if props.plateText then SetVehicleNumberPlateText(veh, tostring(props.plateText):sub(1, 8)) end
    if type(props.mods) == 'table' then
        SetVehicleModKit(veh, 0)
        for slot, val in pairs(props.mods) do SetVehicleMod(veh, tonumber(slot), val, false) end
    end
end

RegisterNetEvent('ph_clans:cl:spawnClanVehicle', function(d)
    d = d or {}
    local hash = type(d.model) == 'string' and GetHashKey(d.model) or d.model
    if not hash or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        return TriggerServerEvent('ph_clans:sv:clanVehSpawned', d.vehId, 0)
    end
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) and t < 200 do Wait(10) t = t + 1 end
    if not HasModelLoaded(hash) then
        return TriggerServerEvent('ph_clans:sv:clanVehSpawned', d.vehId, 0)
    end

    local ped = PlayerPedId()
    local fwd = GetOffsetFromEntityInWorldCoords(ped, 0.0, 4.5, 0.0)
    local h   = GetEntityHeading(ped) + 90.0
    local gz  = fwd.z
    local ok, z = GetGroundZFor_3dCoord(fwd.x + 0.0, fwd.y + 0.0, fwd.z + 2.0, false)
    if ok and type(z) == 'number' then gz = z + 1.0 end

    local veh = CreateVehicle(hash, fwd.x, fwd.y, gz, h, true, false)
    SetModelAsNoLongerNeeded(hash)
    local tries = 0
    while not DoesEntityExist(veh) and tries < 50 do Wait(10) tries = tries + 1 end
    if not DoesEntityExist(veh) then
        return TriggerServerEvent('ph_clans:sv:clanVehSpawned', d.vehId, 0)
    end

    SetEntityAsMissionEntity(veh, true, true)            -- ph_world nu il sterge
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetVehicleNumberPlateText(veh, d.plate or 'PH')
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleOnGroundProperly(veh)
    SetVehicleEngineOn(veh, false, true, true)
    applyProps(veh, d.props)
    if Config.ApplyUpgradeMods then pcall(Config.ApplyUpgradeMods, veh, d.upgrade or 0) end

    local ent = Entity(veh)
    ent.state:set('clan', d.clanId or MY_CLAN, true)     -- folosit de lacatul de sofer
    ent.state:set('clanveh', d.vehId, true)              -- folosit la curatarea orfanilor

    local netId = NetworkGetNetworkIdFromEntity(veh)
    SetNetworkIdCanMigrate(netId, true)
    MY_CV[d.vehId] = { veh = veh, netId = netId, emptySince = 0 }
    TriggerServerEvent('ph_clans:sv:clanVehSpawned', d.vehId, netId)

    if IsVehicleSeatFree(veh, -1) then SetPedIntoVehicle(ped, veh, -1) end
end)

RegisterNetEvent('ph_clans:cl:despawnClanVehicle', function(netId)
    if not netId or netId == 0 then return end
    local veh = NetworkDoesNetworkIdExist(netId) and NetworkGetEntityFromNetworkId(netId) or 0
    if veh ~= 0 and DoesEntityExist(veh) then
        SetEntityAsMissionEntity(veh, true, true)
        DeleteEntity(veh)
    end
    for id, cv in pairs(MY_CV) do
        if cv.netId == netId then MY_CV[id] = nil end
    end
end)

-- ----------------------------------------------------------
--  Lacat de sofer : doar membrii clanului conduc vehiculul de clan
-- ----------------------------------------------------------
CreateThread(function()
    while true do
        local wait = 800
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
            local ok, vc = pcall(function() return Entity(veh).state.clan end)
            vc = ok and vc or nil
            if vc and vc ~= 0 and MY_CLAN ~= 0 and vc ~= MY_CLAN then
                wait = 0
                local moved = false
                for seat = 0, GetVehicleMaxNumberOfPassengers(veh) - 1 do
                    if IsVehicleSeatFree(veh, seat) then
                        SetPedIntoVehicle(ped, veh, seat)
                        moved = true
                        break
                    end
                end
                if not moved then TaskLeaveVehicle(veh, 16) end
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('You cannot drive a clan vehicle that is not yours.')
                EndTextCommandDisplayHelp(0, false, true, -1)
            end
        end
        Wait(wait)
    end
end)

-- ----------------------------------------------------------
--  Auto-despawn : raporteaza serverul cand un vehicul de clan spawnat de
--  mine sta gol de peste Config.VehDespawnMin minute
-- ----------------------------------------------------------
CreateThread(function()
    local idleSec = (tonumber(Config.VehDespawnMin) or 15) * 60
    while true do
        Wait(30000)
        local now = os.time()
        for vehId, cv in pairs(MY_CV) do
            local veh = cv.veh
            if not veh or not DoesEntityExist(veh) then
                MY_CV[vehId] = nil
            else
                local occupied = false
                for seat = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
                    if not IsVehicleSeatFree(veh, seat) then occupied = true break end
                end
                if occupied then
                    cv.emptySince = 0
                else
                    if cv.emptySince == 0 then cv.emptySince = now
                    elseif now - cv.emptySince >= idleSec then
                        TriggerServerEvent('ph_clans:sv:vehEmpty', vehId)
                        MY_CV[vehId] = nil
                    end
                end
            end
        end
    end
end)

-- ----------------------------------------------------------
--  La repornirea resursei : curata vehiculele de clan orfane
-- ----------------------------------------------------------
AddEventHandler('onClientResourceStart', function(res)
    if res ~= RES then return end
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local ok, tag = pcall(function() return Entity(veh).state.clanveh end)
        if ok and tag then
            SetEntityAsMissionEntity(veh, true, true)
            DeleteEntity(veh)
        end
    end
end)

AddEventHandler('onClientResourceStop', function(res)
    if res ~= RES then return end
    if menuOpen then SetNuiFocus(false, false) end
    for _, cv in pairs(MY_CV) do
        if cv.veh and DoesEntityExist(cv.veh) then
            SetEntityAsMissionEntity(cv.veh, true, true)
            DeleteEntity(cv.veh)
        end
    end
end)
