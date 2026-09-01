-- ==========================================================
--  ph_appearance / appearance_cmd  -  comenzile / ale resursei
--
--    /editcharacter  [sqlId]   (staff >= Config.EditCharacterGrade, implicit manager)
--      Deschide editorul de aspect pe ped-ul TAU, pornind de la aspectul tintei.
--      In editor: switch M/F, toate sliderele (fara haine), plus:
--        - Save            -> aspectul LIVE al tintei (users.appearance + gender)
--        - Save Character  -> preset in character_templates (user_id, gender)
--
--    /resetcharacter [sqlId]   (staff >= Config.EditCharacterGrade, implicit manager)
--      Baga jucatorul (online) fortat in creatorul de caracter, ii dezechipeaza
--      hainele in inventar (ce nu incape -> Post Office) si ii sterge aspectul.
--
--  Comenzile sunt inregistrate pe SERVER (verifica gradul, rezolva tinta).
--  Fisierul e incarcat pe ambele parti (client -> doar chat suggestions).
-- ==========================================================

if IsDuplicityVersion() then
    -- ================= SERVER =================
    RegisterCommand('editcharacter', function(src, args)
        if src == 0 then print('[ph_appearance] /editcharacter is used in-game.') return end
        PHA_OpenEditor(src, args[1])       -- global din server.lua (valideaza gradul + tinta)
    end, false)

    RegisterCommand('resetcharacter', function(src, args)
        if src == 0 then print('[ph_appearance] /resetcharacter is used in-game.') return end
        PHA_ResetCharacter(src, args[1])   -- global din server.lua
    end, false)
else
    -- ================= CLIENT =================
    AddEventHandler('onClientResourceStart', function(res)
        if res ~= GetCurrentResourceName() then return end
        TriggerEvent('chat:addSuggestion', '/editcharacter',
            'Staff: edit a player character appearance (switch M/F, Save / Save Character)',
            { { name = 'sqlId' } })
        TriggerEvent('chat:addSuggestion', '/resetcharacter',
            'Staff: force a player into the character creator (worn clothes -> inventory / Post Office)',
            { { name = 'sqlId' } })
    end)
end
