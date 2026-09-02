-- ==========================================================
--  ph_appearance / client
--    - apply-lib (heritage / face / hair / overlays / eyes) + default outfit
--    - creator (creare personaj nou)  +  editor (/editcharacter)
--    - camera orbitala condusa din NUI (drag / zoom / focus)
-- ==========================================================
local PHCORE = 'ph-core'

local mode        = nil   -- nil | 'create' | 'editor'
local creatorReset = false -- true daca creatorul a fost deschis prin /resetcharacter
local cur         = nil   -- aspectul editat acum (tabel)
local editorCtx = nil     -- { targetId, targetName }
local ownBackup = nil     -- editor: aspectul + pozitia proprie, pentru restore
local cam       = nil
local camState  = {}
local uiFocus   = false

-- ----------------------------------------------------------
--  APLICARE ASPECT
-- ----------------------------------------------------------
local function ensureModel(gender)
    local name = Config.PedModels[gender] or Config.PedModels[0]
    local want = joaat(name)
    if GetEntityModel(PlayerPedId()) == want then return PlayerPedId() end
    RequestModel(want)
    local t = 0
    while not HasModelLoaded(want) and t < 300 do RequestModel(want); Wait(10); t = t + 1 end
    if not HasModelLoaded(want) then return PlayerPedId() end
    SetPlayerModel(PlayerId(), want)
    SetModelAsNoLongerNeeded(want)
    Wait(60)
    local p = PlayerPedId()
    SetPedDefaultComponentVariation(p)
    return p
end

--- aplica DOAR aspectul (nu si hainele)
local function applyAppearance(ap)
    ap = Appearance.Clamp(ap)
    local p = ensureModel(ap.gender)

    local h = ap.heritage
    SetPedHeadBlendData(p, h.mom, h.dad, 0, h.mom, h.dad, 0,
        h.shapeMix + 0.0, h.skinMix + 0.0, 0.0, false)

    SetPedComponentVariation(p, 2, ap.hair.style, 0, 0)
    SetPedHairColor(p, ap.hair.color, ap.hair.highlight)

    for i = 1, 20 do SetPedFaceFeature(p, i - 1, (ap.face[i] or 0.0) + 0.0) end

    for key, meta in pairs(Appearance.OVERLAYS) do
        local o = ap.overlays[key] or { style = -1, opacity = 1.0, color = 0, color2 = 0 }
        if not o.style or o.style < 0 then
            SetPedHeadOverlay(p, meta.id, 255, 0.0)
        else
            SetPedHeadOverlay(p, meta.id, o.style, (o.opacity or 1.0) + 0.0)
            if meta.color then
                SetPedHeadOverlayColor(p, meta.id, meta.color, o.color or 0, o.color2 or o.color or 0)
            end
        end
    end

    SetPedEyeColor(p, ap.eyeColor or 0)
    return p
end
exports('Apply', function(ap) return applyAppearance(ap) end)

--- ascunde / reafiseaza regiuni de corp (Config.BodyHide) pe componentele GTA.
--- `body` = { <regiune> = true/false }.  "ascuns" bate "vizibil" pe o componenta
--- partajata; "vizibil" revine la Config.NakedOutfit[gender].components[comp]
--- (fallback 0/0).  NU atinge parul (comp 2).
local function applyBody(p, gender, body)
    p = p or PlayerPedId()
    local cfg = Config.BodyHide and Config.BodyHide[gender]
    if not cfg then return end
    body = type(body) == 'table' and body or {}
    local naked = Config.NakedOutfit and Config.NakedOutfit[gender]
    local desired = {}   -- [comp] = { drawable, texture }
    for region, specs in pairs(cfg) do
        local hidden = body[region] == true
        for _, ov in ipairs(specs) do
            local comp = tonumber(ov.comp)
            if comp and comp ~= 2 then
                if hidden then
                    desired[comp] = { ov.drawable or 0, ov.texture or 0 }
                elseif desired[comp] == nil then
                    local nb = naked and naked.components and naked.components[comp]
                    desired[comp] = { nb and nb[1] or 0, nb and nb[2] or 0 }
                end
            end
        end
    end
    for comp, dt in pairs(desired) do
        SetPedComponentVariation(p, comp, dt[1], dt[2], 0)
    end
end
exports('ApplyBody', function(gender, body) applyBody(PlayerPedId(), tonumber(gender) or 0, body) end)

--- aspectul "dezbracat" (Config.NakedOutfit) - reperul fara haine de inventar.
--- NU atinge parul (comp 2).  `body` (optional) = regiuni ascunse, aplicate peste baza.
local function applyNakedBase(p, gender, body)
    p = p or PlayerPedId()
    local o = Config.NakedOutfit and Config.NakedOutfit[gender]
    if not o then SetPedDefaultComponentVariation(p); applyBody(p, gender, body); return end
    for comp, dt in pairs(o.components or {}) do
        comp = tonumber(comp)
        if comp and comp ~= 2 then SetPedComponentVariation(p, comp, dt[1] or 0, dt[2] or 0, 0) end
    end
    for prop, dt in pairs(o.props or {}) do
        prop = tonumber(prop)
        if prop then
            if (dt[1] or -1) < 0 then ClearPedProp(p, prop)
            else SetPedPropIndex(p, prop, dt[1], dt[2] or 0, true) end
        end
    end
    applyBody(p, gender, body)
end
exports('ApplyNakedBase', function(gender, body) applyNakedBase(PlayerPedId(), tonumber(gender) or 0, body) end)

--- cere lui ph_inventory sa re-capteze baza (acum "dezbracat") si sa re-echipeze
local function reapplyInventoryClothes()
    TriggerEvent('ph_appearance:cl:reapplyEquipment')
end

-- ----------------------------------------------------------
--  HOOK: la intrarea in joc, aplica aspectul salvat + hainele
-- ----------------------------------------------------------
AddEventHandler('ph-core:client:playerLoaded', function(char)
    if mode then return end   -- daca suntem in creator/editor, nu ne bagam
    local ap = Appearance.Decode(char and char.appearance)
    local gender = tonumber(char and char.gender) or 0
    CreateThread(function()
        Wait(50)
        if ap then applyAppearance(ap) else ensureModel(gender) end
        Wait(60)
        applyNakedBase(PlayerPedId(), ap and ap.gender or gender, ap and ap.body)
        -- re-aplica o data dupa ce totul e stabil (unele slot-uri se pot reseta la spawn)
        Wait(400)
        if not mode then
            if ap then applyAppearance(ap) end
            applyNakedBase(PlayerPedId(), ap and ap.gender or gender, ap and ap.body)
        end
        -- ph_inventory (hook-ul lui de playerLoaded) capteaza baza si echipeaza hainele
    end)
end)

--- staff a modificat aspectul unui jucator online (din /editcharacter -> Save)
RegisterNetEvent('ph_appearance:cl:applyLive', function(ap)
    if mode then return end   -- daca tocmai edita ceva, nu ne bagam
    CreateThread(function()
        applyAppearance(ap)
        Wait(50)
        applyNakedBase(PlayerPedId(), (ap and ap.gender) or 0, ap and ap.body)
        Wait(30)
        reapplyInventoryClothes()   -- ph_inventory re-echipeaza hainele purtate
    end)
end)

-- ==========================================================
--  CAMERA
-- ==========================================================
local function camReset()
    local d = Config.Camera.default
    camState = { radius = d.radius, heading = d.heading, pitch = d.pitch, targetZ = d.targetZ }
end

local function camUpdate()
    if not cam then return end
    local p = PlayerPedId()
    local base = GetEntityCoords(p)
    local tz = base.z + (camState.targetZ or 0.6)
    local a  = math.rad(GetEntityHeading(p) + (camState.heading or 0.0))
    local pr = math.rad(camState.pitch or 0.0)
    local horiz = (camState.radius or 1.3) * math.cos(pr)
    local fx, fy = -math.sin(a), math.cos(a)
    SetCamCoord(cam, base.x + fx * horiz, base.y + fy * horiz, tz + (camState.radius or 1.3) * math.sin(pr))
    PointCamAtCoord(cam, base.x, base.y, tz)
end

local function camStart()
    camReset()
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 50.0, false, 0)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, false)
    camUpdate()
end

local function camStop()
    RenderScriptCams(false, false, 0, true, false)
    if cam then DestroyCam(cam, false); cam = nil end
end

-- ==========================================================
--  MAXIME dependente de ped (pentru sliders in NUI)
-- ==========================================================
local function computeMaxes(p)
    local ov = {}
    for key, meta in pairs(Appearance.OVERLAYS) do
        ov[key] = math.max(0, (GetPedHeadOverlayNum(meta.id) or 1) - 1)
    end
    return {
        hair      = math.max(0, GetNumberOfPedDrawableVariations(p, 2) - 1),
        hairColor = (Config.Palettes.hair or 64) - 1,
        makeupColor = (Config.Palettes.makeup or 64) - 1,
        eyeColor  = 30,
        heritageParent = 45,
        overlays  = ov,
        faceCount = Config.FaceFeatureCount or 20,
    }
end

-- ==========================================================
--  SCENA (freeze + teleport + cam + NUI)
-- ==========================================================
local sceneThread = nil

local function enterScene()
    local p = PlayerPedId()
    DoScreenFadeOut(350); Wait(400)

    if mode == 'editor' then
        local c = GetEntityCoords(p)
        ownBackup = ownBackup or {}
        ownBackup.coords  = c
        ownBackup.heading = GetEntityHeading(p)
    end

    local s = Config.Camera.scene
    SetEntityCoordsNoOffset(p, s.x + 0.0, s.y + 0.0, s.z + 0.0, false, false, false)
    SetEntityHeading(p, s.h + 0.0)
    FreezeEntityPosition(p, true)
    SetEntityInvincible(p, true)
    SetEntityVisible(p, true, false)
    RequestCollisionAtCoord(s.x, s.y, s.z)
    local t = 0
    while not HasCollisionLoadedAroundEntity(p) and t < 100 do Wait(10); t = t + 1 end

    camStart()
    SetNuiFocus(true, true); uiFocus = true
    Wait(200); DoScreenFadeIn(400)

    if sceneThread then sceneThread = nil end
    sceneThread = true
    CreateThread(function()
        while sceneThread do
            HideHudAndRadarThisFrame()
            DisableAllControlActions(0)
            camUpdate()
            Wait(0)
        end
    end)
end

local function leaveScene()
    local wasCreate = (mode == 'create')
    sceneThread = nil
    if wasCreate then DoScreenFadeOut(300); Wait(320) end   -- acopera golul pana la FinalizeSpawn
    camStop()
    SetNuiFocus(false, false); uiFocus = false
    SendNUIMessage({ action = 'close' })

    local p = PlayerPedId()
    if mode == 'editor' and ownBackup then
        DoScreenFadeOut(300); Wait(350)
        -- reface aspectul propriu al managerului
        local me = exports[PHCORE]:GetCharacter()
        local myAp = Appearance.Decode(me and me.appearance)
        if myAp then applyAppearance(myAp) else ensureModel(tonumber(me and me.gender) or 0) end
        Wait(30)
        applyNakedBase(PlayerPedId(), myAp and myAp.gender or (tonumber(me and me.gender) or 0), myAp and myAp.body)
        reapplyInventoryClothes()   -- re-echipeaza hainele proprii ale managerului
        p = PlayerPedId()
        if ownBackup.coords then
            SetEntityCoordsNoOffset(p, ownBackup.coords.x, ownBackup.coords.y, ownBackup.coords.z, false, false, false)
            SetEntityHeading(p, ownBackup.heading or 0.0)
        end
        Wait(150); DoScreenFadeIn(400)
        FreezeEntityPosition(p, false)
        SetEntityInvincible(p, false)
    end
    -- in modul 'create' lasam ped-ul inghetat: ph-core FinalizeSpawn il elibereaza
    -- dupa ce il muta la spawn-ul de personaj nou.

    mode, cur, editorCtx, ownBackup = nil, nil, nil, nil
end

-- ==========================================================
--  CREATOR (personaj nou)  - declansat de ph-core
-- ==========================================================
RegisterNetEvent('ph_appearance:cl:startCreator', function(data)
    data = data or {}
    if mode then return end
    mode = 'create'
    creatorReset = data.reset == true
    cur = Appearance.Default(tonumber(data.gender) or 0)

    enterScene()
    local p = applyAppearance(cur)
    applyBody(p, cur.gender, cur.body)
    SendNUIMessage({
        action = 'open',
        data = {
            mode = 'create',
            appearance = cur,
            maxes = computeMaxes(p),
            overlayOrder = Appearance.OVERLAY_ORDER,
            bodyParts = Appearance.BODY_PARTS,
        },
    })
end)

-- ==========================================================
--  EDITOR (/editcharacter [sqlId])  - declansat de server dupa validare
-- ==========================================================
RegisterNetEvent('ph_appearance:cl:startEditor', function(data)
    data = data or {}
    if mode then return end
    mode = 'editor'
    editorCtx = { targetId = data.targetId, targetName = data.targetName }
    cur = data.appearance and Appearance.Clamp(data.appearance)
        or Appearance.Default(tonumber(data.gender) or 0)

    enterScene()
    local p = applyAppearance(cur)
    applyBody(p, cur.gender, cur.body)
    SendNUIMessage({
        action = 'open',
        data = {
            mode = 'editor',
            targetId = data.targetId,
            targetName = data.targetName,
            appearance = cur,
            template = data.template or nil,
            maxes = computeMaxes(p),
            overlayOrder = Appearance.OVERLAY_ORDER,
            bodyParts = Appearance.BODY_PARTS,
        },
    })
end)

--- managerul a comutat M/F -> serverul trimite preset-ul (daca exista) pt noul gen
RegisterNetEvent('ph_appearance:cl:editorTemplate', function(payload)
    payload = payload or {}
    local gender = (tonumber(payload.gender) == 1) and 1 or 0
    -- baza: aspectul live al tintei daca genul se potriveste, altfel default
    if payload.liveSame and type(payload.live) == 'table' then
        cur = Appearance.Clamp(payload.live)
    else
        cur = Appearance.Default(gender)
    end
    cur.gender = gender
    local p = applyAppearance(cur)
    applyBody(p, cur.gender, cur.body)
    SendNUIMessage({
        action = 'genderSwitched',
        data = {
            gender = gender,
            appearance = cur,
            template = payload.template or nil,
            maxes = computeMaxes(p),
            bodyParts = Appearance.BODY_PARTS,
        },
    })
end)

-- ==========================================================
--  NUI callbacks
-- ==========================================================
--- update incremental: { section, key/index, value, [sub] }
RegisterNUICallback('paUpdate', function(d, cb)
    cb('ok')
    if not cur or not d then return end
    local s = d.section
    if s == 'gender' then
        -- comutare M/F
        local g = (tonumber(d.value) == 1) and 1 or 0
        if mode == 'editor' and editorCtx then
            TriggerServerEvent('ph_appearance:sv:editorGender', { targetId = editorCtx.targetId, gender = g })
        else
            cur.gender = g
            local p = applyAppearance(cur)
            applyBody(p, cur.gender, cur.body)
            SendNUIMessage({ action = 'genderSwitched', data = {
                gender = g, appearance = cur, maxes = computeMaxes(p), bodyParts = Appearance.BODY_PARTS } })
        end
        return
    elseif s == 'body' then
        cur.body = type(cur.body) == 'table' and cur.body or {}
        cur.body[d.key] = d.value == true
        applyBody(PlayerPedId(), cur.gender, cur.body)
        return
    elseif s == 'heritage' then
        cur.heritage[d.key] = tonumber(d.value) or cur.heritage[d.key]
    elseif s == 'face' then
        local i = (tonumber(d.index) or 0) + 1
        if i >= 1 and i <= 20 then cur.face[i] = tonumber(d.value) or 0.0 end
    elseif s == 'hair' then
        cur.hair[d.key] = math.floor(tonumber(d.value) or 0)
    elseif s == 'eyeColor' then
        cur.eyeColor = math.floor(tonumber(d.value) or 0)
    elseif s == 'overlay' then
        local o = cur.overlays[d.key]; if not o then return end
        o[d.sub or 'style'] = (d.sub == 'opacity') and (tonumber(d.value) or 1.0) or math.floor(tonumber(d.value) or 0)
    else
        return
    end
    applyAppearance(cur)
end)

RegisterNUICallback('paCam', function(d, cb)
    cb('ok')
    if not cam or not d then return end
    if d.focus == 'reset' then
        camReset()
    elseif d.focus and Config.Camera.focus[d.focus] then
        local f = Config.Camera.focus[d.focus]
        camState.radius  = f.radius  or camState.radius
        camState.targetZ = f.targetZ or camState.targetZ
        camState.pitch   = f.pitch   or camState.pitch
        camState.heading = 0.0
    else
        if d.dh then camState.heading = (camState.heading + d.dh * (Config.Camera.dragSpeed or 0.35)) % 360 end
        if d.dp then
            camState.pitch = math.max(Config.Camera.minPitch,
                math.min(Config.Camera.maxPitch, camState.pitch - d.dp * (Config.Camera.dragSpeed or 0.35)))
        end
        if d.dz then
            camState.radius = math.max(Config.Camera.minRadius,
                math.min(Config.Camera.maxRadius, camState.radius - d.dz * (Config.Camera.zoomStep or 0.12)))
        end
    end
    camUpdate()
end)

RegisterNUICallback('paLoadTemplate', function(d, cb)
    cb('ok')
    if not cur or type(d) ~= 'table' or type(d.appearance) ~= 'table' then return end
    cur = Appearance.Clamp(d.appearance)
    local p = applyAppearance(cur)
    applyBody(p, cur.gender, cur.body)
    SendNUIMessage({ action = 'setAll', data = {
        appearance = cur, maxes = computeMaxes(p), bodyParts = Appearance.BODY_PARTS } })
end)

--- CREATE: gata -> trimite la server, care scrie DB si anunta ph-core
RegisterNUICallback('paCreateDone', function(d, cb)
    cb('ok')
    if mode ~= 'create' or not cur then return end
    if type(d) == 'table' and type(d.appearance) == 'table' then cur = Appearance.Clamp(d.appearance) end
    TriggerServerEvent('ph_appearance:sv:saveCreate', { appearance = cur, reset = creatorReset })
    creatorReset = false
    leaveScene()   -- ph-core va face spawn-ul; scena se inchide
end)

--- EDITOR: "Save"  (aspect live al tintei)
RegisterNUICallback('paEditorSave', function(d, cb)
    cb('ok')
    if mode ~= 'editor' or not editorCtx then return end
    local ap = (type(d) == 'table' and type(d.appearance) == 'table') and Appearance.Clamp(d.appearance) or cur
    TriggerServerEvent('ph_appearance:sv:editorSave', {
        targetId = editorCtx.targetId, targetName = editorCtx.targetName, appearance = ap,
    })
end)

--- EDITOR: "Save Character"  (preset per gen)
RegisterNUICallback('paEditorTemplate', function(d, cb)
    cb('ok')
    if mode ~= 'editor' or not editorCtx then return end
    local ap = (type(d) == 'table' and type(d.appearance) == 'table') and Appearance.Clamp(d.appearance) or cur
    TriggerServerEvent('ph_appearance:sv:editorTemplate', {
        targetId = editorCtx.targetId, targetName = editorCtx.targetName, appearance = ap,
    })
end)

RegisterNUICallback('paClose', function(_, cb)
    cb('ok')
    if mode == 'create' then return end   -- creatorul nu se poate inchide fara confirm
    leaveScene()
end)
