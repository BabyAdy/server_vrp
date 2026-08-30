Config = {}

Config.MaxDistance = 25.0     -- metri: peste asta nu se mai deseneaza
Config.ShowSelf    = true     -- jucatorul isi vede propriul nametag
Config.HeadOffset  = 0.38     -- inaltime peste osul capului

-- estompare cu distanta (alpha)
Config.FadeStart   = 14.0     -- pana aici alpha maxim
Config.MinAlpha    = 60

-- ascunde nametag-ul cand jucatorul tinta e:
Config.HideWhenDead     = true
Config.HideInVehicleFPV = false   -- true = ascunde propriul tag cand esti in masina la persoana 1

-- culori linii
Config.Colors = {
    id     = { 180, 150, 255 },   -- (id) - mov deschis
    name   = { 255, 255, 255 },
    badge  = { 255, 205, 90 },    -- placeholder pana vin subscriptiile
}
