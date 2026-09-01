Config = {}

Config.OpenKey        = 'I'          -- tasta de deschidere (rebindabila din Settings)
Config.DefaultSlots   = 100          -- sloturi default / cont (se maresc prin /setslots -> ticket)
Config.MaxSlots       = 500          -- plafon /setslots (gridul ocupa 1..MaxSlots)
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
    MaxLoadedAmmo      = 500,           -- gloante maxim incarcate (implicit; override per-arma cu `maxAmmo`)
    MaxDurability      = 100.0,         -- durabilitate maxima (implicit; override per-arma cu `maxDurability`)
    DurabilityPerShot  = 0.20,          -- scade la fiecare glont tras
    BreakAtZero        = true,          -- la durabilitate 0 arma se sparge SI dispare din inventar
    BrokenBlocksEquip  = true,          -- durabilitate 0 => nu mai poti echipa arma
    HoverTooltipMs     = 2000,          -- cat tii cursorul pe arma pana apare tooltip-ul
}

-- ==========================================================
--  Atasamente (one-time-use)
--  Itemul-atasament se consuma la montare (drag atasament -> arma).
--  Ramane activ pe arma pana cand arma se sparge sau pana il scoti
--  manual din meniul de context al armei (butonul ✕ <label>).
--  `components` = numele componentei GTA per weaponName; daca lipseste
--  pentru arma respectiva, montarea e refuzata (incompatibil).
-- ==========================================================
Config.Attachments = {
    suppressor = {
        label = 'Amortizor',
        components = {
            WEAPON_PISTOL      = 'COMPONENT_AT_PI_SUPP_02',
            WEAPON_PISTOL50    = 'COMPONENT_AT_AR_SUPP_02',
            WEAPON_MICROSMG    = 'COMPONENT_AT_AR_SUPP_02',
            WEAPON_PUMPSHOTGUN = 'COMPONENT_AT_SR_SUPP',
        },
    },
    flashlight = {
        label = 'Lanterna tactica',
        components = {
            WEAPON_PISTOL   = 'COMPONENT_AT_PI_FLSH',
            WEAPON_PISTOL50 = 'COMPONENT_AT_PI_FLSH',
            WEAPON_MICROSMG = 'COMPONENT_AT_AR_FLSH',
        },
    },
    scope = {
        label = 'Luneta',
        components = {
            WEAPON_MICROSMG    = 'COMPONENT_AT_SCOPE_MACRO_02',
            WEAPON_PUMPSHOTGUN = 'COMPONENT_AT_SCOPE_MACRO_02',
        },
    },
    extmag = {
        label = 'Incarcator marit',
        components = {
            WEAPON_PISTOL   = 'COMPONENT_PISTOL_CLIP_02',
            WEAPON_PISTOL50 = 'COMPONENT_PISTOL50_CLIP_02',
            WEAPON_MICROSMG = 'COMPONENT_MICROSMG_CLIP_02',
        },
    },
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
--  Sloturi numerice unificate (strict numere intregi, fara suprapunere)
--    1     .. MaxSlots            -> grid normal
--    5001  .. 5006               -> sloturi de HAINE aplicate pe ped
--    5007  .. 5011               -> accesorii (rezervate; inca fara iteme)
--    6001  .. 6000+HotbarSlots   -> FAST SLOTS reale (arme / consumabile)
--
--  Bazele sunt mult peste MaxSlots ca sa nu existe niciodata coliziune
--  daca gridul creste prin /setslots.  Indexul de hotbar folosit de taste
--  ramane 1..HotbarSlots; slotul numeric intern e HotbarBase + index - 1.
-- ==========================================================
Config.EquipmentSlotIds = {
    hat = 5001, mask = 5002, jacket = 5003, pants = 5004, shoes = 5005, backpack = 5006,
    glasses = 5007, earrings = 5008, watch = 5009, bracelet = 5010, necklace = 5011,
}

-- reverse lookup [idNumeric] = cheieEchipament
Config.ClothingSlots = {}
for _eqKey, _eqId in pairs(Config.EquipmentSlotIds) do
    Config.ClothingSlots[_eqId] = _eqKey
end

Config.HotbarSlots = 5
Config.HotbarBase  = 6001   -- fast slot #i => slot numeric 6000 + i

-- ==========================================================
--  ITEME  (exemple - le inlocuiesti / adaugi liber)
--  type: 'item' | 'weapon' | 'ammo' | 'clothing'
-- ==========================================================

-- Hanorace staff F - haine streamate prin PREFIX ( ^ ), fara .meta (metoda replace).
-- Fisierele din [stream]/ph_clothing/stream/ INLOCUIESC un drawable vanilla de jbib
-- pentru  mp_f_freemode_01 . Pune aici acelasi index cu cel din numele fisierelor:
--   stream/mp_f_freemode_01^jbib_<N>_u.ydd  +  ^jbib_diff_<N>_[a|b|c]_uni.ytd
-- Indexul e folosit DIRECT la echipare si la /tryon; nu se citeste nicio colectie.
local STAFF_F_JBIB_DRAWABLE = 15   -- <<< pune indexul vanilla jbib pe care il inlocuiesti

Config.Items = {
    -- consumabile / misc
    water      = { label = 'Sticla de apa', weight = 0.5, stack = 20,  type = 'item', usable = true, effect = 'thirst', value = 25 },
    bread      = { label = 'Paine',         weight = 0.3, stack = 20,  type = 'item', usable = true, effect = 'hunger', value = 25 },
    bandage    = { label = 'Bandaj',        weight = 0.2, stack = 10,  type = 'item', usable = true, effect = 'heal',   value = 25 },
    phone      = { label = 'Telefon',       weight = 0.4, stack = 1,   type = 'item', usable = true, effect = 'phone' },
    radio      = { label = 'Statie radio',  weight = 0.6, stack = 1,   type = 'item', usable = true, effect = 'radio' },
    lockpick   = { label = 'Lockpick',      weight = 0.2, stack = 10,  type = 'item', usable = true, effect = 'lockpick' },
    dirtymoney = { label = 'Teanc de bani', weight = 0.05, stack = 500, type = 'item' },

    -- arme  (maxAmmo implicit = Config.Weapon.MaxLoadedAmmo = 500;
    --        revolvere / gadgeturi -> maxAmmo = 100)
    weapon_pistol   = { label = 'Pistol', weight = 1.2, stack = 1, type = 'weapon', weaponName = 'WEAPON_PISTOL',      ammoType = 'ammo_pistol' },
    weapon_pistol50 = {label = 'Pistol .50', weight = 1.2, stack = 1, type = 'weapon', weaponName = 'WEAPON_PISTOL50', ammoType = 'ammo_pistol50' },
    weapon_smg      = { label = 'SMG',    weight = 2.5, stack = 1, type = 'weapon', weaponName = 'WEAPON_MICROSMG',    ammoType = 'ammo_smg' },
    weapon_pump     = { label = 'Pusca',  weight = 3.5, stack = 1, type = 'weapon', weaponName = 'WEAPON_PUMPSHOTGUN', ammoType = 'ammo_shotgun' },
    weapon_bat      = { label = 'Bata',   weight = 1.8, stack = 1, type = 'weapon', weaponName = 'WEAPON_BAT' },
    weapon_revolver = { label = 'Revolver', weight = 1.6, stack = 1, type = 'weapon', weaponName = 'WEAPON_REVOLVER', ammoType = 'ammo_revolver', maxAmmo = 100 },
    weapon_flare    = { label = 'Pistol de semnalizare', weight = 1.0, stack = 1, type = 'weapon', weaponName = 'WEAPON_FLAREGUN', ammoType = 'ammo_flare', maxAmmo = 100 },

    -- munitie
    ammo_pistol   = { label = 'Gloante 9mm', weight = 0.02, stack = 500, type = 'ammo' },
    ammo_pistol50 = { label = 'Ammo .50', weight = 0.02, stack = 500, type = 'ammo' },
    ammo_smg      = { label = 'Gloante SMG', weight = 0.02, stack = 500, type = 'ammo' },
    ammo_shotgun  = { label = 'Cartuse',     weight = 0.05, stack = 500, type = 'ammo' },
    ammo_revolver = { label = 'Gloante .357', weight = 0.03, stack = 200, type = 'ammo' },
    ammo_flare    = { label = 'Rachete de semnalizare', weight = 0.08, stack = 50, type = 'ammo' },

    -- atasamente (one time use - se consuma la montare)
    at_suppressor = { label = 'Amortizor',          weight = 0.30, stack = 5, type = 'attachment', attachment = 'suppressor' },
    at_flashlight = { label = 'Lanterna tactica',   weight = 0.20, stack = 5, type = 'attachment', attachment = 'flashlight' },
    at_scope      = { label = 'Luneta',             weight = 0.40, stack = 5, type = 'attachment', attachment = 'scope' },
    at_extmag     = { label = 'Incarcator marit',   weight = 0.35, stack = 5, type = 'attachment', attachment = 'extmag' },

    -- haine (drawable/texture pe ped freemode - exemple)
    clothing_cap    = { label = 'Sapca rosie',  weight = 0.2, stack = 1, type = 'clothing', slot = 'hat',    drawable = 5,  texture = 0 },
    clothing_jacket = { label = 'Geaca neagra', weight = 0.8, stack = 1, type = 'clothing', slot = 'jacket', drawable = 26, texture = 0 },
    clothing_pants  = { label = 'Blugi',        weight = 0.6, stack = 1, type = 'clothing', slot = 'pants',  drawable = 10, texture = 0 },
    clothing_shoes  = { label = 'Adidasi albi', weight = 0.5, stack = 1, type = 'clothing', slot = 'shoes',  drawable = 20, texture = 0 },
    clothing_bag    = { label = 'Rucsac',       weight = 1.0, stack = 1, type = 'clothing', slot = 'backpack', drawable = 45, texture = 0 },

    -- Hanorace staff F (addon "mp_f_freemode_01_staff", jbib) - acelasi model, texturi diferite.
    -- Doar pe personaje FEMEIE (mp_f_freemode_01); pe barbat nu se aplica (index inexistent).
    -- Iconuri: pui .png in ph_inventory/html/img/ cu numele cheii (ex: staff_f_owner_jacket.png).
    staff_f_owner_jacket     = { label = 'Staff Jacket F - Owner',     weight = 0.8, stack = 1, type = 'clothing', slot = 'jacket', drawable = STAFF_F_JBIB_DRAWABLE, texture = 0 },
    staff_f_developer_jacket = { label = 'Staff Jacket F - Developer', weight = 0.8, stack = 1, type = 'clothing', slot = 'jacket', drawable = STAFF_F_JBIB_DRAWABLE, texture = 1 },
    staff_f_manager_jacket   = { label = 'Staff Jacket F - Manager',   weight = 0.8, stack = 1, type = 'clothing', slot = 'jacket', drawable = STAFF_F_JBIB_DRAWABLE, texture = 2 },
}
