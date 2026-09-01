-- ==========================================================
--  ph_world / commands  (toate comenzile / ale resursei)
--
--    /time    [HH:MM | HH]   (staff >= Config.StaffPerm)  - zi/noapte dupa ora
--    /weather [type]         (staff >= Config.StaffPerm)  - vremea GTA
--
--  Starea (PHW_clock / PHW_weather) si helperele de broadcast (PHW_*) sunt in
--  server.lua - aici e doar inregistrarea comenzilor.
-- ==========================================================

-- ----------------------------------------------------------
--  /time [HH:MM | HH]
-- ----------------------------------------------------------
RegisterCommand('time', function(src, args)
    if not PHW_requirePerm(src) then return end

    local raw = tostring(args[1] or '')
    local hh, mm = raw:match('^(%d%d?):(%d%d?)$')
    if not hh then
        hh = raw:match('^(%d%d?)$')
        mm = '0'
    end
    hh, mm = tonumber(hh), tonumber(mm)
    if not hh or not mm or hh < 0 or hh > 23 or mm < 0 or mm > 59 then
        return exports[PHW_PH_CORE]:CmdSyntax(src, '/time [HH:MM]  (e.g. /time 21:30 or /time 8)')
    end

    PHW_clock.h, PHW_clock.m = hh, mm
    PHW_pushTime(-1)

    local label = ('%02d:%02d'):format(hh, mm)
    PHW_notify(src, ('Time set to %s.'):format(label), 'success')
    exports[PHW_PH_CORE]:StaffMsg('time', ('%s set the time to %s.'):format(PHW_staffName(src), label))
    print(('^5[ph_world]^7 %s set time -> %s'):format(PHW_staffName(src), label))
end, false)

-- ----------------------------------------------------------
--  /weather [type]
-- ----------------------------------------------------------
RegisterCommand('weather', function(src, args)
    if not PHW_requirePerm(src) then return end

    local w = tostring(args[1] or ''):upper()
    if w == '' or not PHW_isWeatherValid(w) then
        return exports[PHW_PH_CORE]:CmdSyntax(src,
            '/weather [type: ' .. table.concat(Config.Weather.Types, '/') .. ']')
    end

    PHW_weather = w
    PHW_pushWeather(-1)

    PHW_notify(src, ('Weather set to %s.'):format(w), 'success')
    exports[PHW_PH_CORE]:StaffMsg('weather', ('%s set the weather to %s.'):format(PHW_staffName(src), w))
    print(('^5[ph_world]^7 %s set weather -> %s'):format(PHW_staffName(src), w))
end, false)
