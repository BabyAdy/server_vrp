-- ==========================================================
--  ph_hud / commands  -  TOATE comenzile / ale resursei (client)
--
--    /hudtest   - adauga cateva status-uri de test in HUD
--
--  Foloseste exportul client `ph_hud:addStatus` definit in client.lua.
-- ==========================================================
RegisterCommand('hudtest', function()
    exports['ph_hud']:addStatus('rent', 'RENTED VEHICLE', { durationSec = 3300 })
    exports['ph_hud']:addStatus('hood', 'WEARING HOOD')
    exports['ph_hud']:addStatus('oil', 'OIL EXTRACTION', { durationSec = 6600 })
end, false)
