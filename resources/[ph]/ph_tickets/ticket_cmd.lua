-- ==========================================================
--  ph_tickets / ticket_cmd
--
--  CLIENT:
--    /ticket        - deschide meniul de tickete (Create Ticket | My Tickets)
--
--  Fisier incarcat doar pe client (vezi fxmanifest) ; branch-uit oricum cu
--  IsDuplicityVersion() ca sa respecte conventia de layout a proiectului.
-- ==========================================================
if IsDuplicityVersion() then return end

RegisterCommand('ticket', function()
    TriggerServerEvent('ph_tickets:sv:open')
end, false)

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    TriggerEvent('chat:addSuggestion', '/ticket', 'Open the ticket menu (create a ticket / your active ticket)')
end)
