-- ==========================================================
--  ph_shop / client  -  NUI-ul magazinului (/shop)
-- ==========================================================
local RES = GetCurrentResourceName()
local open = false

local function focus(on)
    open = on
    SetNuiFocus(on, on)
end

RegisterNetEvent('ph_shop:cl:open', function(data)
    focus(true)
    SendNUIMessage({ action = 'open', data = data })
end)

RegisterNetEvent('ph_shop:cl:form', function(data)
    SendNUIMessage({ action = 'form', data = data })
end)

RegisterNetEvent('ph_shop:cl:formError', function(data)
    SendNUIMessage({ action = 'formError', data = data })
end)

RegisterNetEvent('ph_shop:cl:formDone', function(data)
    SendNUIMessage({ action = 'formDone', data = data })
end)

RegisterNUICallback('close', function(_, cb)
    focus(false)
    cb('ok')
end)

RegisterNUICallback('buy', function(d, cb)
    if d and d.key then TriggerServerEvent('ph_shop:sv:buy', d.key) end
    cb('ok')
end)

RegisterNUICallback('phoneSet', function(d, cb)
    TriggerServerEvent('ph_shop:sv:phoneSet', d and d.value or '')
    cb('ok')
end)

RegisterNUICallback('clanRequest', function(d, cb)
    TriggerServerEvent('ph_shop:sv:clanRequest', { name = d and d.name or '', tag = d and d.tag or '' })
    cb('ok')
end)

-- inchidere cu ESC / Backspace
CreateThread(function()
    while true do
        if open then
            if IsControlJustReleased(0, 322) or IsControlJustReleased(0, 177) then
                focus(false)
                SendNUIMessage({ action = 'forceClose' })
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

AddEventHandler('onClientResourceStart', function(res)
    if res ~= RES then return end
    TriggerEvent('chat:addSuggestion', '/shop', 'Open the Premium Points shop')
end)
