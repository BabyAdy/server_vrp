-- ==========================================================
--  staff_menu / client
-- ==========================================================
local menuOpen = false
local spectating = false
local specTarget = nil

-- ----------------------------------------------------------
--  Deschidere (declansat de ph-core dupa /staffmenu)
-- ----------------------------------------------------------
RegisterNetEvent('ph-core:staff:openMenu', function()
    TriggerServerEvent('staff_menu:sv:open')
end)

RegisterNetEvent('staff_menu:cl:open', function(data)
    menuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })
end)

RegisterNetEvent('staff_menu:cl:data', function(payload)
    SendNUIMessage({ action = 'data', data = payload })
end)

RegisterNetEvent('staff_menu:cl:result', function(payload)
    SendNUIMessage({ action = 'result', data = payload })
end)

-- ----------------------------------------------------------
--  NUI -> client -> server
-- ----------------------------------------------------------
RegisterNUICallback('close', function(_, cb)
    menuOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('players', function(_, cb)
    TriggerServerEvent('staff_menu:sv:players')
    cb('ok')
end)

RegisterNUICallback('ticket', function(data, cb)
    TriggerServerEvent('staff_menu:sv:ticket', data)
    cb('ok')
end)

RegisterNUICallback('action', function(data, cb)
    TriggerServerEvent('staff_menu:sv:action', data)
    cb('ok')
end)

RegisterNUICallback('dev', function(data, cb)
    TriggerServerEvent('staff_menu:sv:dev', data)
    cb('ok')
end)

RegisterNUICallback('mycoords', function(_, cb)
    local c = GetEntityCoords(PlayerPedId())
    local h = GetEntityHeading(PlayerPedId())
    cb({ x = math.floor(c.x * 100) / 100, y = math.floor(c.y * 100) / 100, z = math.floor(c.z * 100) / 100, h = math.floor(h * 100) / 100 })
end)

-- ----------------------------------------------------------
--  Actiuni executate pe client
-- ----------------------------------------------------------
local function teleportTo(x, y, z)
    local ped = PlayerPedId()
    DoScreenFadeOut(300)
    Wait(350)
    SetEntityCoordsNoOffset(ped, x + 0.0, y + 0.0, z + 0.0, false, false, false)
    local t = 0
    RequestCollisionAtCoord(x, y, z)
    while not HasCollisionLoadedAroundEntity(ped) and t < 200 do Wait(10); t = t + 1 end
    Wait(150)
    DoScreenFadeIn(350)
end

RegisterNetEvent('staff_menu:cl:teleport', function(pos)
    if not pos then return end
    CreateThread(function() teleportTo(pos.x, pos.y, pos.z) end)
end)

RegisterNetEvent('staff_menu:cl:freeze', function(state)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, state == true)
    if state then
        SendNUIMessage({ action = 'toast', text = 'You were frozen by staff.' })
    end
end)

RegisterNetEvent('staff_menu:cl:heal', function()
    local ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetPedArmour(ped, 100)
    ClearPedBloodDamage(ped)
end)

RegisterNetEvent('staff_menu:cl:revive', function()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(ped), true, false)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetPedArmour(ped, 0)
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)
end)

-- ----------------------------------------------------------
--  Spectate (toggle)
-- ----------------------------------------------------------
RegisterNetEvent('staff_menu:cl:spectate', function(targetServerId)
    if spectating then
        NetworkSetInSpectatorMode(false, PlayerPedId())
        FreezeEntityPosition(PlayerPedId(), false)
        SetEntityVisible(PlayerPedId(), true, false)
        SetEntityInvincible(PlayerPedId(), false)
        spectating = false
        specTarget = nil
        SendNUIMessage({ action = 'toast', text = 'Spectate stopped.' })
        return
    end

    local tp = GetPlayerFromServerId(targetServerId)
    if tp == -1 then
        SendNUIMessage({ action = 'toast', text = 'Target is out of range.' })
        return
    end
    local tPed = GetPlayerPed(tp)
    local c = GetEntityCoords(tPed)

    SetEntityCoordsNoOffset(PlayerPedId(), c.x, c.y, c.z + 2.0, false, false, false)
    Wait(200)
    SetEntityVisible(PlayerPedId(), false, false)
    FreezeEntityPosition(PlayerPedId(), true)
    SetEntityInvincible(PlayerPedId(), true)
    NetworkSetInSpectatorMode(true, tPed)
    spectating = true
    specTarget = targetServerId
    SendNUIMessage({ action = 'toast', text = 'Spectating the player. Run again to stop.' })
end)

-- inchide meniul cu ESC / BACKSPACE cat timp e deschis
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

-- ==========================================================
--  NOCLIP  (F2, staff >= Config.Noclip.MinGrade)
-- ==========================================================
local noclipAllowed = false
local noclip = false
local speedIdx = 2                 -- pointer in Config.Noclip.Speeds (Normal by default)
local SPD = (Config.Noclip and Config.Noclip.Speeds) or {}
local pushNoclipHud               -- forward-declarat

RegisterNetEvent('staff_menu:cl:noclip', function(allowed)
    noclipAllowed = allowed == true
    if not noclipAllowed and noclip then noclip = false end
end)

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    TriggerServerEvent('staff_menu:sv:reqNoclip')
    TriggerServerEvent('staff_menu:sv:reqNoclipList')
    TriggerEvent('chat:addSuggestion', '/heal', 'Set 100% HP (no id = yourself)', { { name = 'sqlId', help = 'optional' } })
    TriggerEvent('chat:addSuggestion', '/revive', 'Revive with 100% HP (no id = yourself)', { { name = 'sqlId', help = 'optional' } })
    TriggerEvent('chat:addSuggestion', '/dv', 'Delete the nearest vehicle')
    TriggerEvent('chat:addSuggestion', '/spawncar', 'Spawn a vehicle (unlocked + engine on)', { { name = 'model' } })
    TriggerEvent('chat:addSuggestion', '/fix', 'Repair and start the vehicle')
    TriggerEvent('chat:addSuggestion', '/flip', 'Put the vehicle back on its wheels')
    TriggerEvent('chat:addSuggestion', '/maxperf', 'Max out the vehicle performance mods')
    TriggerEvent('chat:addSuggestion', '/dvall', 'Delete all unused vehicles (10s warning)')
    TriggerEvent('chat:addSuggestion', '/setvw', 'Move a player to a virtual world', {
        { name = 'sqlId' }, { name = 'virtualWorld', help = '0 = normal' } })
    TriggerEvent('chat:addSuggestion', '/doorinfo', 'Aim at a door to get its model + coords')
    TriggerEvent('chat:addSuggestion', '/givemoney', 'Give (or -take) cash to a player', {
        { name = 'sqlId' }, { name = 'amount', help = 'negativ = scade' } })
    TriggerEvent('chat:addSuggestion', '/givebmoney', 'Give (or -take) bank money to a player', {
        { name = 'sqlId' }, { name = 'amount', help = 'negativ = scade' } })
    TriggerEvent('chat:addSuggestion', '/givepp', 'Give (or -take) premium points to a player', {
        { name = 'sqlId' }, { name = 'amount', help = 'negativ = scade' } })
end)
AddEventHandler('ph-core:client:playerLoaded', function()
    TriggerServerEvent('staff_menu:sv:reqNoclip')
    TriggerServerEvent('staff_menu:sv:reqNoclipList')
end)

--- viteza curenta (toate sunt disponibile - noclip e doar pentru staff)
local function currentSpeed()
    if speedIdx < 1 or speedIdx > #SPD then speedIdx = 1 end
    return SPD[speedIdx]
end

local function cycleSpeed()
    speedIdx = (speedIdx % #SPD) + 1
    pushNoclipHud()
end

function pushNoclipHud()  -- luainspect: atribuit forward-declaratiei locale
    local cur = currentSpeed()
    local tiers = {}
    for i, s in ipairs(SPD) do
        tiers[#tiers + 1] = { name = s.name, active = (i == speedIdx) }
    end
    SendNUIMessage({ action = 'noclip', data = {
        on = noclip,
        speedName = cur and cur.name or '?',
        speedLabel = cur and cur.label or '',
        tiers = tiers,
    }})
end

local NC_SELF_ALPHA = (Config.Noclip and Config.Noclip.SelfAlpha) or 150

local function setNoclip(state)
    if state and not noclipAllowed then return end
    noclip = state == true

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    local ent = (veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped) and veh or ped

    SetEntityInvincible(ent, noclip)
    SetEntityInvincible(ped, noclip)
    FreezeEntityPosition(ent, noclip)
    SetEntityCollision(ent, not noclip, not noclip)

    if noclip then
        -- pentru tine: te vezi transparent ; pentru ceilalti: invizibil (vezi broadcast-ul de mai jos)
        SetEntityAlpha(ped, NC_SELF_ALPHA, false)
        if ent ~= ped then SetEntityAlpha(ent, NC_SELF_ALPHA, false) end
    else
        SetEntityVelocity(ent, 0.0, 0.0, 0.0)
        FreezeEntityPosition(ent, false)
        SetEntityCollision(ent, true, true)
        SetEntityInvincible(ent, false)
        SetEntityInvincible(ped, false)
        ResetEntityAlpha(ped)
        if ent ~= ped then ResetEntityAlpha(ent) end
    end

    TriggerServerEvent('staff_menu:sv:noclip', noclip)
    pushNoclipHud()
end

-- F2 (rebindabil din Settings > Key Bindings)
RegisterCommand('+phNoclip', function()
    if noclipAllowed then setNoclip(not noclip) end
end, false)
RegisterCommand('-phNoclip', function() end, false)
RegisterKeyMapping('+phNoclip', 'Staff: Toggle Noclip', 'keyboard', (Config.Noclip and Config.Noclip.Key) or 'F2')

-- bucla de miscare
local NC_KILL = {
    24, 25, 68, 69, 70, 91, 92,           -- attack / aim / vehicle attack
    30, 31, 32, 33, 34, 35, 36,           -- move WASD + duck
    21, 22, 44, 38,                       -- sprint / jump / cover / E
    23, 75,                               -- enter/exit vehicle
    263, 264, 257, 140, 141, 142,         -- melee
}

CreateThread(function()
    while true do
        if noclip then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            local ent = (veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped) and veh or ped

            for _, c in ipairs(NC_KILL) do DisableControlAction(0, c, true) end
            DisablePlayerFiring(PlayerId(), true)

            if IsDisabledControlJustPressed(0, 21) then cycleSpeed() end   -- L Shift = viteza

            local cur = currentSpeed()
            local step = ((cur and cur.mps) or 5.0) * GetFrameTime()

            local rot = GetGameplayCamRot(2)
            local pitch, yaw = math.rad(rot.x), math.rad(rot.z)
            local cp = math.cos(pitch)
            local fx, fy, fz = -math.sin(yaw) * cp, math.cos(yaw) * cp, math.sin(pitch)
            local rx, ry = math.cos(yaw), math.sin(yaw)

            local dx, dy, dz = 0.0, 0.0, 0.0
            if IsDisabledControlPressed(0, 32) then dx = dx + fx; dy = dy + fy; dz = dz + fz end   -- W fata
            if IsDisabledControlPressed(0, 33) then dx = dx - fx; dy = dy - fy; dz = dz - fz end   -- S spate
            if IsDisabledControlPressed(0, 34) then dx = dx - rx; dy = dy - ry end                 -- A stanga
            if IsDisabledControlPressed(0, 35) then dx = dx + rx; dy = dy + ry end                 -- D dreapta
            if IsDisabledControlPressed(0, 44) then dz = dz + 1.0 end                              -- Q sus
            if IsDisabledControlPressed(0, 38) then dz = dz - 1.0 end                              -- E jos

            local mag = math.sqrt(dx * dx + dy * dy + dz * dz)
            if mag > 0.001 then
                dx, dy, dz = dx / mag, dy / mag, dz / mag
                local p = GetEntityCoords(ent)
                SetEntityCoordsNoOffset(ent, p.x + dx * step, p.y + dy * step, p.z + dz * step, true, true, true)
            end
            SetEntityHeading(ent, rot.z)
            if ent ~= ped then SetEntityRotation(ent, 0.0, 0.0, rot.z, 2, true) end
            SetEntityVelocity(ent, 0.0, 0.0, 0.0)

            Wait(0)
        else
            Wait(300)
        end
    end
end)

-- daca ti se ia gradul cat esti in noclip
CreateThread(function()
    while true do
        Wait(2000)
        if noclip and not noclipAllowed then setNoclip(false) end
    end
end)

-- ----------------------------------------------------------
--  Ceilalti jucatori NU vad pe cel din noclip (nici ped, nici nametag).
--  ph_nametag verifica IsEntityVisible(ped) -> nametag-ul dispare automat.
-- ----------------------------------------------------------
local hiddenNoclip = {}   -- [serverId] = true

RegisterNetEvent('staff_menu:cl:noclipState', function(serverId, on)
    if serverId == GetPlayerServerId(PlayerId()) then return end   -- pe tine te gestioneaza setNoclip()
    if on then
        hiddenNoclip[serverId] = true
    else
        hiddenNoclip[serverId] = nil
        local ply = GetPlayerFromServerId(serverId)
        if ply ~= -1 then
            local pd = GetPlayerPed(ply)
            if pd ~= 0 and DoesEntityExist(pd) then
                SetEntityVisible(pd, true, false)
                ResetEntityAlpha(pd)
                SetEntityNoCollisionEntity(PlayerPedId(), pd, true)
                local v = GetVehiclePedIsIn(pd, false)
                if v ~= 0 then SetEntityVisible(v, true, false); ResetEntityAlpha(v) end
            end
        end
    end
end)

CreateThread(function()
    while true do
        if next(hiddenNoclip) ~= nil then
            local myPed = PlayerPedId()
            for sid in pairs(hiddenNoclip) do
                local ply = GetPlayerFromServerId(sid)
                if ply ~= -1 then
                    local pd = GetPlayerPed(ply)
                    if pd ~= 0 and DoesEntityExist(pd) then
                        SetEntityLocallyInvisible(pd)
                        SetEntityVisible(pd, false, false)
                        SetEntityNoCollisionEntity(myPed, pd, false)
                        local v = GetVehiclePedIsIn(pd, false)
                        if v ~= 0 then
                            SetEntityLocallyInvisible(v)
                            SetEntityVisible(v, false, false)
                            SetEntityNoCollisionEntity(myPed, v, false)
                        end
                    end
                end
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ==========================================================
--  COMENZI DE VEHICUL  (executate pe clientul apelantului)
-- ==========================================================
local spawnedCars = {}   -- toate vehiculele din /spawncar (raman in lume; nu se sterg intre ele)

local function nc_toast(text) SendNUIMessage({ action = 'toast', text = text }) end

--- scoate un vehicul din lista de urmarire /spawncar
local function forgetSpawned(veh)
    for i = #spawnedCars, 1, -1 do
        if spawnedCars[i] == veh or not DoesEntityExist(spawnedCars[i]) then
            table.remove(spawnedCars, i)
        end
    end
end

--- sterge un vehicul, cerand mai intai controlul retelei (onesync)
local function deleteVeh(veh)
    if veh == 0 or not DoesEntityExist(veh) then return end
    if not NetworkHasControlOfEntity(veh) then
        NetworkRequestControlOfEntity(veh)
        local t = 0
        while not NetworkHasControlOfEntity(veh) and t < 25 do Wait(10); t = t + 1 end
    end
    SetEntityAsMissionEntity(veh, true, true)
    DeleteVehicle(veh)
    if DoesEntityExist(veh) then DeleteEntity(veh) end
end

--- vehiculul pe care actionam: cel in care esti, altfel cel mai apropiat in raza
local function targetVehicle(radius)
    local ped = PlayerPedId()
    local v = GetVehiclePedIsIn(ped, false)
    if v ~= 0 then return v end
    local pc = GetEntityCoords(ped)
    local best, bestD = 0, radius or 6.0
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local d = #(GetEntityCoords(veh) - pc)
        if d < bestD then best, bestD = veh, d end
    end
    return best
end

local function fixVehicle(veh)
    if veh == 0 then return end
    SetVehicleFixed(veh)
    SetVehicleDeformationFixed(veh)
    SetVehicleUndriveable(veh, false)
    SetVehicleEngineHealth(veh, 1000.0)
    SetVehiclePetrolTankHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleEngineOn(veh, true, true, false)
    SetVehicleFuelLevel(veh, 100.0)
end

local function flipVehicle(veh)
    if veh == 0 then return end
    local h = GetEntityHeading(veh)
    SetVehicleOnGroundProperly(veh)
    SetEntityRotation(veh, 0.0, 0.0, h, 2, true)
end

local function maxPerf(veh)
    if veh == 0 then return false end
    SetVehicleModKit(veh, 0)
    -- doar performanta: engine / brakes / transmission / suspension
    for _, slot in ipairs({ 11, 12, 13, 15 }) do
        local n = GetNumVehicleMods(veh, slot)
        if n and n > 0 then SetVehicleMod(veh, slot, n - 1, false) end
    end
    -- turbo
    ToggleVehicleMod(veh, 18, true)
    SetVehicleMod(veh, 18, 0, false)
    -- consumabile de performanta
    SetVehicleFixed(veh)
    SetVehicleEngineOn(veh, true, true, false)
    return true
end

RegisterNetEvent('staff_menu:cl:vehcmd', function(op, arg)
    local ped = PlayerPedId()

    if op == 'dv' then
        local veh = targetVehicle(8.0)
        if veh == 0 then return nc_toast('No vehicle nearby.') end
        forgetSpawned(veh)
        deleteVeh(veh)
        nc_toast('Vehicle deleted.')

    elseif op == 'fix' then
        local veh = targetVehicle(6.0)
        if veh == 0 then return nc_toast('No vehicle nearby.') end
        fixVehicle(veh)
        nc_toast('Vehicle repaired and started.')

    elseif op == 'flip' then
        local veh = targetVehicle(6.0)
        if veh == 0 then return nc_toast('No vehicle nearby.') end
        flipVehicle(veh)
        nc_toast('Vehicle put back on its wheels.')

    elseif op == 'maxperf' then
        local veh = GetVehiclePedIsIn(ped, false)
        if veh == 0 then return nc_toast('You must be in a vehicle.') end
        maxPerf(veh)
        nc_toast('Performance set to maximum.')

    elseif op == 'spawncar' then
        local model = tostring(arg or ''):lower()
        local hash = GetHashKey(model)
        if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
            return nc_toast(('Invalid model: %s'):format(model))
        end
        -- vehiculul precedent din /spawncar NU se mai sterge; ramane in lume
        RequestModel(hash)
        local t = 0
        while not HasModelLoaded(hash) and t < 200 do Wait(10); t = t + 1 end
        if not HasModelLoaded(hash) then return nc_toast('Could not load the model.') end

        local c = GetEntityCoords(ped)
        local fwd = GetEntityForwardVector(ped)
        local veh = CreateVehicle(hash, c.x + fwd.x * 3.0, c.y + fwd.y * 3.0, c.z + 0.5, GetEntityHeading(ped), true, false)
        SetModelAsNoLongerNeeded(hash)
        SetVehicleHasBeenOwnedByPlayer(veh, true)
        SetEntityAsMissionEntity(veh, true, true)
        SetVehicleOnGroundProperly(veh)
        SetVehicleDoorsLocked(veh, 1)         -- descuiat
        SetVehicleNeedsToBeHotwired(veh, false)
        SetVehicleEngineOn(veh, true, true, false)
        SetVehicleDirtLevel(veh, 0.0)
        SetPedIntoVehicle(ped, veh, -1)
        spawnedCars[#spawnedCars + 1] = veh
        nc_toast(('Spawned: %s'):format(model))
    end
end)

-- /dvall: sterge vehiculele fara nimeni in ele (in acest client), fara sa blocheze
RegisterNetEvent('staff_menu:cl:dvall', function()
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(veh) then
            local empty = IsVehicleSeatFree(veh, -1)
            if empty then
                for seat = 0, GetVehicleMaxNumberOfPassengers(veh) - 1 do
                    if not IsVehicleSeatFree(veh, seat) then empty = false break end
                end
            end
            if empty then
                forgetSpawned(veh)
                NetworkRequestControlOfEntity(veh)
                SetEntityAsMissionEntity(veh, true, true)
                DeleteVehicle(veh)
                if DoesEntityExist(veh) then DeleteEntity(veh) end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, veh in ipairs(spawnedCars) do
        if DoesEntityExist(veh) then DeleteVehicle(veh) end
    end
end)

-- ==========================================================
--  USI BLOCATE PERMANENT  (Config.Doors) - fara UI.
--  Totul e pe CLIENT -> se aplica in ORICE virtual world (routing bucket),
--  sistemul de usi e local.  Usile NU se pot deschide deloc:
--    - door system: LOCKED + open ratio 0 (re-fortat des)
--    - cat esti aproape: fiecare frame slam la 0 + FreezeEntityPosition pe canat
-- ==========================================================
local function doorHashOf(i) return GetHashKey(('ph_door_%d'):format(i)) end
local function doorModelOf(d)
    return (type(d.model) == 'string') and GetHashKey(d.model) or math.floor(d.model or 0)
end

--- (re)inregistreaza + incuie ferm toate usile din config
local function applyLockedDoors()
    for i, d in ipairs(Config.Doors or {}) do
        local model = doorModelOf(d)
        if model ~= 0 then
            local h = doorHashOf(i)
            if not IsDoorRegisteredWithSystem(h) then
                AddDoorToSystem(h, model, d.x + 0.0, d.y + 0.0, d.z + 0.0, false, false, false)
            end
            DoorSystemSetDoorState(h, 1, true, true)          -- 1 = LOCKED
            DoorSystemSetOpenRatio(h, 0.0, true, true)
            DoorSystemSetHoldOpen(h, false)
            DoorSystemSetAutomaticRate(h, 0.0, false, false)
            DoorSystemSetAutomaticDistance(h, 0.0, false, false)
        end
    end
end

-- re-inregistrare periodica (dupa stream-uri mari / schimbari de bucket)
CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(200) end
    Wait(1500)
    applyLockedDoors()
    while true do
        Wait(Config.DoorRefreshMs or 3000)
        applyLockedDoors()
    end
end)

-- enforcement dur cat esti aproape de o usa din lista: nu are cum sa se deschida
CreateThread(function()
    while true do
        local near = false
        if next(Config.Doors or {}) ~= nil then
            local pc = GetEntityCoords(PlayerPedId())
            for i, d in ipairs(Config.Doors) do
                local dist = #(pc - vector3(d.x + 0.0, d.y + 0.0, d.z + 0.0))
                if dist < 30.0 then
                    near = true
                    local h = doorHashOf(i)
                    DoorSystemSetOpenRatio(h, 0.0, false, false)
                    DoorSystemSetDoorState(h, 1, false, false)
                    if dist < 4.0 then
                        local obj = GetClosestObjectOfType(d.x + 0.0, d.y + 0.0, d.z + 0.0, 2.5, doorModelOf(d), false, false, false)
                        if obj ~= 0 and DoesEntityExist(obj) then
                            FreezeEntityPosition(obj, true)
                        end
                    end
                end
            end
        end
        Wait(near and 0 or 800)
    end
end)

-- re-aplica imediat dupa spawn si dupa o schimbare de virtual world (ex: /setvw)
AddEventHandler('ph-core:client:playerLoaded', function()
    SetTimeout(1500, applyLockedDoors)
end)
RegisterNetEvent('staff_menu:cl:refreshDoors', function()
    SetTimeout(300, applyLockedDoors)
    SetTimeout(1500, applyLockedDoors)
end)

-- ----------------------------------------------------------
--  /doorinfo: mod de OCHIRE - te uiti la usa, [E] confirma, [Backspace] anuleaza
-- ----------------------------------------------------------
local doorPicking = false

local function rotToDir(rot)
    local rz, rx = math.rad(rot.z), math.rad(rot.x)
    local n = math.abs(math.cos(rx))
    return vector3(-math.sin(rz) * n, math.cos(rz) * n, math.sin(rx))
end

--- obiectul la care se uita jucatorul (raycast din camera), fallback pe cel mai apropiat
local function aimedObject()
    local cam = GetGameplayCamCoord()
    local dst = cam + rotToDir(GetGameplayCamRot(2)) * 12.0
    local ray = StartShapeTestLosProbe(cam.x, cam.y, cam.z, dst.x, dst.y, dst.z, 1 + 16, PlayerPedId(), 4)
    local _, hit, _, _, ent = GetShapeTestResult(ray)
    if (hit == 1 or hit == true) and ent and ent ~= 0 and DoesEntityExist(ent) and GetEntityType(ent) == 3 then
        return ent
    end
    -- fallback: cel mai apropiat obiect de crosshair
    local pc = GetEntityCoords(PlayerPedId())
    local best, bestD
    for _, obj in ipairs(GetGamePool('CObject')) do
        local d = #(GetEntityCoords(obj) - pc)
        if d < 4.0 and (not bestD or d < bestD) then best, bestD = obj, d end
    end
    return best
end

local function reportDoor(ent)
    local oc = GetEntityCoords(ent)
    local m = GetEntityModel(ent)
    local line = ('DOOR  model = %s   x = %.2f, y = %.2f, z = %.2f'):format(m, oc.x + 0.0, oc.y + 0.0, oc.z + 0.0)
    local cfg = ('{ name = \'\', model = %s, x = %.2f, y = %.2f, z = %.2f },'):format(m, oc.x + 0.0, oc.y + 0.0, oc.z + 0.0)
    print('[doorinfo] ' .. line)
    print('[doorinfo] ' .. cfg)
    SendNUIMessage({ action = 'toast', text = line .. '  (copied to F8 console)' })
end

RegisterNetEvent('staff_menu:cl:doorinfo', function()
    if doorPicking then doorPicking = false; return end
    doorPicking = true
    CreateThread(function()
        local started = GetGameTimer()
        while doorPicking do
            local ent = aimedObject()

            -- hint pe ecran
            SetTextFont(4); SetTextScale(0.42, 0.42); SetTextColour(255, 255, 255, 220)
            SetTextOutline(); SetTextCentre(true)
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(
                ent and ('Look at the door   ~b~[E]~w~ confirm   ~b~[Backspace]~w~ cancel')
                    or  ('Not aiming at any door   ~b~[Backspace]~w~ cancel'))
            EndTextCommandDisplayText(0.5, 0.86)

            if ent then
                local c = GetEntityCoords(ent)
                DrawMarker(28, c.x, c.y, c.z, 0, 0, 0, 0, 0, 0, 0.35, 0.35, 0.35, 120, 200, 255, 150, false, false, 2, nil, nil, false)
                if IsControlJustReleased(0, 38) then           -- E
                    reportDoor(ent)
                    doorPicking = false
                end
            end

            if IsControlJustReleased(0, 177) or IsControlJustReleased(0, 322)  -- Backspace / Esc
               or GetGameTimer() - started > 25000 then
                doorPicking = false
                SendNUIMessage({ action = 'toast', text = 'doorinfo: cancelled.' })
            end
            Wait(0)
        end
    end)
end)
