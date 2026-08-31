Config = {}

Config.OpenKey        = 'I'          -- tasta de deschidere (rebindabila din Settings)
Config.DefaultSlots   = 100          -- sloturi default / cont (se maresc prin /setslots -> ticket)
Config.MaxWeight      = 450.0        -- capacitate (unitatea din header: current/max)
Config.SaveIntervalMs = 5 * 60 * 1000

-- Drop-uri pe jos
Config.Drop = {
    ExpireMs        = 10 * 60 * 1000,   -- itemele stau 10 minute pe jos
    PickupDistance  = 2.0,
    NearbyDistance  = 12.0,             -- raza pentru panoul "NEARBY ITEMS"
    Prop            = 'prop_med_bag_01b',
}

-- Arme
Config.Weapon = {
    MaxLoadedAmmo      = 500,           -- gloante maxim incarcate intr-o arma
    MaxDurability      = 100.0,
    DurabilityPerShot  = 0.20,          -- scade la fiecare glont tras
    BrokenBlocksEquip  = true,          -- durabilitate 0 => nu mai poti echipa arma
    HoverTooltipMs     = 2000,          -- cat tii cursorul pe arma pana apar gloantele
}

-- Sloturi de echipament (stanga sus).  kind: 'component' | 'prop' ; id = id GTA
Config.EquipmentSlots = {
    hat      = { label = 'Sapca',        kind = 'prop',      id = 0 },
    glasses  = { label = 'Ochelari',     kind = 'prop',      id = 1 },
    earrings = { label = 'Cercei',       kind = 'prop',      id = 2 },
    watch    = { label = 'Ceas',         kind = 'prop',      id = 6 },
    bracelet = { label = 'Bratara',      kind = 'prop',      id = 7 },
    mask     = { label = 'Masca',        kind = 'component', id = 1 },
    jacket   = { label = 'Geaca',        kind = 'component', id = 11 },
    pants    = { label = 'Pantaloni',    kind = 'component', id = 4 },
    shoes    = { label = 'Incaltaminte', kind = 'component', id = 6 },
    necklace = { label = 'Lant',         kind = 'component', id = 7 },
    backpack = { label = 'Rucsac',       kind = 'component', id = 5 },
}
Config.EquipmentOrder = {
    'hat', 'jacket', 'pants', 'watch', 'mask',
    'glasses', 'bracelet', 'shoes', 'earrings', 'necklace', 'backpack',
}

-- ==========================================================
--  Sloturi numerice unificate
--  1..DefaultSlots        -> grid normal
--  101..106               -> sloturi de haine (clothing) aplicate pe ped
--  107..111               -> accesorii (rezervate; inca fara iteme in Config.Items)
--  hotbar 1..HotbarSlots  -> pointeri catre sloturi de grid (arme / consumabile)
--
--  Toate au aceeasi validare: itemul tras trebuie sa fie type='clothing'
--  si item.slot == cheia de echipament mapata mai jos.
-- ==========================================================
Config.EquipmentSlotIds = {
    hat = 101, mask = 102, jacket = 103, pants = 104, shoes = 105, backpack = 106,
    glasses = 107, earrings = 108, watch = 109, bracelet = 110, necklace = 111,
}

-- reverse lookup [idNumeric] = cheieEchipament
Config.ClothingSlots = {}
for _eqKey, _eqId in pairs(Config.EquipmentSlotIds) do
    Config.ClothingSlots[_eqId] = _eqKey
end

Config.HotbarSlots = 5

-- ==========================================================
--  ITEME  (exemple - le inlocuiesti / adaugi liber)
--  type: 'item' | 'weapon' | 'ammo' | 'clothing'
-- ==========================================================
Config.Items = {
    -- consumabile / misc
    water      = { label = 'Sticla de apa', weight = 0.5, stack = 20,  type = 'item', usable = true, effect = 'thirst', value = 25 },
    bread      = { label = 'Paine',         weight = 0.3, stack = 20,  type = 'item', usable = true, effect = 'hunger', value = 25 },
    bandage    = { label = 'Bandaj',        weight = 0.2, stack = 10,  type = 'item', usable = true, effect = 'heal',   value = 25 },
    phone      = { label = 'Telefon',       weight = 0.4, stack = 1,   type = 'item', usable = true, effect = 'phone' },
    radio      = { label = 'Statie radio',  weight = 0.6, stack = 1,   type = 'item', usable = true, effect = 'radio' },
    lockpick   = { label = 'Lockpick',      weight = 0.2, stack = 10,  type = 'item', usable = true, effect = 'lockpick' },
    dirtymoney = { label = 'Teanc de bani', weight = 0.05, stack = 500, type = 'item' },

    -- arme
    weapon_pistol   = { label = 'Pistol', weight = 1.2, stack = 1, type = 'weapon', weaponName = 'WEAPON_PISTOL',      ammoType = 'ammo_pistol' },
    weapon_pistol50 = {label = 'Pistol .50', weight = 1.2, stack = 1, type = 'weapon', weaponName = 'WEAPON_PISTOL50', ammoType = 'ammo_pistol50' },
    weapon_smg      = { label = 'SMG',    weight = 2.5, stack = 1, type = 'weapon', weaponName = 'WEAPON_MICROSMG',    ammoType = 'ammo_smg' },
    weapon_pump     = { label = 'Pusca',  weight = 3.5, stack = 1, type = 'weapon', weaponName = 'WEAPON_PUMPSHOTGUN', ammoType = 'ammo_shotgun' },
    weapon_bat      = { label = 'Bata',   weight = 1.8, stack = 1, type = 'weapon', weaponName = 'WEAPON_BAT' },

    -- munitie
    ammo_pistol   = { label = 'Gloante 9mm', weight = 0.02, stack = 500, type = 'ammo' },
    ammo_pistol50 = { label = 'Ammo .50', weight = 0.02, stack = 500, type = 'ammo' },
    ammo_smg      = { label = 'Gloante SMG', weight = 0.02, stack = 500, type = 'ammo' },
    ammo_shotgun  = { label = 'Cartuse',     weight = 0.05, stack = 500, type = 'ammo' },

    -- haine (drawable/texture pe ped freemode - exemple)
    clothing_cap    = { label = 'Sapca rosie',  weight = 0.2, stack = 1, type = 'clothing', slot = 'hat',    drawable = 5,  texture = 0 },
    clothing_jacket = { label = 'Geaca neagra', weight = 0.8, stack = 1, type = 'clothing', slot = 'jacket', drawable = 26, texture = 0 },
    clothing_pants  = { label = 'Blugi',        weight = 0.6, stack = 1, type = 'clothing', slot = 'pants',  drawable = 10, texture = 0 },
    clothing_shoes  = { label = 'Adidasi albi', weight = 0.5, stack = 1, type = 'clothing', slot = 'shoes',  drawable = 20, texture = 0 },
    clothing_bag    = { label = 'Rucsac',       weight = 1.0, stack = 1, type = 'clothing', slot = 'backpack', drawable = 45, texture = 0 },
}
