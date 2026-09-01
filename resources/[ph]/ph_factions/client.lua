-- ==========================================================
--  ph_factions / client
-- ==========================================================
local self = {              -- starea proprie, trimisa de server (ph_factions:cl:self)
    faction = 0, rank = 0, rankName = nil, tester = false, supervisor = false,
    warns = 0, onDuty = false, data = nil,
    marker = { type = 1, r = 155, g = 120, b = 255, a = 140, sz = 1.4, h = 1.0 },
    interact = 2.0, drawDist = 18.0,
}
local publicFactions = {}   -- lista publica de HQ-uri (blip)
local blips = {}            -- [factionId] = blipHandle
local inside = false        -- sunt in interiorul HQ-ului
local menuOpen = false
local garageOpen = false

local GARAGE_KEYS = { car = 'vgarage', heli = 'hgarage', boat = 'bgarage' }

local function isLoaded()
    local ok, r = pcall(function() return exports['ph-core']:IsLoaded() end)
    return ok and r
end

-- ----------------------------------------------------------
--  Helpers de desenare
-- ----------------------------------------------------------
local function draw3DText(x, y, z, text)
    local onScreen, sx, sy = World3dToScreen2d(x, y, z)
    if not onScreen then return end
    SetTextScale(0.34, 0.34)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 215)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentSubstringPlayerName(text)
    DrawText(sx, sy)
end

local function marker(m, x, y, z)
    DrawMarker(m.type or 1, x, y, z - (m.h or 1.0), 0, 0, 0, 0, 0, 0,
        m.sz or 1.4, m.sz or 1.4, m.h or 1.0, m.r or 155, m.g or 120, m.b or 255, m.a or 140,
        false, true, 2, false, nil, nil, false)
end

-- ----------------------------------------------------------
--  Blips publice pentru HQ-uri
-- ----------------------------------------------------------
local function rebuildBlips()
    for id, b in pairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end blips[id] = nil end
    for _, f in ipairs(publicFactions) do
        if f.hqEnter then
            local b = AddBlipForCoord(f.hqEnter.x + 0.0, f.hqEnter.y + 0.0, f.hqEnter.z + 0.0)
            SetBlipSprite(b, (f.blip and f.blip.sprite) or 60)
            SetBlipColour(b, (f.blip and f.blip.color) or 3)
            SetBlipScale(b, (f.blip and f.blip.scale) or 0.9)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(f.name .. ' HQ')
            EndTextCommandSetBlipName(b)
            blips[f.id] = b
        end
    end
end

RegisterNetEvent('ph_factions:cl:factions', function(list)
    publicFactions = list or {}
    rebuildBlips()
end)

RegisterNetEvent('ph_factions:cl:self', function(data)
    self = data or self
    inside = false
end)

-- ----------------------------------------------------------
--  Comenzi client
-- ----------------------------------------------------------
RegisterCommand('factionmenu', function()
    TriggerServerEvent('ph_factions:sv:openMenu')
end, false)

-- suggestions (english)
AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    TriggerEvent('chat:addSuggestion', '/duty', 'Toggle faction duty on/off')
    TriggerEvent('chat:addSuggestion', '/factionmenu', 'Open the faction menu (rank 6+ / tester / supervisor)')
    TriggerEvent('chat:addSuggestion', '/setleader', 'Set a player as faction leader (rank 7 + factions.leader)', {
        { name = 'sqlId' }, { name = 'factionId' } })
    TriggerEvent('chat:addSuggestion', '/setfmember', 'Set a player faction and rank', {
        { name = 'sqlId' }, { name = 'factionId' }, { name = 'rank 1-7' } })
    TriggerEvent('chat:addSuggestion', '/makeleader', 'Set a player rank 7 without changing factions.leader', {
        { name = 'sqlId' }, { name = 'factionId' } })
    TriggerEvent('chat:addSuggestion', '/changerankname', 'Rename a faction rank', {
        { name = 'factionId' }, { name = 'rank 1-7' }, { name = 'new name' } })
    TriggerEvent('chat:addSuggestion', '/auninvite', 'Remove a player from their faction', {
        { name = 'sqlId' }, { name = 'reason', help = 'optional' } })
    TriggerEvent('chat:addSuggestion', '/removeleader', 'Remove a player from faction and from factions.leader', {
        { name = 'sqlId' }, { name = 'reason', help = 'optional' } })
end)

-- ----------------------------------------------------------
--  HQ enter / exit (teleport + fade)
-- ----------------------------------------------------------
local function teleportTo(pt)
    local ped = PlayerPedId()
    DoScreenFadeOut(250)
    local t = 0
    while not IsScreenFadedOut() and t < 40 do Wait(10); t = t + 1 end
    SetEntityCoordsNoOffset(ped, pt.x + 0.0, pt.y + 0.0, pt.z + 0.0, false, false, false)
    if pt.h then SetEntityHeading(ped, pt.h + 0.0) end
    RequestCollisionAtCoord(pt.x + 0.0, pt.y + 0.0, pt.z + 0.0)
    local t2 = 0
    while not HasCollisionLoadedAroundEntity(ped) and t2 < 100 do Wait(10); t2 = t2 + 1 end
    Wait(150)
    DoScreenFadeIn(350)
end

RegisterNetEvent('ph_factions:cl:enteredHQ', function(exitCoords)
    inside = true
    if exitCoords then teleportTo(exitCoords) end
end)

RegisterNetEvent('ph_factions:cl:leftHQ', function(enterCoords)
    inside = false
    if enterCoords then teleportTo(enterCoords) end
end)

RegisterNetEvent('ph_factions:cl:leaveHQ', function(enterCoords)
    -- scos din factiune cat era in interior
    if inside and enterCoords then
        inside = false
        teleportTo(enterCoords)
    end
end)

-- ----------------------------------------------------------
--  Loop de interactiune: marker + text + [E]
-- ----------------------------------------------------------
CreateThread(function()
    while true do
        local wait = 500
        if isLoaded() and self.faction ~= 0 and self.data then
            local ped = PlayerPedId()
            local pc = GetEntityCoords(ped)
            local f = self.data
            local dd = self.drawDist or 18.0
            local ir = self.interact or 2.0
            local acted = false

            -- intrare HQ (doar cand NU esti in interior)
            if not inside and f.hqEnter then
                local d = #(pc - vector3(f.hqEnter.x, f.hqEnter.y, f.hqEnter.z))
                if d < dd then
                    wait = 0
                    marker(self.marker, f.hqEnter.x, f.hqEnter.y, f.hqEnter.z)
                    if d < ir then
                        draw3DText(f.hqEnter.x, f.hqEnter.y, f.hqEnter.z + 0.9, ('%s HQ~n~~b~[E]~w~ Intra'):format(f.name))
                        if IsControlJustReleased(0, 38) and not acted then
                            acted = true
                            TriggerServerEvent('ph_factions:sv:enterHQ', f.id)
                        end
                    end
                end
            end

            -- iesire HQ (doar cand esti in interior)
            if inside and f.hqExit then
                local d = #(pc - vector3(f.hqExit.x, f.hqExit.y, f.hqExit.z))
                if d < dd then
                    wait = 0
                    marker(self.marker, f.hqExit.x, f.hqExit.y, f.hqExit.z)
                    if d < ir then
                        draw3DText(f.hqExit.x, f.hqExit.y, f.hqExit.z + 0.9, '~b~[E]~w~ Iesi din HQ')
                        if IsControlJustReleased(0, 38) and not acted then
                            acted = true
                            TriggerServerEvent('ph_factions:sv:exitHQ')
                        end
                    end
                end
            end

            -- garaje (v / h / b)
            if not inside then
                for cat, key in pairs(GARAGE_KEYS) do
                    local g = f[key]
                    if g then
                        local d = #(pc - vector3(g.x, g.y, g.z))
                        if d < dd then
                            wait = 0
                            marker(self.marker, g.x, g.y, g.z)
                            if d < ir then
                                draw3DText(g.x, g.y, g.z + 0.9, ('%s~n~~b~[E]~w~ Deschide'):format(g.label or cat))
                                if IsControlJustReleased(0, 38) and not acted then
                                    acted = true
                                    TriggerServerEvent('ph_factions:sv:openGarage', cat)
                                end
                            end
                        end
                    end
                end
            end
        end
        Wait(wait)
    end
end)

-- ----------------------------------------------------------
--  Garaj: spawn vehicul
-- ----------------------------------------------------------
local lastGarage = { category = 'car', coords = nil }

RegisterNetEvent('ph_factions:cl:garage', function(category, list, garageCoords)
    lastGarage.category = category
    lastGarage.coords = garageCoords
    garageOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'garage', data = { category = category, list = list or {} } })
end)

local function applyProps(veh, props)
    if type(props) ~= 'table' then return end
    if props.primary then SetVehicleColours(veh, props.primary, props.secondary or props.primary) end
    if props.plateText then SetVehicleNumberPlateText(veh, tostring(props.plateText):sub(1, 8)) end
    if type(props.mods) == 'table' then
        SetVehicleModKit(veh, 0)
        for slot, val in pairs(props.mods) do SetVehicleMod(veh, tonumber(slot), val, false) end
    end
end

RegisterNetEvent('ph_factions:cl:spawnVehicle', function(model, spawn, factionId, props)
    local hash = type(model) == 'string' and GetHashKey(model) or model
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        return
    end
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) and t < 200 do Wait(10); t = t + 1 end
    if not HasModelLoaded(hash) then return end

    local veh = CreateVehicle(hash, spawn.x + 0.0, spawn.y + 0.0, spawn.z + 0.0, (spawn.h or 0.0) + 0.0, true, false)
    SetModelAsNoLongerNeeded(hash)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetEntityAsMissionEntity(veh, true, true)           -- ph_world nu il sterge
    SetVehicleNumberPlateText(veh, ('PH%03d'):format(factionId % 1000))
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleEngineOn(veh, true, true, false)
    applyProps(veh, props)

    -- marcaj de factiune (replicat) - folosit de lacatul de sofer
    local ent = Entity(veh)
    ent.state:set('faction', factionId, true)

    local ped = PlayerPedId()
    SetPedIntoVehicle(ped, veh, -1)
end)

-- ----------------------------------------------------------
--  Lacat de sofer: doar membrii factiunii pot conduce vehiculul de factiune;
--  ceilalti pot sta doar pasageri.
-- ----------------------------------------------------------
CreateThread(function()
    while true do
        local wait = 800
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
            local ok, vf = pcall(function() return Entity(veh).state.faction end)
            vf = ok and vf or nil
            if vf and vf ~= 0 and vf ~= self.faction then
                wait = 0
                -- muta-l pe primul loc de pasager liber, altfel afara
                local moved = false
                for seat = 0, GetVehicleMaxNumberOfPassengers(veh) - 1 do
                    if IsVehicleSeatFree(veh, seat) then
                        SetPedIntoVehicle(ped, veh, seat)
                        moved = true
                        break
                    end
                end
                if not moved then
                    TaskLeaveVehicle(veh, 16)
                end
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('You cannot drive a faction vehicle that is not yours.')
                EndTextCommandDisplayHelp(0, false, true, -1)
            end
        end
        Wait(wait)
    end
end)

-- ----------------------------------------------------------
--  NUI: meniu factiune
-- ----------------------------------------------------------
RegisterNetEvent('ph_factions:cl:openMenu', function(data)
    menuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })
end)

RegisterNetEvent('ph_factions:cl:menuData', function(data)
    SendNUIMessage({ action = 'data', data = data })
end)

RegisterNUICallback('close', function(_, cb)
    menuOpen = false
    garageOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('menu', function(d, cb)
    TriggerServerEvent('ph_factions:sv:menu', d or {})
    cb('ok')
end)

RegisterNUICallback('garagePick', function(d, cb)
    garageOpen = false
    SetNuiFocus(false, false)
    if d and d.id then
        TriggerServerEvent('ph_factions:sv:spawnVehicle', d.id, lastGarage.category)
    end
    cb('ok')
end)

RegisterNUICallback('nearestPlayer', function(_, cb)
    -- pentru butonul "Recruteaza cel mai apropiat"
    local ped = PlayerPedId()
    local pc = GetEntityCoords(ped)
    local best, bestD = nil, 5.0
    for _, p in ipairs(GetActivePlayers()) do
        if p ~= PlayerId() then
            local d = #(GetEntityCoords(GetPlayerPed(p)) - pc)
            if d < bestD then best = GetPlayerServerId(p); bestD = d end
        end
    end
    cb({ serverId = best })
end)

-- inchide meniul cu ESC / Backspace
CreateThread(function()
    while true do
        if menuOpen or garageOpen then
            if IsControlJustReleased(0, 322) or IsControlJustReleased(0, 177) then
                menuOpen = false; garageOpen = false
                SetNuiFocus(false, false)
                SendNUIMessage({ action = 'forceClose' })
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)
