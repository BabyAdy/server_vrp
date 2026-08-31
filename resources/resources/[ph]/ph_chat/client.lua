local chatOpen = false
local suggestions = {}   -- [name] = { help = string, params = table }

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
local function suggestionList()
    local list = {}
    for name, s in pairs(suggestions) do
        list[#list + 1] = { name = name, help = s.help or '', params = s.params or {} }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function openChat(prefill)
    if chatOpen then return end
    chatOpen = true
    SetNuiFocus(true, true)          -- tastatura + cursor (ca sa poti da scroll)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ type = 'open', prefill = prefill or '' })
end

-- ----------------------------------------------------------
--  NUI -> client
-- ----------------------------------------------------------
RegisterNUICallback('ready', function(_, cb)
    SendNUIMessage({ type = 'config', data = {
        visibleLines = Config.VisibleLines,
        scrollback   = Config.ScrollbackLines,
        fadeDelay    = Config.FadeDelay,
        timestamps   = Config.ShowTimestamps,
    }})
    SendNUIMessage({ type = 'suggestions', data = suggestionList() })
    TriggerServerEvent('ph_chat:requestOptions')   -- ia optiunile salvate (si dupa un restart de resursa)
    cb('ok')
end)

RegisterNUICallback('close', function(data, cb)
    chatOpen = false
    SetNuiFocus(false, false)

    local msg = data and data.message
    if type(msg) == 'string' then
        msg = msg:gsub('^%s+', ''):gsub('%s+$', '')
        if msg ~= '' then
            if msg:sub(1, 1) == '/' then
                ExecuteCommand(msg:sub(2))          -- comanda (client sau, daca lipseste, server)
            else
                TriggerServerEvent('ph_chat:submit', msg)
            end
        end
    end
    cb('ok')
end)

-- ----------------------------------------------------------
--  Taste
-- ----------------------------------------------------------
RegisterCommand('phChatOpen', function() openChat('') end, false)
RegisterCommand('phChatCmd', function() openChat('/') end, false)
RegisterKeyMapping('phChatOpen', 'Chat: scrie un mesaj', 'keyboard', Config.OpenKey)
RegisterKeyMapping('phChatCmd', 'Chat: scrie o comanda', 'keyboard', Config.CmdKey)

-- ----------------------------------------------------------
--  Primire mesaje
-- ----------------------------------------------------------
RegisterNetEvent('ph_chat:receive', function(payload)
    SendNUIMessage({ type = 'message', data = payload })
end)

-- optiuni per jucator (linii vizibile, toggle Premium Chat) - trimise de server la conectare
RegisterNetEvent('ph_chat:options', function(opt)
    SendNUIMessage({ type = 'options', data = opt })
end)

RegisterNUICallback('setOption', function(data, cb)
    TriggerServerEvent('ph_chat:setOption', data or {})
    cb('ok')
end)

-- ----------------------------------------------------------
--  Compatibilitate cu API-ul standard `chat`
-- ----------------------------------------------------------
RegisterNetEvent('chat:addMessage', function(data)
    if type(data) ~= 'table' then return end

    local prefix, text
    if type(data.args) == 'table' then
        prefix = data.args[1]
        local rest = {}
        for i = 2, #data.args do rest[#rest + 1] = tostring(data.args[i]) end
        text = table.concat(rest, ' ')
        if text == '' then text, prefix = prefix, nil end
    else
        text = tostring(data.message or data.text or '')
    end

    local col
    if type(data.color) == 'table' then
        col = ('rgb(%d,%d,%d)'):format(
            math.floor(data.color[1] or 255),
            math.floor(data.color[2] or 255),
            math.floor(data.color[3] or 255))
    end

    SendNUIMessage({ type = 'message', data = {
        prefix = prefix, prefixColor = col,
        text = text, textColor = '#e8e6f0',
    }})
end)

RegisterNetEvent('chat:addSuggestion', function(name, help, params)
    suggestions[name] = { help = help, params = params }
    SendNUIMessage({ type = 'suggestions', data = suggestionList() })
end)

RegisterNetEvent('chat:removeSuggestion', function(name)
    suggestions[name] = nil
    SendNUIMessage({ type = 'suggestions', data = suggestionList() })
end)

RegisterNetEvent('chat:clear', function()
    SendNUIMessage({ type = 'clear' })
end)

-- ----------------------------------------------------------
--  Exports pentru alte resurse (client-side)
-- ----------------------------------------------------------
exports('addMessage', function(payload)
    SendNUIMessage({ type = 'message', data = payload })
end)

exports('addSuggestion', function(name, help, params)
    suggestions[name] = { help = help, params = params }
    SendNUIMessage({ type = 'suggestions', data = suggestionList() })
end)

exports('removeSuggestion', function(name)
    suggestions[name] = nil
    SendNUIMessage({ type = 'suggestions', data = suggestionList() })
end)
