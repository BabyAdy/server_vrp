-- ==========================================================
--  ph_clothing / commands  (toate comenzile / ale resursei)
--
--    /tryon component <id> <drawable> [texture]
--    /tryon prop      <id> <drawable> [texture]
--    /tryon reset
--    /tryon info                (dump in F8: cate drawable-uri are fiecare slot)
--
--  /tryon - comanda de test pentru hainele custom (staff >= Config.TryOnPerm).
--  Verificarea de grad se face aici; aplicarea efectiva pe ped e pe client.
-- ==========================================================
local PH_CORE = 'ph-core'

RegisterCommand('tryon', function(src, args)
    if src == 0 then
        print('[ph_clothing] /tryon merge doar in joc.')
        return
    end
    if exports[PH_CORE]:RequireStaff(src, Config.TryOnPerm) ~= true then return end

    local sub = tostring(args[1] or ''):lower()

    if sub == 'reset' then
        TriggerClientEvent('ph_clothing:cl:tryon', src, { op = 'reset' })
        exports[PH_CORE]:Notify(src, 'Appearance reset to model default.', 'info')
        return
    end

    if sub == 'info' then
        TriggerClientEvent('ph_clothing:cl:tryon', src, { op = 'info' })
        return
    end

    if sub ~= 'component' and sub ~= 'prop' then
        exports[PH_CORE]:CmdSyntax(src, '/tryon [component|prop] [id] [drawable] [texture]  |  /tryon reset  |  /tryon info')
        return
    end

    local id      = tonumber(args[2])
    local drawable = tonumber(args[3])
    local texture  = tonumber(args[4]) or 0
    if not id or not drawable then
        exports[PH_CORE]:CmdSyntax(src, ('/tryon %s [id] [drawable] [texture]'):format(sub))
        return
    end

    TriggerClientEvent('ph_clothing:cl:tryon', src, {
        op = sub, id = math.floor(id),
        drawable = math.floor(drawable), texture = math.floor(texture),
    })
end, false)
