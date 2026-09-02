-- ==========================================================
--  ph_tickets / client  -  NUI-ul meniului /ticket
--  Comanda /ticket e in ticket_cmd.lua (conventia de layout).
-- ==========================================================
local menuOpen = false

local function closeMenu()
    if not menuOpen then return end
    menuOpen = false
    SetNuiFocus(false, false)
    TriggerServerEvent('ph_tickets:sv:closeMenu')
end

RegisterNetEvent('ph_tickets:cl:open', function(data)
    menuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })
end)

RegisterNetEvent('ph_tickets:cl:data', function(data)
    SendNUIMessage({ action = 'data', data = data })
end)

RegisterNUICallback('close', function(_, cb)
    closeMenu()
    cb('ok')
end)

RegisterNUICallback('action', function(d, cb)
    TriggerServerEvent('ph_tickets:sv:action', d or {})
    cb('ok')
end)

-- ESC / Backspace inchid meniul
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

AddEventHandler('onClientResourceStop', function(res)
    if res == GetCurrentResourceName() and menuOpen then SetNuiFocus(false, false) end
end)
