local _, NS = ...
local Plate = {}
NS.NameplateCombat = Plate

local T, K, tr = NS.Theme, NS.Kit, NS.Locale.Text
local MAX_ACTIVE, MAX_PER_TARGET, MAX_HITS = 40, 4, 3
local REVALIDATE_INTERVAL = .1
local AMOUNT_SCALE = 1.8   -- amounts are this much larger than the size setting
local CAPTION_SCALE = .85  -- the caption is this much smaller
local AMOUNT_BUDGET = 3.2  -- em reserved per protected amount where its end is not known
local PLUS_SCALE = .62
local PLUS_GAP = 3        -- between the ink of an amount and the "+"
-- Where the figures' ink stands in an amount's text box, of the amount size (seen in the game on
-- 2026-11-22 at size 23): its foot this far above the box's bottom, and this high.
local FIGURE_FOOT, FIGURE_HEIGHT = .22, .72
-- The plate: a flat box with a hairline in the card's colour, the icon flush in its left end, the
-- amounts beside it, and the caption free above it (inside it on a card without amounts).
local EDGE, BOX_PAD, PAD_LEFT, PAD_RIGHT, ROW_GAP, CAPTION_GAP = 1, 5, 6, 7, 3, 2
local SUB_DIM = .72       -- the caption's second part, in the card's colour made darker
local families = {
    weapon = {key = "procPlateWeapon", name = "Windfury", sub = "Weapon", icon = "star", spells = {8232, 16361}},
    totem = {key = "procPlateTotem", name = "Windfury", sub = "Totem", icon = "activities", spells = {8512, 8516}},
    extra = {key = "procPlateExtra", name = "Extra Attack", icon = "pvp"},
}

local function finite(value)
    return type(value) == "number" and value == value and value < math.huge and value > -math.huge
end

local function spellTexture(api, result, family)
    if family == families.extra then return api:SpellIcon(result.spellID) end
    for _, id in ipairs(family.spells or {}) do
        local icon = api:SpellIcon(id)
        if icon then return icon end
    end
end

-- The card's content. A protected amount stays an opaque line and only reaches a renderer slot.
local function content(api, result, family, config)
    local hits = type(result.hits) == "table" and result.hits or {}
    local count = result.hitCount
    if not api:Public(count) or not finite(count) or count < 1 or count % 1 ~= 0 then count = 0 end
    local complete = result.complete == true
    local main, sub = "", ""
    if config.procPlateName then
        local spellName = family == families.extra and api:SpellName(result.spellID)
        main = string.upper(spellName or tr(family.name))
        sub = family.sub and string.upper(tr(family.sub)) or ""
    end
    if config.procPlateGroup and complete and count > 1 then
        sub = (sub ~= "" and sub .. " " or "") .. "×" .. count
    end
    local items = {}
    if config.procPlateAmounts then
        for _, hit in ipairs(hits) do
            local amount = hit.amount
            if #items < MAX_HITS then
                if api:Public(amount) and finite(amount) then
                    local critical = config.procPlateHighlight and api:Public(hit.critical) and hit.critical == true
                    items[#items + 1] = {text = tostring(amount) .. (critical and "!" or ""), critical = critical}
                elseif hit.line ~= nil then
                    items[#items + 1] = {line = hit.line}
                elseif hit.miss then
                    items[#items + 1] = {miss = true}
                end
            end
        end
    end
    local icon, texture = nil, nil
    if config.procPlateIcon then
        texture = spellTexture(api, result, family)
        if not texture then icon = family.icon end
    end
    if not icon and not texture and main == "" and sub == "" and #items == 0 then return end
    return {main = main, sub = sub, items = items, icon = icon, texture = texture}
end

local function createCard(api, renderer)
    local root = api:Root()
    if not root then return end
    local frame = CreateFrame("Frame", nil, root)
    frame:EnableMouse(false)
    frame:Hide()
    local divider = frame:CreateTexture(nil, "BORDER")
    local spell = frame:CreateTexture(nil, "ARTWORK")
    spell:SetTexCoord(.08, .92, .08, .92)
    spell:Hide()
    local card = {
        frame = frame, box = K.Plate(frame, "surface"), divider = divider, spell = spell,
        icon = K.Icon(frame, "star", 16, "gold"),
        main = K.Text(frame, "", "overline"), sub = K.Text(frame, "", "overline"),
        texts = {}, slots = {}, pluses = {},
    }
    for index = 1, MAX_HITS do
        card.texts[index] = K.Text(frame, "", "body")
        if renderer then card.slots[index] = renderer:NewSlot(frame) end
        if index < MAX_HITS then card.pluses[index] = K.Text(frame, "+", "body") end
    end
    return card
end

local function putText(card, field, value, size, x, y, font)
    field:SetText(value)
    field:SetShown(value ~= "")
    if value == "" then return 0 end
    field:SetFont(font, size, "OUTLINE")
    field:ClearAllPoints()
    field:SetPoint("TOPLEFT", card.frame, "TOPLEFT", x, -y)
    return math.ceil(field:GetStringWidth())
end

local function clearItems(card)
    for index = 1, MAX_HITS do
        card.texts[index]:SetText("")
        card.texts[index]:Hide()
        if card.slots[index] then card.slots[index]:Clear() end
        if card.pluses[index] then card.pluses[index]:Hide() end
    end
end

-- Amounts side by side ("291 + 317") or stacked. Each element is anchored to the end of the one
-- before it, so no protected text is measured. bottom: the first row's text foot under the card's
-- top; pitch: from one row to the next. Returns the reserved width, the amounts shown and, for a
-- row, where its last amount ends (region, point, x), if that is known.
local function layoutItems(card, items, x, bottom, pitch, px, font, config)
    clearItems(card)
    local column = config.procPlateLayout == "column"
    local plusPx = math.max(8, math.floor(px * PLUS_SCALE + .5))
    -- The "+" stands at the middle of the figures.
    local lift = math.floor((FIGURE_FOOT + FIGURE_HEIGHT / 2) * px - .45 * plusPx + .5)
    local trail, width, shown = nil, 0, 0
    for _, item in ipairs(items) do
        local region, point, dx, dy
        local plus = not column and trail and card.pluses[shown] or nil
        if plus then
            plus:SetFont(font, plusPx, "OUTLINE")
            T.Tint(plus, "SetTextColor", "muted")
            plus:ClearAllPoints()
            plus:SetPoint("BOTTOMLEFT", trail[1], trail[2], trail[3] + PLUS_GAP, lift)
            plus:Show()
            region, point, dx, dy = plus, "BOTTOMRIGHT", PLUS_GAP, -lift
        else
            region, point, dx, dy = card.frame, "TOPLEFT", x, -(bottom + (column and shown * pitch or 0))
        end
        local index = shown + 1
        local placed, itemWidth, itemTrail = false, 0, nil
        if item.line ~= nil and card.slots[index] then
            local slot = card.slots[index]
            slot:Place(region, point, dx, dy)
            if slot:SetLine(item.line, px, #items == 1) then
                local tailRegion, tailPoint, tailX = slot:Trail()
                if tailRegion then itemTrail = {tailRegion, tailPoint, tailX} end
                -- Also in push mode: its field is nine figures wide, the box only as wide as an amount.
                itemWidth = math.ceil(AMOUNT_BUDGET * px)
                placed = true
            end
        elseif item.text or item.miss then
            local label = card.texts[index]
            label:SetFont(font, item.miss and plusPx or px, "OUTLINE")
            label:SetText(item.text or tr("Miss"))
            T.Tint(label, "SetTextColor", item.critical and "goldBright" or item.miss and "muted" or "text")
            label:ClearAllPoints()
            label:SetPoint("BOTTOMLEFT", region, point, dx, dy)
            label:Show()
            itemTrail = {label, "BOTTOMRIGHT", 0}
            itemWidth = math.ceil(label:GetStringWidth())
            placed = true
        end
        if placed then
            shown = shown + 1
            trail = itemTrail
            if column then width = math.max(width, itemWidth)
            else width = width + itemWidth + (plus and 2 * PLUS_GAP + math.ceil(plus:GetStringWidth()) or 0) end
            -- A protected amount in push mode has no known end: nothing more fits in its row.
            if not column and not trail then break end
        elseif plus then
            -- A refused line leaves no gap: the next amount takes its place.
            plus:Hide()
        end
    end
    return width, shown, not column and trail or nil
end

local function fill(api, card, config, model)
    local font, size, color = api:Font(), config.procPlateSize, config.procPlateColor
    local px = math.floor(size * AMOUNT_SCALE + .5)
    local captionPx = math.max(9, math.floor(size * CAPTION_SCALE + .5))
    local column = config.procPlateLayout == "column"
    local hasItems = #model.items > 0
    local hasCaption = model.main ~= "" or model.sub ~= ""
    -- Without amounts the caption stands inside the box.
    local inside = hasCaption and not hasItems
    local rows = hasItems and (column and math.min(#model.items, MAX_HITS) or 1) or 0
    local rowHeight = math.ceil(FIGURE_HEIGHT * px)
    local height = hasItems and 2 * BOX_PAD + rows * rowHeight + (rows - 1) * ROW_GAP or captionPx + 2 * BOX_PAD
    local top = hasCaption and not inside and captionPx + CAPTION_GAP or 0

    card.icon:Hide()
    card.spell:Hide()
    card.divider:Hide()
    local x = EDGE
    local visual = model.texture and card.spell or model.icon and card.icon or nil
    if visual then
        local cell = height - 2 * EDGE
        local inset = model.texture and 0 or 3
        if model.texture then card.spell:SetTexture(model.texture) else T.SetIcon(card.icon, model.icon, "gold") end
        visual:SetSize(cell - 2 * inset, cell - 2 * inset)
        visual:ClearAllPoints()
        visual:SetPoint("TOPLEFT", card.frame, "TOPLEFT", EDGE + inset, -(top + EDGE + inset))
        visual:Show()
        card.divider:ClearAllPoints()
        card.divider:SetPoint("TOPLEFT", card.frame, "TOPLEFT", EDGE + cell, -(top + EDGE))
        card.divider:SetSize(EDGE, cell)
        card.divider:SetColorTexture(color[1], color[2], color[3], .55)
        card.divider:Show()
        x = EDGE + cell + EDGE
    end
    local contentX = x + PAD_LEFT

    local captionX = inside and contentX or EDGE
    local captionY = inside and top + math.floor((height - captionPx) / 2) or 0
    local mainWidth = putText(card, card.main, model.main, captionPx, captionX, captionY, font)
    card.main:SetTextColor(color[1], color[2], color[3])
    local subX = captionX + (mainWidth > 0 and mainWidth + 4 or 0)
    local subWidth = putText(card, card.sub, model.sub, captionPx, subX, captionY, font)
    card.sub:SetTextColor(color[1] * SUB_DIM, color[2] * SUB_DIM, color[3] * SUB_DIM)
    local captionWidth = subX - captionX + subWidth

    local rowWidth, shown, trail = 0, 0, nil
    local bottom = top + BOX_PAD + rowHeight + FIGURE_FOOT * px
    if hasItems then
        rowWidth, shown, trail = layoutItems(card, model.items, contentX, bottom, rowHeight + ROW_GAP, px, font, config)
        if shown == 0 then
            -- Every line was refused: the card of a proc without amounts.
            model.items = {}
            return fill(api, card, config, model)
        end
    else
        clearItems(card)
    end

    local boxWidth
    if hasItems then boxWidth = contentX + rowWidth + PAD_RIGHT + EDGE
    elseif inside then boxWidth = contentX + captionWidth + PAD_RIGHT + EDGE
    else boxWidth = x end
    local box = card.box
    box.fill:ClearAllPoints()
    box.fill:SetPoint("TOPLEFT", card.frame, "TOPLEFT", 0, -top)
    if trail then
        -- The box ends behind the last figure; the width of a protected amount is never asked for.
        box.fill:SetPoint("BOTTOMRIGHT", trail[1], trail[2], trail[3] + PAD_RIGHT + EDGE, bottom - top - height)
    else
        box.fill:SetSize(boxWidth, height)
    end
    for _, edge in pairs(box.edges) do edge:SetColorTexture(color[1], color[2], color[3], 1) end
    box:SetShown(true)

    card.height = top + height
    card.frame:SetSize(math.max(inside and 0 or captionWidth + EDGE, boxWidth), card.height)
end

local function sameTarget(a, b)
    return a and b and a.plate == b.plate and a.unit == b.unit and a.generation == b.generation and a.guid == b.guid
end

local function detach(card)
    card.frame:Hide()
    card.frame:ClearAllPoints()
    card.attached, card.placedX, card.placedY = nil, nil, nil
end

function Plate.New(api, renderer)
    local view = {}
    local active, pool, offsets = {}, {}, {}
    local lastNow, nextValidation = 0, 0

    local function release(index)
        local card = table.remove(active, index)
        detach(card)
        clearItems(card)
        card.target, card.anchor = nil, nil
        pool[#pool + 1] = card
    end

    local function resolve(target)
        if not target then return end
        local anchor, status = api:ResolveProcAnchor(target)
        if status == "pending" then return nil, true end
        if anchor and (status == "native" or status == "zenial") then return anchor, true end
    end

    local function position(card, anchor, previousBottom, now)
        local age = math.max(0, now - card.started)
        local factor, alpha, dx, dy = NS.Logic.Animation(card.anim, age, card.duration, 1)
        local scale = card.scale * factor
        local opacity = card.anim == "fade" and age < card.duration * .15 and alpha or 1
        local remaining = card.duration - age
        if card.fade > 0 and remaining < card.fade then opacity = opacity * math.max(0, remaining / card.fade) end
        if card.opacity ~= opacity then
            card.frame:SetAlpha(opacity)
            card.opacity = opacity
        end
        if card.drawScale ~= scale then
            card.frame:SetScale(scale)
            card.drawScale = scale
        end
        local centerY, halfHeight = card.y + dy, card.height * scale / 2
        if previousBottom then centerY = math.min(centerY, previousBottom - 4 - halfHeight) end
        local x = (card.x + dx) / scale
        local y = centerY / scale
        if card.attached ~= anchor or card.placedX ~= x or card.placedY ~= y then
            card.frame:ClearAllPoints()
            local ok = pcall(card.frame.SetPoint, card.frame, "LEFT", anchor, card.target and "RIGHT" or "BOTTOM", x, y)
            if not ok then return end
            if not card.attached then card.frame:Show() end
            card.attached, card.placedX, card.placedY = anchor, x, y
        end
        return centerY - halfHeight
    end

    local function arrange(now)
        local index = 1
        while index <= #active do
            local card = active[index]
            local target = card.target
            if not card.anchor then
                if card.attached then detach(card) end
                index = index + 1
            else
                local bottom = position(card, card.anchor, target and offsets[target.plate], now)
                if bottom then
                    if target then offsets[target.plate] = bottom end
                    index = index + 1
                else
                    release(index)
                end
            end
        end
        for plate in pairs(offsets) do offsets[plate] = nil end
    end

    local function expire(now)
        for index = #active, 1, -1 do
            local card = active[index]
            if now - card.started >= card.duration then release(index) end
        end
    end

    local function start(result, family, target, anchor, config, now)
        local model = content(api, result, family, config)
        if not model then return false end
        expire(now)
        local count, replace = 0, nil
        for index, card in ipairs(active) do
            if sameTarget(card.target, target) or (not target and not card.target) then
                count = count + 1
                if not replace and (card.complete or not target) then replace = index end
            end
        end
        if #active >= MAX_ACTIVE or count >= (target and MAX_PER_TARGET or 1) then
            if not replace then return false end
            release(replace)
        end

        local card = table.remove(pool) or createCard(api, renderer)
        if not card then return false end
        card.frame:SetFrameStrata(target and "HIGH" or "TOOLTIP")
        card.frame:SetClampedToScreen(not target)
        fill(api, card, config, model)
        card.target, card.anchor, card.complete = target, anchor, result.complete == true
        card.started, card.duration = now, config.procPlateDuration
        card.anim, card.fade, card.scale = config.procPlateAnim, math.min(config.procPlateFade, card.duration), config.procPlateScale
        card.x, card.y = config.procPlateX, config.procPlateY + (target and 0 or 160)
        if #active == 0 then nextValidation = now + REVALIDATE_INTERVAL end
        active[#active + 1] = card
        lastNow = now
        arrange(now)
        return active[#active] == card
    end

    function view:Present(result, config, now)
        if config.procPlateEnabled ~= true or not finite(now) or type(result) ~= "table" or result.status ~= "confirmed" then
            return false
        end
        local family, ref = families[result.family], result.targetRef
        if not family or config[family.key] ~= true or not ref then return false end
        local anchor, valid = resolve(ref)
        if not valid then
            -- The plate the proc hit is gone (its strike killed the target): the card stands at
            -- the fixed place of a card without a plate.
            return start(result, family, nil, api:Root(), config, now), "screen"
        end
        local target = {unit = ref.unit, plate = ref.plate, guid = ref.guid, generation = ref.generation}
        return start(result, family, target, anchor, config, now), "plate"
    end

    function view:Preview(config, now)
        if not finite(now) or not api:Root() then return false end
        local family = config.procPlateWeapon and families.weapon or config.procPlateTotem and families.totem
            or config.procPlateExtra and families.extra or families.weapon
        local sample = {complete = true, hitCount = 2, hits = {{amount = 291}, {amount = 317}}}
        -- With a working renderer the preview runs the real path: public sample lines in the amount fonts.
        local px = math.floor(config.procPlateSize * AMOUNT_SCALE + .5)
        if renderer and renderer:SelfTest(px) then
            for index, hit in ipairs(sample.hits) do
                sample.hits[index] = {line = "Windfury Attack hits Target for |cffffffff" .. hit.amount .. "|r Physical."}
            end
        end
        return start(sample, family, nil, api:Root(), config, now)
    end

    local function validate(unit, nativePlate)
        for index = #active, 1, -1 do
            local card = active[index]
            local target = card.target
            if target and (not unit or target.unit == unit) and (not nativePlate or target.plate == nativePlate) then
                local anchor, valid = resolve(target)
                if valid then card.anchor = anchor else release(index) end
            end
        end
    end

    function view:Invalidate(unit, nativePlate)
        if #active == 0 then return end
        validate(unit, nativePlate)
        arrange(lastNow)
    end

    function view:Update(now)
        if #active == 0 or not finite(now) then return end
        lastNow = now
        expire(now)
        if now >= nextValidation then
            validate()
            nextValidation = now + REVALIDATE_INTERVAL
        end
        arrange(now)
    end

    function view:Reset()
        for index = #active, 1, -1 do release(index) end
    end

    function view:Count() return #active end
    function view:Busy() return #active > 0 end
    return view
end
