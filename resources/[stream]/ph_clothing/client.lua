-- ==========================================================
--  ph_clothing / client
--  Aplica pe ped-ul apelantului comenzile primite de la server (/tryon).
--  Util ca sa verifici ca hainele custom (addon sau replace) chiar se incarca
--  si ca sa afli indexul unui drawable nou.
-- ==========================================================
local function notify(text, kind)
    -- notificare deasupra minimapului (export client din ph-core)
    exports['ph-core']:Notify(tostring(text), kind or 'info')
end

RegisterNetEvent('ph_clothing:cl:tryon', function(p)
    p = p or {}
    local ped = PlayerPedId()

    if p.op == 'reset' then
        SetPedDefaultComponentVariation(ped)
        return

    elseif p.op == 'info' then
        print('^5[ph_clothing]^7 --- component drawables (id: count / current) ---')
        for _, id in ipairs(Config.Components or {}) do
            print(('  component %2d : %d variations, current drawable %d / texture %d')
                :format(id, GetNumberOfPedDrawableVariations(ped, id),
                        GetPedDrawableVariation(ped, id), GetPedTextureVariation(ped, id)))
        end
        for _, id in ipairs(Config.Props or {}) do
            print(('  prop      %2d : %d variations, current drawable %d')
                :format(id, GetNumberOfPedPropDrawableVariations(ped, id),
                        GetPedPropIndex(ped, id)))
        end
        notify('Clothing info dumped to the F8 console.', 'info')
        return

    elseif p.op == 'component' then
        local maxDraw = GetNumberOfPedDrawableVariations(ped, p.id)
        if p.drawable < 0 or p.drawable >= maxDraw then
            notify(('component %d: drawable %d out of range (0..%d)'):format(p.id, p.drawable, maxDraw - 1), 'error')
            return
        end
        local maxTex = GetNumberOfPedTextureVariations(ped, p.id, p.drawable)
        local tex = (p.texture >= 0 and p.texture < maxTex) and p.texture or 0
        SetPedComponentVariation(ped, p.id, p.drawable, tex, 0)
        notify(('component %d -> drawable %d / texture %d  (max drawable %d)'):format(p.id, p.drawable, tex, maxDraw - 1), 'success')
        return

    elseif p.op == 'prop' then
        local maxDraw = GetNumberOfPedPropDrawableVariations(ped, p.id)
        if p.drawable < -1 or p.drawable >= maxDraw then
            notify(('prop %d: drawable %d out of range (-1..%d)'):format(p.id, p.drawable, maxDraw - 1), 'error')
            return
        end
        if p.drawable == -1 then
            ClearPedProp(ped, p.id)
        else
            local maxTex = GetNumberOfPedPropTextureVariations(ped, p.id, p.drawable)
            local tex = (p.texture >= 0 and p.texture < maxTex) and p.texture or 0
            SetPedPropIndex(ped, p.id, p.drawable, tex, true)
        end
        notify(('prop %d -> drawable %d / texture %d  (max drawable %d)'):format(p.id, p.drawable, p.texture, maxDraw - 1), 'success')
        return
    end
end)

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    TriggerEvent('chat:addSuggestion', '/tryon', 'Staff: test a clothing slot on yourself', {
        { name = 'component|prop|reset|info' },
        { name = 'id',       help = 'slot id (see config.lua)' },
        { name = 'drawable', help = 'variation index (-1 on a prop = remove)' },
        { name = 'texture',  help = 'optional, default 0' },
    })
end)
