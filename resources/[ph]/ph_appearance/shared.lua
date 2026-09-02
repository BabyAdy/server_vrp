-- ==========================================================
--  ph_appearance / shared  -  schema + defaults + clamp
--
--  Formatul `appearance` (JSON in users.appearance / character_templates):
--  {
--    gender   = 0|1,
--    heritage = { mom = 0..45, dad = 0..45, shapeMix = 0..1, skinMix = 0..1 },
--    face     = [20 floats -1..1]   -- index k -> SetPedFaceFeature(ped, k-1, v)
--    hair     = { style, color, highlight },
--    overlays = { <key> = { style = -1..N, opacity = 0..1, color, color2 } },
--    eyeColor = 0..63,
--  }
--  Hainele NU fac parte din acest format (vezi Config.DefaultOutfit).
-- ==========================================================
Appearance = Appearance or {}

--- key -> { id = GTA head-overlay id, color = colorType (nil daca fara), female = true daca doar F }
Appearance.OVERLAYS = {
    blemishes  = { id = 0,  color = nil },
    beard      = { id = 1,  color = 1 },
    eyebrows   = { id = 2,  color = 1 },
    ageing     = { id = 3,  color = nil },
    makeup     = { id = 4,  color = 2, female = true },
    blush      = { id = 5,  color = 2, female = true },
    complexion = { id = 6,  color = nil },
    sundamage  = { id = 7,  color = nil },
    lipstick   = { id = 8,  color = 2, female = true },
    moles      = { id = 9,  color = nil },
}

--- ordine stabila pentru UI
Appearance.OVERLAY_ORDER = {
    'eyebrows', 'beard', 'ageing', 'complexion', 'sundamage',
    'blemishes', 'moles', 'makeup', 'blush', 'lipstick',
}

--- Regiuni de corp care pot fi ascunse din creator / /editcharacter (tab "Body").
--- `key` intra in appearance.body ca boolean (true = ascuns).  Maparea reala
--- key -> componente GTA + drawable "invizibil" e in Config.BodyHide[gender].
Appearance.BODY_PARTS = {
    { key = 'arms',  label = 'Arms & hands' },
    { key = 'torso', label = 'Chest & abdomen' },
    { key = 'legs',  label = 'Legs' },
    { key = 'feet',  label = 'Feet' },
}

local function clampn(v, lo, hi, d)
    v = tonumber(v)
    if v == nil then return d end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
Appearance.ClampNum = clampn

function Appearance.Default(gender)
    gender = (tonumber(gender) == 1) and 1 or 0
    local face = {}
    for i = 1, 20 do face[i] = 0.0 end

    local ov = {}
    for key in pairs(Appearance.OVERLAYS) do
        ov[key] = { style = -1, opacity = 1.0, color = 0, color2 = 0 }
    end
    ov.eyebrows.style = 0   -- macar sprancene vizibile din start

    local body = {}
    for _, bp in ipairs(Appearance.BODY_PARTS) do body[bp.key] = false end

    return {
        gender   = gender,
        heritage = { mom = 0, dad = 0, shapeMix = 0.5, skinMix = 0.5 },
        face     = face,
        hair     = { style = 0, color = 0, highlight = 0 },
        overlays = ov,
        eyeColor = 0,
        body     = body,
    }
end

--- sanitizeaza orice input (din DB sau din NUI) la game-safe.
function Appearance.Clamp(a)
    a = type(a) == 'table' and a or {}
    local g = (tonumber(a.gender) == 1) and 1 or 0

    local h  = type(a.heritage) == 'table' and a.heritage or {}
    local hr = type(a.hair) == 'table' and a.hair or {}

    local sf = type(a.face) == 'table' and a.face or {}
    local face = {}
    for i = 1, 20 do face[i] = clampn(sf[i], -1.0, 1.0, 0.0) end

    local osrc = type(a.overlays) == 'table' and a.overlays or {}
    local ov = {}
    for key in pairs(Appearance.OVERLAYS) do
        local o = type(osrc[key]) == 'table' and osrc[key] or {}
        ov[key] = {
            style   = math.floor(clampn(o.style, -1, 255, -1)),
            opacity = clampn(o.opacity, 0.0, 1.0, 1.0),
            color   = math.floor(clampn(o.color, 0, 255, 0)),
            color2  = math.floor(clampn(o.color2, 0, 255, 0)),
        }
    end

    local bsrc = type(a.body) == 'table' and a.body or {}
    local body = {}
    for _, bp in ipairs(Appearance.BODY_PARTS) do body[bp.key] = bsrc[bp.key] == true end

    return {
        gender   = g,
        heritage = {
            mom      = math.floor(clampn(h.mom, 0, 45, 0)),
            dad      = math.floor(clampn(h.dad, 0, 45, 0)),
            shapeMix = clampn(h.shapeMix, 0.0, 1.0, 0.5),
            skinMix  = clampn(h.skinMix, 0.0, 1.0, 0.5),
        },
        face     = face,
        hair     = {
            style     = math.floor(clampn(hr.style, 0, 255, 0)),
            color     = math.floor(clampn(hr.color, 0, 255, 0)),
            highlight = math.floor(clampn(hr.highlight, 0, 255, 0)),
        },
        overlays = ov,
        eyeColor = math.floor(clampn(a.eyeColor, 0, 63, 0)),
        body     = body,
    }
end

--- decode helper tolerant (string JSON / tabel / nil)
function Appearance.Decode(v)
    if type(v) == 'table' then return v end
    if type(v) ~= 'string' or v == '' then return nil end
    local ok, t = pcall(json.decode, v)
    return ok and type(t) == 'table' and t or nil
end
