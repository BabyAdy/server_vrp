PH = PH or {}
PH.Loaded = false        -- true dupa ce personajul a intrat complet in joc
PH.UIReady = false       -- true dupa ce NUI a semnalat ca s-a incarcat
PH.Character = nil

local authCam = nil

-- ----------------------------------------------------------
--  Camera de autentificare
-- ----------------------------------------------------------
local function startAuthCam()
    local c = Config.AuthCamera
    authCam = CreateCamWithParams(
        'DEFAULT_SCRIPTED_CAMERA',
        c.coords.x, c.coords.y, c.coords.z,
        0.0, 0.0, 0.0,
        50.0, false, 0
    )
    PointCamAtCoord(authCam, c.pointAt.x, c.pointAt.y, c.pointAt.z)
    SetCamActive(authCam, true)
    RenderScriptCams(true, false, 0, true, false)
end

local function stopAuthCam()
    RenderScriptCams(false, false, 0, true, false)
    if authCam then
        DestroyCam(authCam, false)
        authCam = nil
    end
end
PH.StopAuthCam = stopAuthCam

-- ----------------------------------------------------------
--  Boot: freeze player, camera, deschide NUI
-- ----------------------------------------------------------
CreateThread(function()
    if GetResourceState('spawnmanager') == 'started' then
        exports.spawnmanager:setAutoSpawn(false)
    end

    DoScreenFadeOut(0)

    while not NetworkIsSessionStarted() do
        Wait(200)
    end

    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetPlayerInvincible(PlayerId(), true)
    SetPlayerControl(PlayerId(), false, 0)

    local c = Config.AuthCamera
    SetEntityCoordsNoOffset(ped, c.coords.x, c.coords.y, c.coords.z + 20.0, false, false, false)

    startAuthCam()
    SetNuiFocus(true, true)

    -- asteapta ca interfata sa fie gata (max ~5s)
    local tries = 0
    while not PH.UIReady and tries < 100 do
        Wait(50)
        tries = tries + 1
    end

    SendNUIMessage({ action = 'show', screen = 'loading' })
    Wait(250)
    DoScreenFadeIn(600)

    TriggerServerEvent('ph-core:auth:requestState')
end)

-- ----------------------------------------------------------
--  Cat timp nu suntem in joc: ascunde HUD + blocheaza input
-- ----------------------------------------------------------
CreateThread(function()
    while not PH.Loaded do
        HideHudAndRadarThisFrame()
        DisableAllControlActions(0)
        Wait(0)
    end
end)

-- ----------------------------------------------------------
--  API client pentru alte resurse (ph_hud, ph_chat, ...)
-- ----------------------------------------------------------
exports('GetCharacter', function()
    return PH.Character
end)

exports('IsLoaded', function()
    return PH.Loaded == true
end)

exports('GetStaffGrade', function(key)
    return Config.StaffGrades[key or '']
end)

exports('GetStaffGrades', function()
    return Config.StaffGrades
end)

--- Actualizeaza o valoare local si anunta celelalte resurse.
--- Server: TriggerClientEvent('ph-core:client:setData', src, 'money', 1234)
RegisterNetEvent('ph-core:client:setData', function(key, value)
    if type(PH.Character) ~= 'table' or type(key) ~= 'string' then return end
    PH.Character[key] = value
    TriggerEvent('ph-core:client:dataChanged', key, value, PH.Character)
end)
