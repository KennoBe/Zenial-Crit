local _, NS = ...
local Effects = {}
NS.Effects = Effects

local MULTIPLY = "\195\151" -- UTF-8 multiplication sign
local FLASH_TIME = .3
local ranks = {streak = 4, proc = 3, kill = 2, crit = 1, heal = 1}

function Effects.New(api)
    local E = {
        api = api, pool = {}, active = {},
        graphicsPaused = {crit = false, heal = false, kill = false, streak = false, proc = false},
        failedSounds = {}, lastSound = {},
        lastAudioAt = -math.huge, lastAudioCategory = nil, lastAudioPriority = 0,
        lastGraphicAt = nil, flash = nil, flashFailed = false,
    }
    local gradientCache, gradientCount = {}, 0

    function E:Count() return #self.active end

    function E:Busy() return #self.active > 0 or self.flash ~= nil end

    function E:HideFlash()
        self.flash = nil
        if self.flashFrame then pcall(self.flashFrame.Hide, self.flashFrame) end
    end

    function E:Clear()
        for _, effect in ipairs(self.active) do
            if effect.frame then pcall(effect.frame.Hide, effect.frame) end
        end
        self.active = {}
        self:HideFlash()
        api:StopAudio()
    end

    function E:ResetFailures()
        self.failedSounds = {}
        self.graphicsPaused = {crit = false, heal = false, kill = false, streak = false, proc = false}
    end

    function E:RetrySound(id)
        if id then self.failedSounds[id] = nil else self.failedSounds = {} end
    end

    local function limitOf(config)
        local value = config.maxEffects
        if type(value) ~= "number" or value ~= value then value = 3 end
        return math.max(1, math.min(6, math.floor(value)))
    end

    function E:FreeFrame(limit)
        for _, frame in ipairs(self.pool) do if not frame:IsShown() then return frame end end
        if #self.pool >= limit then return nil end
        local frame = api:Frame()
        if not frame then return nil end
        self.pool[#self.pool + 1] = frame
        frame:Hide()
        frame:SetSize(430, 130)
        frame:SetFrameStrata("HIGH")
        frame:EnableMouse(false)
        frame.text = frame:CreateFontString(nil, "OVERLAY")
        frame.text:SetFont(api:Font(), 55, "OUTLINE")
        frame.text:SetPoint("CENTER")
        frame.text:SetShadowOffset(3, -3)
        frame:Hide()
        return frame
    end

    -- Gradient text is cached by text and colors; the cache is dropped at 64 entries.
    local function displayText(config, kind, text)
        if config[kind .. "Gradient"] ~= true then return text, false end
        local r1, g1, b1 = NS.Logic.Color(config, kind)
        local r2, g2, b2 = NS.Logic.Color2(config, kind)
        local key = string.format("%s\0%.3f\0%.3f\0%.3f\0%.3f\0%.3f\0%.3f", text, r1, g1, b1, r2, g2, b2)
        local cached = gradientCache[key]
        if not cached then
            if gradientCount >= 64 then gradientCache, gradientCount = {}, 0 end
            cached = NS.Logic.GradientText(text, r1, g1, b1, r2, g2, b2)
            gradientCache[key], gradientCount = cached, gradientCount + 1
        end
        return cached, true
    end

    function E:Draw(kind, config, anchor, text, size, limit)
        local frame = self:FreeFrame(limit or limitOf(config))
        if not frame then return nil end
        local font, fontSize, fontFlags = api:FontStyle(NS.Logic.FontStyle(config, kind))
        local ok, applied = pcall(frame.text.SetFont, frame.text, font, fontSize, fontFlags)
        if not ok or applied == false then
            pcall(frame.text.SetFont, frame.text, api:Font(), 55, "OUTLINE")
        end
        local shown, gradient = displayText(config, kind, text)
        if gradient then frame.text:SetTextColor(1, 1, 1, 1)
        else frame.text:SetTextColor(NS.Logic.Color(config, kind)) end
        frame.text:SetText(shown)
        frame:SetScale(size)
        frame:SetAlpha(1)
        frame:ClearAllPoints()
        if anchor then
            frame:SetPoint("CENTER", anchor.plate, "TOP", 0, 45 / size)
        else
            local x, y = NS.Logic.Position(config, kind)
            frame:SetPoint("CENTER", api:Root(), "CENTER", x / size, y / size)
        end
        frame:Show()
        return frame
    end

    local priorities = {crit = 1, heal = 1, low = 1, healLow = 1, record = 2, healRecord = 2, kill = 3, streak = 4, proc = 2,
        windfury = 2}

    function E:PlayCategory(category, config, now, preview, retryID, tier)
        if not priorities[category] then return false, "No sound category selected." end
        local enabled = category == "kill" and config.killSound
            or category == "crit" and config.critSound
            or category == "heal" and config.healSound
            or category == "streak" and config.streakSound
            or category == "proc" and config.procSound
            or category == "windfury" and config.procSound
            or category == "record" and config.recordSoundEnabled
            or category == "healRecord" and config.healRecordSoundEnabled
            or category == "low" and config.lowCritEnabled
            or category == "healLow" and config.healLowEnabled
        if not enabled and not preview then return false, "Sound is disabled." end
        if retryID then self:RetrySound(retryID) end
        if preview then
            local keys = NS.Sounds.CategoryKeys[category]
            for _, id in ipairs(keys and config[keys.ids] or {}) do self:RetrySound(id) end
        end
        local priority = priorities[category]
        local elapsed = now - self.lastAudioAt
        local cooldown = type(config.soundCooldown) == "number" and config.soundCooldown or .25
        if not preview and elapsed < cooldown and priority <= self.lastAudioPriority then
            return false, "Sound pause is still active."
        end
        local candidates = NS.Sounds.Candidates(
            config, category, api.env, math.random, self.lastSound[category], self.failedSounds, tier
        )
        if #candidates == 0 then return false, "No available sound selected." end
        api:StopAudio()
        for i = 1, #candidates do
            local candidate = candidates[i]
            if api:PlayPath(candidate.path, NS.Logic.SoundChannel(config, category)) then
                self.lastSound[category] = candidate.id
                if not preview then
                    self.lastAudioAt, self.lastAudioCategory, self.lastAudioPriority = now, category, priority
                end
                return true
            end
            self.failedSounds[candidate.id] = true
        end
        return false, "File could not be played. Check path and WoW restart."
    end

    function E:Evict(index)
        local effect = table.remove(self.active, index)
        if effect and effect.frame then pcall(effect.frame.Hide, effect.frame) end
    end

    -- Screen flash: one reused full-screen texture, linear fade in FLASH_TIME seconds.
    function E:StartFlash(config, kind, now)
        if self.flashFailed then return false end
        if not self.flashFrame then
            local ok, frame, texture = pcall(function()
                local created = api:Frame()
                if not created then error("no frame") end
                created:SetAllPoints(api:Root())
                created:SetFrameStrata("BACKGROUND")
                created:EnableMouse(false)
                local layer = created:CreateTexture(nil, "BACKGROUND")
                layer:SetAllPoints(created)
                created:Hide()
                return created, layer
            end)
            if not ok or not frame then self.flashFailed = true; return false end
            self.flashFrame, self.flashTexture = frame, texture
        end
        local peak = .06 + (type(config.intensity) == "number" and config.intensity or 2) * .08
        local r, g, b = NS.Logic.Color(config, kind)
        local ok = pcall(function()
            self.flashTexture:SetColorTexture(r, g, b, peak)
            self.flashFrame:SetAlpha(1)
            self.flashFrame:Show()
        end)
        if not ok then self.flashFailed = true; self:HideFlash(); return false end
        self.flash = {started = now, peak = peak, r = r, g = g, b = b}
        return true
    end

    -- Opens (or merges into) the text for one event. Returns true when a text is shown.
    function E:Place(kind, config, now, preview, anchor, opts)
        local L = NS.Logic
        local x, y = L.Position(config, kind)
        local key = anchor and anchor.plate or (x .. ":" .. y)
        local rank = ranks[kind] or 1
        local pair = kind == "crit" or kind == "heal"
        if config.combine == true and pair then
            for index = #self.active, 1, -1 do
                local effect = self.active[index]
                if effect.kind == kind and effect.key == key and effect.frame then
                    effect.count = (effect.count or 1) + 1
                    effect.started = now
                    local shown = displayText(config, kind, effect.baseText .. " " .. MULTIPLY .. effect.count)
                    effect.frame.text:SetText(shown)
                    if not preview then self.lastGraphicAt = now end
                    return true
                end
            end
        end
        local gap = config.critGap
        if pair and not preview and type(gap) == "number" and gap > 0 and self.lastGraphicAt
            and now - self.lastGraphicAt < gap then return false end
        local limit = limitOf(config)
        while #self.active >= limit do
            local victim
            for index = 1, #self.active do
                local effect = self.active[index]
                if (preview or effect.rank < rank) and (not victim or effect.started < self.active[victim].started) then
                    victim = index
                end
            end
            if not victim then return false end
            self:Evict(victim)
        end
        local slot, taken = 0, true
        while taken do
            taken = false
            for index = 1, #self.active do
                local effect = self.active[index]
                if effect.frame and effect.key == key and effect.slot == slot then taken = true; break end
            end
            if taken then slot = slot + 1 end
        end
        local tier = type(opts.tier) == "number" and opts.tier or 1
        local base = L.EffectScale(config, anchor ~= nil)
        local size = base * (config[kind .. "Size"] or 1)
        if kind == "streak" and config.streakEscalate == true then
            size = size * (1 + math.min(.6, .12 * (tier - 1)))
        end
        local text = opts.text or L.PickText(config, kind)
        local frame = self:Draw(kind, config, anchor, text, size, limit)
        api:Diagnostic("draw_result", kind, frame ~= nil)
        if not frame then return false end
        self.active[#self.active + 1] = {
            frame = frame, kind = kind, rank = rank, key = key, slot = slot, started = now, scale = size,
            intensity = config.intensity, anim = config[kind .. "Anim"], duration = config[kind .. "Duration"],
            -- Spacing is given for size 1 and follows the overall size, so lines keep their distance.
            alpha = config[kind .. "Alpha"] or 1, offset = slot * (config.stackSpacing or 0) * base,
            x = x, y = y, anchor = anchor, baseText = text, count = 1,
        }
        if not preview and pair then self.lastGraphicAt = now end
        return true
    end

    function E:Show(kind, soundCategory, config, now, preview, anchor, opts)
        opts = opts or {}
        local graphics = false
        if not opts.noGraphic then graphics = preview or (NS.Logic.Output(config, kind)) == true end
        if graphics and config.displayMode == "nameplate" and not anchor and not opts.fixed
            and (kind == "crit" or kind == "kill") then graphics = false end
        local shown = false
        if graphics and (preview or not self.graphicsPaused[kind]) then
            local ok, result = pcall(self.Place, self, kind, config, now, preview == true, anchor, opts)
            api:Diagnostic("draw_result", kind, ok, ok and result or false, not ok and result or nil)
            self.graphicsPaused[kind] = not ok
            shown = ok and result == true
        end
        if shown and (config[kind .. "Flash"] == true or opts.flash == true) then self:StartFlash(config, kind, now) end
        local played, reason = false, nil
        if soundCategory then played, reason = self:PlayCategory(soundCategory, config, now, preview, nil, opts.tier) end
        return shown, played, reason
    end

    -- Static per-frame step (no closure per effect and frame). Identity checks
    -- run on every frame so a reused plate stops the effect immediately.
    local function step(effect, scale, alpha, dx, dy)
        if effect.anchor then
            local followed, valid = pcall(api.FollowNameplate, api, effect.anchor)
            if not followed or not valid then
                api:Diagnostic("anchor_invalidated", "removed/reused/inaccessible")
                effect.frame:Hide(); effect.frame = nil
                return
            end
        end
        local size = effect.scale * scale
        effect.frame:SetScale(size)
        effect.frame:SetAlpha(alpha * effect.alpha)
        effect.frame:ClearAllPoints()
        if effect.anchor then
            effect.frame:SetPoint("CENTER", effect.anchor.plate, "TOP", dx / size, (45 + dy + effect.offset) / size)
        else
            effect.frame:SetPoint("CENTER", api:Root(), "CENTER", (effect.x + dx) / size, (effect.y + dy + effect.offset) / size)
        end
    end

    function E:Update(now)
        for index = #self.active, 1, -1 do
            local effect = self.active[index]
            local scale, alpha, dx, dy, done = NS.Logic.Animation(effect.anim, now - effect.started, effect.duration, effect.intensity)
            if done then
                if effect.frame then pcall(effect.frame.Hide, effect.frame) end
                table.remove(self.active, index)
            elseif effect.frame then
                local ok, errorText = pcall(step, effect, scale, alpha, dx, dy)
                if not ok then
                    api:Diagnostic("animation_error", errorText)
                    pcall(effect.frame.Hide, effect.frame)
                    effect.frame = nil
                end
                -- An effect without a frame is invisible: it frees its place at once.
                if not effect.frame then table.remove(self.active, index) end
            end
        end
        local flash = self.flash
        if flash then
            local progress = (now - flash.started) / FLASH_TIME
            if progress >= 1 or progress < 0 then
                self:HideFlash()
            else
                local ok = pcall(self.flashTexture.SetColorTexture, self.flashTexture, flash.r, flash.g, flash.b, flash.peak * (1 - progress))
                if not ok then self.flashFailed = true; self:HideFlash() end
            end
        end
    end

    return E
end
