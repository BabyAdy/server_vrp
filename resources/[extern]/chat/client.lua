local chatOpen = false

local function nui(action, data)
    data = data or {}
    data.action = action
    SendNUIMessage(data)
end

local function setFocus(state)
    chatOpen = state
    SetNuiFocus(state, state)
    SetNuiFocusKeepInput(false)
end

local function openChat()
    if chatOpen then return end
    setFocus(true)
    nui('open')
end

local function closeChat()
    if not chatOpen then return end
    setFocus(false)
    nui('close')
end

RegisterCommand('+openchat', function()
    if IsPauseMenuActive() then return end
    openChat()
end, false)

RegisterCommand('-openchat', function() end, false)

RegisterKeyMapping('+openchat', 'Deschide chat', 'keyboard', 'T')

RegisterNUICallback('close', function(_, cb)
    closeChat()
    cb('ok')
end)

RegisterNUICallback('send', function(data, cb)
    local msg = data and data.message
    if type(msg) == 'string' then
        msg = msg:gsub('^%s+', ''):gsub('%s+$', '')
        if #msg > 0 and #msg <= 256 then
            TriggerServerEvent('chat:sendMessage', msg)
        end
    end
    closeChat()
    cb('ok')
end)

RegisterNetEvent('chat:addMessage', function(payload)
    if type(payload) ~= 'table' then return end
    nui('message', {
        time = payload.time,
        rank = payload.rank,
        name = payload.name,
        id = payload.id,
        text = payload.text,
    })
end)

RegisterNetEvent('chat:clear', function()
    nui('clear')
end)

-- Blochează controalele în timp ce chatul e deschis
CreateThread(function()
    while true do
        if chatOpen then
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 106, true)
            DisableControlAction(0, 200, true)
            Wait(0)
        else
            Wait(200)
        end
    end
end)

-- Ascunde chatul default FiveM
CreateThread(function()
    SetTextChatEnabled(false)
    SetNuiFocus(false, false)
end)

exports('addMessage', function(payload)
    TriggerEvent('chat:addMessage', payload)
end)

exports('open', openChat)
exports('close', closeChat)
