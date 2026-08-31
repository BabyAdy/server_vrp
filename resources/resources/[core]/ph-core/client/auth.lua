PH = PH or {}

-- ----------------------------------------------------------
--  NUI -> client
-- ----------------------------------------------------------
RegisterNUICallback('uiReady', function(_, cb)
    PH.UIReady = true
    cb('ok')
end)

RegisterNUICallback('login', function(data, cb)
    TriggerServerEvent('ph-core:auth:login', {
        username = data.username,
        password = data.password,
    })
    cb('ok')
end)

RegisterNUICallback('register', function(data, cb)
    TriggerServerEvent('ph-core:auth:register', {
        username = data.username,
        email    = data.email,
        password = data.password,
    })
    cb('ok')
end)

-- ----------------------------------------------------------
--  Server -> client
-- ----------------------------------------------------------
RegisterNetEvent('ph-core:auth:setScreen', function(screen)
    SendNUIMessage({ action = 'show', screen = screen })
end)

RegisterNetEvent('ph-core:auth:result', function(res)
    res = res or {}
    SendNUIMessage({ action = 'authResult', data = res })

    if res.ok and res.next == 'character_create' then
        SendNUIMessage({ action = 'show', screen = 'charcreate' })
    end
    -- res.next == 'spawn' este tratat de character.lua (ph-core:character:spawn)
end)
