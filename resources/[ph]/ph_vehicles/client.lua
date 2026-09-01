-- ==========================================================
--  ph_vehicles / client
--
--  - spawn / despawn vehicule personale (mission entity, altfel ph_world le sterge)
--  - tasta 2 = pornire/oprire motor (doar cu chei, la volan)
--  - tasta L = incuiere/descuiere ;  tasta B = centura (cu ejectare la impact)
--  - odometru + combustibil raportate la server
--  - meniul /v (NUI)
--  - alimenteaza HUD-ul (ph_hud) cu personal / locked / belt / odometer
--
--  Comenzile /v /park /givekey /throwkey sunt in commands.lua (server).
-- ==========================================================
local MYKEYS  = {}   -- [vehId] = true  (am chei)
local MYSPAWN = {}   -- [vehId] = entity  (vehicule create de acest client)
local ENG     = {}   -- [vehId] = bool   (motor dorit pornit)
local FUEL    = {}   -- [vehId] = 0..100
local ODO     = {}   -- [vehId] = metri
local DSENT   = {}   -- [vehId] = true   (raport de distrugere trimis)
local belt    = false
local menuOpen = false
local locBlip = nil
local locGen  = 0

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
local function feed(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(msg))
    EndTextCommandThefeedPostTicker(false, true)
end

local function vehIdOf(veh)
    if not veh or veh == 0 then return nil end
    local ok, v = pcall(function() return Entity(veh).state.phveh end)
    if ok and v then return tonumber(v) end
    return nil
end

local function findVehById(id)
    if MYSPAWN[id] and DoesEntityExist(MYSPAWN[id]) then return MYSPAWN[id] end
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if vehIdOf(veh) == id then return veh end
    end
    return nil
end

local function applyProps(veh, props)
    if type(props) ~= 'table' then return end
    if props.primary then SetVehicleColours(veh, props.primary, props.secondary or props.primary) end
    if props.plateText then SetVehicleNumberPlateText(veh, tostring(props.plateText):sub(1, 8)) end
    if type(props.mods) == 'table' then
        SetVehicleModKit(veh, 0)
        for slot, val in pairs(props.mods) do SetVehicleMod(veh, tonumber(slot), val, false) end
    end
end

local function pushHud(veh, id)
    local personal = id ~= nil
    local locked
    if personal then
        local ok, st = pcall(function() return Entity(veh).state.locked end)
        locked = (ok and st == true) or false
    end
    local info = {
        personal = personal,
        locked   = locked,
        belt     = belt,
        odoKm    = personal and (math.floor((ODO[id] or 0) / 100) / 10) or nil,
        plate    = personal and GetVehicleNumberPlateText(veh) or nil,
    }
    pcall(function() exports['ph_hud']:setVehicleInfo(info) end)
end

local function clearHud()
    pcall(function() exports['ph_hud']:clearVehicleInfo() end)
end

local function ejectThroughWindscreen(veh)
    local ped = PlayerPedId()
    local v = GetEntityVelocity(veh)
    local off = GetOffsetFromEntityInWorldCoords(veh, 0.0, 1.2, 0.4)
    SetEntityCoords(ped, off.x, off.y, off.z, false, false, false, false)
    SetEntityVelocity(ped, v.x, v.y, v.z)
    Wait(1)
    SetPedToRagdoll(ped, 5000, 5000, 0, false, false, false)
    ApplyDamageToPed(ped, Config.Seatbelt.ejectDamage, false)
    pcall(function() SmashVehicleWindow(veh, 6) end)
    feed('You were thrown from the vehicle!')
end

local function nearestLockableId()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then
        local id = vehIdOf(veh)
        if id and MYKEYS[id] then return id end
        return nil
    end
    local pc = GetEntityCoords(ped)
    local best, bestD
    for _, v in ipairs(GetGamePool('CVehicle')) do
        local id = vehIdOf(v)
        if id and MYKEYS[id] then
            local d = #(pc - GetEntityCoords(v))
            if d <= Config.LockRadius and (not bestD or d < bestD) then bestD, best = d, id end
        end
    end
    return best
end

-- ----------------------------------------------------------
--  Server -> client
-- ----------------------------------------------------------
RegisterNetEvent('ph_vehicles:cl:keys', function(list)
    MYKEYS = {}
    for _, id in ipairs(list or {}) do MYKEYS[tonumber(id)] = true end
end)

RegisterNetEvent('ph_vehicles:cl:spawn', function(d)
    local hash = GetHashKey(d.model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        TriggerServerEvent('ph_vehicles:sv:spawned', d.id, 0)
        return
    end
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) and t < 200 do Wait(10) t = t + 1 end
    if not HasModelLoaded(hash) then
        TriggerServerEvent('ph_vehicles:sv:spawned', d.id, 0)
        return
    end

    local veh = CreateVehicle(hash, d.x, d.y, d.z, d.h, true, false)
    SetModelAsNoLongerNeeded(hash)
    local tries = 0
    while not DoesEntityExist(veh) and tries < 50 do Wait(10) tries = tries + 1 end
    if not DoesEntityExist(veh) then
        TriggerServerEvent('ph_vehicles:sv:spawned', d.id, 0)
        return
    end

    SetEntityAsMissionEntity(veh, true, true)          -- ph_world nu il sterge
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetVehicleNumberPlateText(veh, d.plate or 'PH')
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleOnGroundProperly(veh)
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleDoorsLocked(veh, d.locked and 2 or 1)
    if Config.Fuel.enabled then SetVehicleFuelLevel(veh, (d.fuel or 100) + 0.0) end
    applyProps(veh, d.props)

    local ent = Entity(veh)
    ent.state:set('phveh', d.id, true)
    ent.state:set('owner', d.ownerId, true)
    ent.state:set('locked', d.locked and true or false, true)

    MYSPAWN[d.id] = veh
    ENG[d.id]  = false
    FUEL[d.id] = d.fuel or 100
    ODO[d.id]  = d.odo or 0
    DSENT[d.id] = nil

    local netId = NetworkGetNetworkIdFromEntity(veh)
    SetNetworkIdCanMigrate(netId, true)
    TriggerServerEvent('ph_vehicles:sv:spawned', d.id, netId)

    local ped = PlayerPedId()
    if #(GetEntityCoords(ped) - vector3(d.x, d.y, d.z)) < 8.0 and IsVehicleSeatFree(veh, -1) then
        SetPedIntoVehicle(ped, veh, -1)
    end
end)

RegisterNetEvent('ph_vehicles:cl:despawn', function(id)
    id = tonumber(id)
    local veh = findVehById(id)
    if veh and DoesEntityExist(veh) then
        SetEntityAsMissionEntity(veh, true, true)
        DeleteEntity(veh)
    end
    MYSPAWN[id] = nil ENG[id] = nil FUEL[id] = nil ODO[id] = nil DSENT[id] = nil
end)

RegisterNetEvent('ph_vehicles:cl:engine', function(id, on)
    id = tonumber(id)
    ENG[id] = on and true or false
    local veh = findVehById(id)
    if veh then SetVehicleEngineOn(veh, ENG[id], false, true) end
end)

RegisterNetEvent('ph_vehicles:cl:lock', function(id, locked)
    id = tonumber(id)
    local veh = findVehById(id)
    if veh then
        SetVehicleDoorsLocked(veh, locked and 2 or 1)
        pcall(function() Entity(veh).state:set('locked', locked and true or false, true) end)
    end
end)

RegisterNetEvent('ph_vehicles:cl:waypoint', function(c, label)
    if not c or not c.x then return end
    SetNewWaypoint(c.x + 0.0, c.y + 0.0)
    if locBlip and DoesBlipExist(locBlip) then RemoveBlip(locBlip) end
    locBlip = AddBlipForCoord(c.x + 0.0, c.y + 0.0, (c.z or 0.0) + 0.0)
    SetBlipSprite(locBlip, Config.Blip.sprite)
    SetBlipColour(locBlip, Config.Blip.color)
    SetBlipScale(locBlip, Config.Blip.scale)
    SetBlipRoute(locBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label or 'Vehicle')
    EndTextCommandSetBlipName(locBlip)
    locGen = locGen + 1
    local mine = locGen
    SetTimeout(180000, function()
        if mine == locGen and locBlip and DoesBlipExist(locBlip) then
            RemoveBlip(locBlip) locBlip = nil
        end
    end)
end)

RegisterNetEvent('ph_vehicles:cl:parkQuery', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return feed('You must be in your personal vehicle.') end
    local id = vehIdOf(veh)
    if not id then return feed('This is not a personal vehicle.') end
    if GetPedInVehicleSeat(veh, -1) ~= ped then return feed('You must be in the driver seat.') end
    if not MYKEYS[id] then return feed('You do not have keys to this vehicle.') end
    if ENG[id] == true then return feed('Turn the engine off first (press 2).') end
    local c = GetEntityCoords(veh)
    TriggerServerEvent('ph_vehicles:sv:parkSet', {
        id = id, x = c.x, y = c.y, z = c.z, h = GetEntityHeading(veh),
    })
end)

RegisterNetEvent('ph_vehicles:cl:giveKeyQuery', function(targetUid)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return feed('You must be sitting in your vehicle.') end
    local id = vehIdOf(veh)
    if not id then return feed('This is not a personal vehicle.') end
    TriggerServerEvent('ph_vehicles:sv:giveKey', { id = id, targetUid = targetUid })
end)

-- ----------------------------------------------------------
--  NUI  (/v)
-- ----------------------------------------------------------
RegisterNetEvent('ph_vehicles:cl:openMenu', function(data)
    menuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })
end)

RegisterNetEvent('ph_vehicles:cl:refresh', function(data)
    if not menuOpen then return end
    SendNUIMessage({ action = 'refresh', data = data })
end)

RegisterNUICallback('close', function(_, cb)
    menuOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('vAction', function(d, cb)
    TriggerServerEvent('ph_vehicles:sv:action', d or {})
    cb('ok')
end)

CreateThread(function()
    while true do
        if menuOpen then
            if IsControlJustReleased(0, 322) or IsControlJustReleased(0, 177) then
                menuOpen = false
                SetNuiFocus(false, false)
                SendNUIMessage({ action = 'forceClose' })
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- ----------------------------------------------------------
--  Keybindings  (raman aici, langa logica lor)
-- ----------------------------------------------------------
RegisterKeyMapping('+phSeatbelt', 'Toggle seatbelt', 'keyboard', Config.SeatbeltKey)
RegisterCommand('+phSeatbelt', function()
    if not Config.Seatbelt.enabled then return end
    if GetVehiclePedIsIn(PlayerPedId(), false) == 0 then return end
    belt = not belt
    feed(belt and '~g~Seatbelt fastened' or '~r~Seatbelt unfastened')
end, false)
RegisterCommand('-phSeatbelt', function() end, false)

RegisterKeyMapping('+phVehLock', 'Lock / unlock your personal vehicle', 'keyboard', Config.LockKey)
RegisterCommand('+phVehLock', function()
    local id = nearestLockableId()
    if id then TriggerServerEvent('ph_vehicles:sv:lock', id) end
end, false)
RegisterCommand('-phVehLock', function() end, false)

-- ----------------------------------------------------------
--  Bucla principala de vehicul
-- ----------------------------------------------------------
CreateThread(function()
    local lastKmh = 0.0
    local lastOdoCoords = nil
    local wasDriverId = nil
    local lastHudPush = 0
    local hudActive = false

    while true do
        local w = 500
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)

        if veh ~= 0 and IsPedInAnyVehicle(ped, false) then
            w = 0
            local id = vehIdOf(veh)
            local isDriver = GetPedInVehicleSeat(veh, -1) == ped
            local kmh = GetEntitySpeed(veh) * 3.6

            -- lacat de sofer: fara chei nu poti conduce un vehicul personal
            if id and isDriver and not MYKEYS[id] then
                local moved = false
                for seat = 0, GetVehicleMaxNumberOfPassengers(veh) - 1 do
                    if IsVehicleSeatFree(veh, seat) then
                        SetPedIntoVehicle(ped, veh, seat) moved = true break
                    end
                end
                if not moved then TaskLeaveVehicle(veh, 16) end
                feed('You do not have keys to this vehicle.')
            end

            -- motor fortat oprit pana la tasta 2
            if id then
                if ENG[id] ~= true and GetIsVehicleEngineRunning(veh) then
                    SetVehicleEngineOn(veh, false, true, true)
                end
                if isDriver then
                    DisableControlAction(0, Config.EngineControl, true)
                    if IsDisabledControlJustPressed(0, Config.EngineControl) then
                        if MYKEYS[id] then
                            TriggerServerEvent('ph_vehicles:sv:engine', id)
                        else
                            feed('You do not have keys to this vehicle.')
                        end
                    end
                end

                -- vehicul distrus
                if not DSENT[id] and (IsEntityDead(veh) or GetVehicleEngineHealth(veh) <= -3999.0) then
                    DSENT[id] = true
                    TriggerServerEvent('ph_vehicles:sv:destroyed', id)
                end
            end

            -- odometru (doar sofer)
            if id and isDriver then
                local c = GetEntityCoords(veh)
                if lastOdoCoords then
                    local d = #(c - lastOdoCoords)
                    if d > 0.05 and d < 60.0 then ODO[id] = (ODO[id] or 0) + d end
                end
                lastOdoCoords = c
                wasDriverId = id
            else
                lastOdoCoords = nil
            end

            -- centura
            if Config.Seatbelt.enabled and not belt
               and lastKmh >= Config.Seatbelt.ejectMinKmh
               and (lastKmh - kmh) >= Config.Seatbelt.ejectDropKmh then
                ejectThroughWindscreen(veh)
            end
            lastKmh = kmh

            local nowMs = GetGameTimer()
            if nowMs - lastHudPush > 150 then
                lastHudPush = nowMs
                pushHud(veh, id)
                hudActive = true
            end
        else
            if wasDriverId then
                local vv = findVehById(wasDriverId)
                if vv and DoesEntityExist(vv) then
                    local c = GetEntityCoords(vv)
                    TriggerServerEvent('ph_vehicles:sv:report', {
                        id = wasDriverId, occupied = false, flush = true,
                        fuel = FUEL[wasDriverId], odo = ODO[wasDriverId],
                        lastPos = { x = c.x, y = c.y, z = c.z, h = GetEntityHeading(vv) },
                    })
                end
                wasDriverId = nil
            end
            lastKmh = 0.0
            lastOdoCoords = nil
            belt = false
            if hudActive then clearHud() hudActive = false end
        end

        Wait(w)
    end
end)

-- ----------------------------------------------------------
--  Combustibil (la 10s)
-- ----------------------------------------------------------
CreateThread(function()
    while true do
        Wait(10000)
        if Config.Fuel.enabled then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
                local id = vehIdOf(veh)
                if id and ENG[id] == true then
                    local rpm = GetVehicleCurrentRpm(veh)
                    local use = Config.Fuel.idlePer10 + Config.Fuel.drivePer10 * math.max(0.0, rpm)
                    FUEL[id] = math.max(0.0, (FUEL[id] or 100) - use)
                    SetVehicleFuelLevel(veh, FUEL[id] + 0.0)
                    if FUEL[id] <= Config.Fuel.reserve then
                        ENG[id] = false
                        SetVehicleEngineOn(veh, false, true, true)
                        feed('~r~Out of fuel.')
                    end
                    TriggerServerEvent('ph_vehicles:sv:report', {
                        id = id, occupied = true, fuel = FUEL[id], odo = ODO[id],
                    })
                end
            end
        end
    end
end)

-- ----------------------------------------------------------
--  Heartbeat de ocupare (la Config.HeartbeatSec)
-- ----------------------------------------------------------
CreateThread(function()
    while true do
        Wait(Config.HeartbeatSec * 1000)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 then
            local id = vehIdOf(veh)
            if id then
                local isDriver = GetPedInVehicleSeat(veh, -1) == ped
                TriggerServerEvent('ph_vehicles:sv:report', {
                    id = id, occupied = true,
                    fuel = isDriver and FUEL[id] or nil,
                    odo  = isDriver and ODO[id] or nil,
                })
            end
        end
    end
end)

-- ----------------------------------------------------------
--  Vehicule proprii distruse in afara masinii
-- ----------------------------------------------------------
CreateThread(function()
    while true do
        Wait(4000)
        for id, veh in pairs(MYSPAWN) do
            if not DoesEntityExist(veh) then
                MYSPAWN[id] = nil
            elseif not DSENT[id] and (IsEntityDead(veh) or GetVehicleEngineHealth(veh) <= -3999.0) then
                DSENT[id] = true
                TriggerServerEvent('ph_vehicles:sv:destroyed', id)
                MYSPAWN[id] = nil
            end
        end
    end
end)

-- ----------------------------------------------------------
--  Sugestii de comenzi
-- ----------------------------------------------------------
AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    TriggerEvent('chat:addSuggestion', '/v', 'Open your personal vehicle garage')
    TriggerEvent('chat:addSuggestion', '/vcreate', 'Grant a personal vehicle to a player (staff >= manager)', {
        { name = 'sqlId' }, { name = 'model' }, { name = 'label', help = 'optional' } })
    TriggerEvent('chat:addSuggestion', '/park', 'Set the park spot for the personal vehicle you are sitting in (engine off)')
    TriggerEvent('chat:addSuggestion', '/givekey', 'Give keys to your vehicle to a nearby player', { { name = 'sqlId' } })
    TriggerEvent('chat:addSuggestion', '/throwkey', 'Give up any borrowed vehicle keys you hold')
end)

AddEventHandler('onClientResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearHud()
    for _, veh in pairs(MYSPAWN) do
        if DoesEntityExist(veh) then DeleteEntity(veh) end
    end
end)

-- La (re)pornirea resursei serverul nu mai are evidenta vehiculelor personale
-- din sesiunea anterioara -> curata orice vehicul cu tag `phveh` ramas orfan.
AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(1500)
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            if vehIdOf(veh) and IsVehicleSeatFree(veh, -1) and GetPedInVehicleSeat(veh, -1) == 0 then
                SetEntityAsMissionEntity(veh, true, true)
                DeleteEntity(veh)
            end
        end
    end)
end)
