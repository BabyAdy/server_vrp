-- ==========================================================
--  ph_world / server - stare autoritara de timp & vreme
--    /time    [HH:MM | HH]        (staff >= Config.StaffPerm)
--    /weather [type]              (staff >= Config.StaffPerm)
--  Starea e tinuta aici si trimisa la toti clientii + la cei care intra tarziu.
-- ==========================================================
local PH_CORE = 'ph-core'

local clock = {
    h = math.floor(Config.Time.StartHour or 12) % 24,
    m = math.floor(Config.Time.StartMinute or 0) % 60,
    running = Config.Time.KeepRunning ~= false,
}

local weather = tostring(Config.Weather.Start or 'EXTRASUNNY'):upper()

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
local function notify(src, text, kind)
    if src == 0 then print('[ph_world] ' .. tostring(text)); return end
    exports[PH_CORE]:Notify(src, text, kind or 'info')
end

local function requirePerm(src)
    if src == 0 then return true end
    return exports[PH_CORE]:RequireStaff(src, Config.StaffPerm) == true
end

local function staffName(src)
    if src == 0 then return 'console' end
    local c = exports[PH_CORE]:GetCharacter(src)
    return (c and c.username) or ('src ' .. src)
end

local function isWeatherValid(w)
    for _, t in ipairs(Config.Weather.Types) do
        if t == w then return true end
    end
    return false
end

-- ----------------------------------------------------------
--  Broadcast
-- ----------------------------------------------------------
local function pushTime(target)
    TriggerClientEvent('ph_world:cl:syncTime', target or -1, clock.h, clock.m, clock.running)
end

local function pushWeather(target, transitionSec)
    TriggerClientEvent('ph_world:cl:syncWeather', target or -1, weather,
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
        if clock.running then
            clock.m = clock.m + 1
            if clock.m >= 60 then
                clock.m = 0
                clock.h = (clock.h + 1) % 24
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
        pushTime(-1)
    end
end)

-- ----------------------------------------------------------
--  Sincronizare la intrarea in joc
-- ----------------------------------------------------------
AddEventHandler('ph-core:playerLoaded', function(src)
    if not src then return end
    pushTime(src)
    pushWeather(src, 0)   -- fara tranzitie pentru cel care abia a intrat
end)

RegisterNetEvent('ph_world:sv:reqSync', function()
    local src = source
    pushTime(src)
    pushWeather(src, 0)
end)

-- ----------------------------------------------------------
--  /time [HH:MM | HH]
-- ----------------------------------------------------------
RegisterCommand('time', function(src, args)
    if not requirePerm(src) then return end

    local raw = tostring(args[1] or '')
    local hh, mm = raw:match('^(%d%d?):(%d%d?)$')
    if not hh then
        hh = raw:match('^(%d%d?)$')
        mm = '0'
    end
    hh, mm = tonumber(hh), tonumber(mm)
    if not hh or not mm or hh < 0 or hh > 23 or mm < 0 or mm > 59 then
        return exports[PH_CORE]:CmdSyntax(src, '/time [HH:MM]  (e.g. /time 21:30 or /time 8)')
    end

    clock.h, clock.m = hh, mm
    pushTime(-1)

    local label = ('%02d:%02d'):format(hh, mm)
    notify(src, ('Time set to %s.'):format(label), 'success')
    exports[PH_CORE]:StaffMsg('time', ('%s set the time to %s.'):format(staffName(src), label))
    print(('^5[ph_world]^7 %s set time -> %s'):format(staffName(src), label))
end, false)

-- ----------------------------------------------------------
--  /weather [type]
-- ----------------------------------------------------------
RegisterCommand('weather', function(src, args)
    if not requirePerm(src) then return end

    local w = tostring(args[1] or ''):upper()
    if w == '' or not isWeatherValid(w) then
        return exports[PH_CORE]:CmdSyntax(src,
            '/weather [type: ' .. table.concat(Config.Weather.Types, '/') .. ']')
    end

    weather = w
    pushWeather(-1)

    notify(src, ('Weather set to %s.'):format(w), 'success')
    exports[PH_CORE]:StaffMsg('weather', ('%s set the weather to %s.'):format(staffName(src), w))
    print(('^5[ph_world]^7 %s set weather -> %s'):format(staffName(src), w))
end, false)
