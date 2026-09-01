-- ==========================================================
--  ph_shop / commands  -  TOATE comenzile / ale resursei (server)
--
--    /shop   - deschide magazinul cu Premium Points (NUI)
--
--  Helperele traiesc in server.lua si sunt expuse prin SHOPENV.
--  NUI-ul (deschidere / formular / focus) e in client.lua.
-- ==========================================================
local E = SHOPENV

RegisterCommand('shop', function(src)
    if src == 0 then print('[ph_shop] /shop is used in-game.') return end
    E.open(src)
end, false)
