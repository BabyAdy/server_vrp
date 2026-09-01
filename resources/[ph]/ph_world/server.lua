-- ==========================================================
--  ph_world / server - stare autoritara de timp & vreme
--  Starea e tinuta aici si trimisa la toti clientii + la cei care intra tarziu.
--  Comenzile (/time, /weather) sunt in  commands.lua .
--
--  NOTA: `PHW_*` (clock, weather, helperele de broadcast) sunt GLOBALE la nivel
--  de resursa, ca sa fie vazute si din commands.lua (fisierele din aceeasi
--  resursa impart mediul global, dar NU si local-urile).
-- ==========================================================
PHW_PH_CORE = 'ph-core'

PHW_clock = {
    h = math.floor(Config.Time.StartHour or 12) % 24,
    m = math.floor(Config.Time.StartMinute or 0) % 60,
    running = Config.Time.KeepRunning ~= false,
}

PHW_weather = tostring(Config.Weather.Start or 'EXTRASUNNY'):upper()

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
function PHW_notify(src, text, kind)
    if src == 0 then print('[ph_world] ' .. tostring(text)); return end
    exports[PHW_PH_CORE]:Notify(src, text, kind or 'info')
end

function PHW_requirePerm(src)
    if src == 0 then return true end
    return exports[PHW_PH_CORE]:RequireStaff(src, Config.StaffPerm) == true
end

function PHW_staffName(src)
    if src == 0 then return 'console' end
    local c = exports[PHW_PH_CORE]:GetCharacter(src)
    return (c and c.username) or ('src ' .. src)
end

function PHW_isWeatherValid(w)
    for _, t in ipairs(Config.Weather.Types) do
        if t == w then return true end
    end
    return false
end

-- ----------------------------------------------------------
--  Broadcast
-- ----------------------------------------------------------
function PHW_pushTime(target)
    TriggerClientEvent('ph_world:cl:syncTime', target or -1, PHW_clock.h, PHW_clock.m, PHW_clock.running)
end

function PHW_pushWeather(target, transitionSec)
    TriggerClientEvent('ph_world:cl:syncWeather', target or -1, PHW_weather,
        transitionSec ~= nil and transitionSec or (Config.Weather.TransitionSec or 15))
end

-- ----------------------------------------------------------
--  Ceasul serverului curge in fundal (fara retea) ca cei care
--  intra tarziu sa primeasca ora corecta.
-- ----------------------------------------------------------
CreateThread(function()
    local stepMs = math.floor((Config.Time.RealSecondsPerGameMinute or 2.0) * 1000)
    if stepMs < 100 then stepMs = 100 end
    while true do
        Wait(stepMs)
        if PHW_clock.running then
            PHW_clock.m = PHW_clock.m + 1
            if PHW_clock.m >= 60 then
                PHW_clock.m = 0
                PHW_clock.h = (PHW_clock.h + 1) % 24
            end
        end
    end
end)

-- resync periodic anti-drift
CreateThread(function()
    local every = math.floor(Config.Time.ResyncMs or 120000)
    if every < 15000 then every = 15000 end
    while true do
        Wait(every)
        PHW_pushTime(-1)
    end
end)

-- ----------------------------------------------------------
--  Sincronizare la intrarea in joc
-- ----------------------------------------------------------
AddEventHandler('ph-core:playerLoaded', function(src)
    if not src then return end
    PHW_pushTime(src)
    PHW_pushWeather(src, 0)   -- fara tranzitie pentru cel care abia a intrat
end)

RegisterNetEvent('ph_world:sv:reqSync', function()
    local src = source
    PHW_pushTime(src)
    PHW_pushWeather(src, 0)
end)
