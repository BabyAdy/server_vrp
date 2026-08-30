Config = {}

Config.ServerName = 'PURPLE HAVOC'

Config.RefreshMs        = 200      -- rata de update pentru bare / ceas
Config.OnlineRefreshMs  = 5000     -- rata cu care serverul trimite nr. de jucatori

Config.HideNativeCash   = true     -- ascunde afisajul de bani nativ GTA (il inlocuim noi)

-- Salariu (doar countdown vizual deocamdata; la 0 trimite ph_hud:paycheckDue pe server)
Config.Paycheck = {
    intervalSec = 15 * 60,
}

-- Nevoi (foame / sete). Deocamdata pur cosmetic - fara efecte, fara salvare.
Config.Needs = {
    enable = true,
    start  = 100.0,
    decayPerMin = { hunger = 0.6, thirst = 0.9 },
}

-- Nume zile / luni (ca in screenshot: "thursday", "feb")
Config.Days = {
    [0] = 'sunday', [1] = 'monday', [2] = 'tuesday', [3] = 'wednesday',
    [4] = 'thursday', [5] = 'friday', [6] = 'saturday',
}
Config.Months = {
    [0] = 'jan', [1] = 'feb', [2] = 'mar', [3] = 'apr', [4] = 'may', [5] = 'jun',
    [6] = 'jul', [7] = 'aug', [8] = 'sep', [9] = 'oct', [10] = 'nov', [11] = 'dec',
}
