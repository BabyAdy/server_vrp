Config = {}

-- Taste (se pot rebinda din Settings > Key Bindings in FiveM)
Config.OpenKey = 'T'       -- deschide chat-ul pentru un mesaj normal
Config.CmdKey  = '/'       -- deschide chat-ul cu "/" pus, pentru comenzi

Config.MaxMessages      = 30      -- cate linii pastreaza in buffer (vizibile prin scroll cand e deschis)
Config.VisibleLines     = 17      -- cate linii se vad cand chat-ul e inchis
Config.FadeDelay        = 18000   -- ms fara activitate pana se estompeaza (cand e inchis)
Config.ShowTimestamps   = true    -- prefix [HH:MM] pe fiecare linie (ora din joc)
Config.MessageMaxLength = 256
Config.ShowIdInChat     = false   -- true => prefix "[sqlid] Nume" la mesajele jucatorilor

-- Culori atribuite numelor (rotatie stabila per jucator)
Config.NameColors = {
    '#e74c3c', '#3498db', '#2ecc71', '#f1c40f', '#9b59b6',
    '#1abc9c', '#e67e22', '#e84393', '#00b894', '#a29bfe',
}
