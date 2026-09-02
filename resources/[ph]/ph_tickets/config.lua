-- ==========================================================
--  ph_tickets / config  (shared)
--  Sistemul de tickete al jucatorilor:  /ticket  ->  meniu NUI
--    Sidebar: Create Ticket | My Tickets
--    Create : alegi tipul + descriere (max Config.MaxLen)
--    My Tickets : ticketul activ + chat live cu staff-ul care l-a acceptat
-- ==========================================================
Config = {}

-- Antetul minimalist din stanga-sus al meniului (logo + numele serverului)
Config.ServerName = 'Purple Havoc'
Config.Logo       = 'https://i.imgur.com/eAfdBdO.png'   -- URL (gol = ascuns)

-- Lungimea maxima a descrierii si a fiecarui mesaj din chat
Config.MaxLen = 250

-- Tipurile de ticket afisate in "Create Ticket".
--   id     = valoarea salvata in `tickets.category`
--   label  = textul afisat
--   desc   = subtitlul din card
--   icon   = clasa FontAwesome
Config.Types = {
    { id = 'question',  label = 'Question',       desc = 'A quick question for the staff team.',            icon = 'fa-circle-question' },
    { id = 'general',   label = 'General Problem', desc = 'A bug, being stuck, a rule issue, a refund…',     icon = 'fa-triangle-exclamation' },
    { id = 'highstaff', label = 'High Staff',      desc = 'Sensitive matter meant for senior staff only.',   icon = 'fa-user-shield' },
}

-- Gradul minim de staff care e anuntat in chat cand se creeaza un ticket normal.
Config.NotifyGrade = 'trialhelper'
-- Gradul minim anuntat pentru ticketele de tip "High Staff".
Config.HighStaffNotifyGrade = 'headadmin'

-- Cat de des reimprospateaza clientul firul de chat cat timp e deschis (secunde).
Config.PollSeconds = 3
