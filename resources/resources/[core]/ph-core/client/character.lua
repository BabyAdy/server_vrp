PH = PH or {}

-- ----------------------------------------------------------
--  NUI -> client
-- ----------------------------------------------------------
RegisterNUICallback('createCharacter', function(data, cb)
    TriggerServerEvent('ph-core:character:create', {
        dob    = data.dob,
        gender = tonumber(data.gender),
        height = tonumber(data.height),
    })
    cb('ok')
end)

-- ----------------------------------------------------------
--  Server -> client
-- ----------------------------------------------------------
RegisterNetEvent('ph-core:character:result', function(res)
    SendNUIMessage({ action = 'characterResult', data = res or {} })
end)

RegisterNetEvent('ph-core:character:spawn', function(char)
    PH.Character = char
    CreateThread(function()
        PH.FinalizeSpawn(char)
    end)
end)

-- ----------------------------------------------------------
--  Spawn efectiv al personajului
-- ----------------------------------------------------------
function PH.FinalizeSpawn(char)
    DoScreenFadeOut(500)
    Wait(600)

    SendNUIMessage({ action = 'hide' })
    SetNuiFocus(false, false)

    -- model
    local modelName = (char.gender == 1) and Config.PedModels.female or Config.PedModels.male
    local model = joaat(modelName)

    if not IsModelInCdimage(model) or not IsModelValid(model) then
        print(('^1[ph-core] Model invalid: %s (%s) - pastrez modelul curent.^7'):format(modelName, model))
    else
        -- cerem repetat modelul; pe un joc cu mult DLC poate dura mult sa se incarce
        local waited = 0
        RequestModel(model)
        while not HasModelLoaded(model) and waited < 20000 do
            RequestModel(model)
            Wait(50)
            waited = waited + 50
        end

        if HasModelLoaded(model) then
            -- SetPlayerModel pe un model neincarcat => CRASH nativ, de-asta verificam
            SetPlayerModel(PlayerId(), model)
            SetModelAsNoLongerNeeded(model)
            Wait(100)   -- lasa noul ped sa se creeze inainte de PlayerPedId()
        else
            print(('^1[ph-core] Modelul %s nu s-a incarcat in 20s - se pastreaza modelul implicit.^7'):format(modelName))
        end
    end

    local ped = PlayerPedId()
    SetPedDefaultComponentVariation(ped)

    -- pozitie de spawn (fixa deocamdata; ultima pozitie nu se salveaza inca)
    local pos = char.spawn or Config.NewCharacterSpawn
    local heading = pos.heading or 0.0

    NetworkResurrectLocalPlayer(pos.x + 0.0, pos.y + 0.0, pos.z + 0.0, heading + 0.0, true, false)
    SetEntityCoordsNoOffset(ped, pos.x + 0.0, pos.y + 0.0, pos.z + 0.0, false, false, false)
    SetEntityHeading(ped, heading + 0.0)

    RequestCollisionAtCoord(pos.x, pos.y, pos.z)
    local ct = 0
    while not HasCollisionLoadedAroundEntity(ped) and ct < 300 do
        Wait(10)
        ct = ct + 1
    end

    PH.StopAuthCam()

    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetPlayerControl(PlayerId(), true, 0)
    SetPlayerInvincible(PlayerId(), false)
    ClearPedTasksImmediately(ped)

    PH.Loaded = true

    Wait(400)
    DoScreenFadeIn(700)

    TriggerServerEvent('ph-core:character:spawned')
    -- hook local pentru alte resurse client-side
    TriggerEvent('ph-core:client:playerLoaded', char)
end
