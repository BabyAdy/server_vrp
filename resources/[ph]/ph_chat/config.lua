Config = {}

-- Taste (se pot rebinda din Settings > Key Bindings in FiveM)
Config.OpenKey = 'T'       -- deschide chat-ul pentru un mesaj normal
Config.CmdKey  = '/'       -- deschide chat-ul cu "/" pus, pentru comenzi

Config.VisibleLines     = 10      -- linii vizibile implicit (chat inchis); jucatorul si le regleaza 5..20 din Optiuni
Config.LinesMin         = 5
Config.LinesMax         = 20

-- Resize (scala interfetei de chat, %) - reglabil din Optiuni, persistat in users.chat_scale
Config.ScaleDefault     = 100
Config.ScaleMin         = 70
Config.ScaleMax         = 140
Config.ScaleStep        = 10
Config.ScrollbackLines  = 50      -- linii suplimentare pastrate deasupra, vizibile prin scroll cand chatul e deschis
Config.FadeDelay        = 18000   -- ms fara activitate pana se estompeaza (cand e inchis)
Config.ShowTimestamps   = true    -- prefix [HH:MM] pe fiecare linie (ora din joc)
Config.MessageMaxLength = 256
Config.ShowIdInChat     = true   -- true => prefix "[sqlid] Nume" la mesajele jucatorilor

-- ==========================================================
--  Premium Chat  (/pc [mesaj])
--  Acces: staff >= Config.PremiumChat.MinStaffGrade  SAU  abonament activ (>= 1s).
--  Format afisat:  (/pc) [Tag] Username: mesaj
--    [Tag]  = gradul de staff (cu culoarea lui) daca esti staff,
--             altfel eticheta abonamentului (Gold #FCD600 / Platinum #8F00FC).
--    corpul mesajului foloseste TextColor (diferit de Gold si Platinum).
-- ==========================================================
Config.PremiumChat = {
    Prefix         = '(/pc)',
    TextColor      = '#bf60ff',      -- culoarea corpului mesajului /pc
    MinStaffGrade  = 'trialhelper',  -- gradul minim de staff care are acces / vede canalul
}

-- Culori atribuite numelor (rotatie stabila per jucator)
Config.NameColors = {
    '#e74c3c', '#3498db', '#2ecc71', '#f1c40f', '#9b59b6',
    '#1abc9c', '#e67e22', '#e84393', '#00b894', '#a29bfe',
}
