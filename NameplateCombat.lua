local _, NS = ...
local Plate = {}
NS.NameplateCombat = Plate

local T, K, tr = NS.Theme, NS.Kit, NS.Locale.Text
local MAX_ACTIVE, MAX_PER_TARGET, MAX_HITS = 40, 4, 3
local REVALIDATE_INTERVAL = .1
local families = {
    weapon = {key = "procPlateWeapon", name = "Windfury", icon = "star"},
    totem = {key = "procPlateTotem", name = "Windfury Totem", icon = "activities"},
    extra = {key = "procPlateExtra", name = "Extra Attack", icon = "pvp"},
}

local function finite(value)
    return type(value) == "number" and value == value and value < math.huge and value > -math.huge
end

local function content(api, result, family, config)
    local hits = type(result.hits) == "table" and result.hits or {}
    local count = result.hitCount
    if not api:Public(count) or not finite(count) or count < 1 or count % 1 ~= 0 then count = 0 end
    local complete = result.complete == true
    local title = ""
    if config.procPlateName then
        local spellName = family == families.extra and api:SpellName(result.spellID)
        title = spellName or tr(family.name)
    end
    if config.procPlateGroup and complete and count > 1 then
        title = (title ~= "" and title .. " " or "") .. "×" .. count
    end
    local rows, total, allPublic = {}, 0, complete and count >= 2 and #hits == count
    if config.procPlateAmounts or config.procPlateSum then
        for _, hit in ipairs(hits) do
            local amount = hit.amount
            if api:Public(amount) and finite(amount) then
                if allPublic then total = total + amount end
                if config.procPlateAmounts and #rows < MAX_HITS then
                    local critical = config.procPlateHighlight and api:Public(hit.critical) and hit.critical == true
                    rows[#rows + 1] = {text = tostring(amount) .. (critical and "!" or ""), critical = critical}
                end
            else
                allPublic = false
            end
        end
    end
    local sum = config.procPlateSum and allPublic and finite(total) and string.format(tr("Total %s"), tostring(total)) or ""
    local icon = config.procPlateIcon and family.icon or nil
    if not icon and title == "" and sum == "" and #rows == 0 then return end
    return title, rows, sum, icon
end

local function createCard(api)
    local root = api:Root()
    if not root then return end
    local frame = K.Card(root, "raised")
    frame:EnableMouse(false)
    frame:Hide()
    local card = {
        frame = frame, icon = K.Icon(frame, "star", 16, "gold"),
        title = K.Text(frame, "", "heading"), total = K.Text(frame, "", "caption"), hits = {},
    }
    for index = 1, MAX_HITS do card.hits[index] = K.Text(frame, "", "body") end
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

local function fill(api, card, config, title, rows, sum, icon)
    local pad, gap = 5, 5
    local font, size, color = api:Font(), config.procPlateSize, config.procPlateColor
    local width, y = 0, pad
    card.icon:SetShown(icon ~= nil)
    if icon then
        local iconSize = size + 3
        T.SetIcon(card.icon, icon, "gold")
        card.icon:SetSize(iconSize, iconSize)
        card.icon:ClearAllPoints()
        card.icon:SetPoint("TOPLEFT", card.frame, "TOPLEFT", pad, -pad)
        width = iconSize
    end
    local titleX = pad + (icon and width + gap or 0)
    local titleWidth = putText(card, card.title, title, size, titleX, y + (icon and 1 or 0), font)
    card.title:SetTextColor(color[1], color[2], color[3])
    if titleWidth > 0 then width = titleX - pad + titleWidth end
    if width > 0 then y = y + size + 4 end

    local row, x = config.procPlateLayout == "row", pad
    for index, label in ipairs(card.hits) do
        local hit = rows[index]
        local hitWidth = putText(card, label, hit and hit.text or "", size - 1, x, y, font)
        if hitWidth > 0 then
            T.Tint(label, "SetTextColor", hit.critical and "goldBright" or "text")
            width = math.max(width, x - pad + hitWidth)
            if row then x = x + hitWidth + gap else y = y + size + 2 end
        end
    end
    if row and #rows > 0 then y = y + size + 2 end
    local totalWidth = putText(card, card.total, sum, size - 1, pad, y, font)
    if totalWidth > 0 then y = y + size + 2 end
    card.height = y + pad
    card.frame:SetSize(math.max(width, totalWidth) + 2 * pad, card.height)
end

local function sameTarget(a, b)
    return a and b and a.plate == b.plate and a.unit == b.unit and a.generation == b.generation and a.guid == b.guid
end

local function detach(card)
    card.frame:Hide()
    card.frame:ClearAllPoints()
    card.attached, card.placedX, card.placedY = nil, nil, nil
end

function Plate.New(api)
    local view = {}
    local active, pool, offsets = {}, {}, {}
    local lastNow, nextValidation = 0, 0

    local function release(index)
        local card = table.remove(active, index)
        detach(card)
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
        local title, rows, sum, icon = content(api, result, family, config)
        if not title then return false end
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

        local card = table.remove(pool) or createCard(api)
        if not card then return false end
        card.frame:SetFrameStrata(target and "HIGH" or "TOOLTIP")
        card.frame:SetClampedToScreen(not target)
        fill(api, card, config, title, rows, sum, icon)
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
        if not valid then return false end
        local target = {unit = ref.unit, plate = ref.plate, guid = ref.guid, generation = ref.generation}
        return start(result, family, target, anchor, config, now)
    end

    function view:Preview(config, now)
        if not finite(now) or not api:Root() then return false end
        local family = config.procPlateWeapon and families.weapon or config.procPlateTotem and families.totem
            or config.procPlateExtra and families.extra or families.weapon
        local sample = {complete = true, hitCount = 2, hits = {{amount = 412}, {amount = 638, critical = true}}}
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
