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
        SendNUIMessage({ action = 'toast', text = 'Ai fost inghetat de staff.' })
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
        SendNUIMessage({ action = 'toast', text = 'Spectate oprit.' })
        return
    end

    local tp = GetPlayerFromServerId(targetServerId)
    if tp == -1 then
        SendNUIMessage({ action = 'toast', text = 'Tinta nu e in raza.' })
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
    SendNUIMessage({ action = 'toast', text = 'Spectezi jucatorul. Ruleaza din nou pentru stop.' })
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
