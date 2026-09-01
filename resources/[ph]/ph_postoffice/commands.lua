-- ==========================================================
--  ph_postoffice / commands  -  TOATE comenzile / ale resursei
--
--    /po                     - revendica pachetele din Post Office
--    /postoffice [list]      - revendica, sau "list" ca sa le vezi
--
--  Helperele traiesc in server.lua si sunt expuse prin `POENV`.
-- ==========================================================
local E = POENV

local function doPostoffice(src, args)
    if src == 0 then print('[ph_postoffice] use this command in-game.') return end
    local uid = exports[E.PH]:GetUserId(src)
    if not uid then return end

    if args[1] == 'list' then
        local rows = MySQL.query.await(
            'SELECT name, count, reason, created_at FROM post_office_items WHERE user_id = ? AND claimed_at IS NULL ORDER BY id ASC LIMIT 50',
            { uid }) or {}
        if #rows == 0 then return E.toast(src, 'Post Office is empty.', 'info') end
        E.notify(src, ('Post Office (%d package(s)):'):format(#rows), '#b98cff')
        for _, r in ipairs(rows) do
            E.notify(src, (' - %dx %s%s'):format(r.count, E.itemLabel(r.name), r.reason and (' — ' .. r.reason) or ''), '#cfc9e6')
        end
    else
        E.claim(uid, src)
    end
end

RegisterCommand('postoffice', function(src, args) doPostoffice(src, args) end, false)
RegisterCommand('po', function(src, args) doPostoffice(src, args) end, false)
