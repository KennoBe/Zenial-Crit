local _, NS = ...
local Effects = {}
NS.Effects = Effects

function Effects.New(api)
    local E = {
        api = api, pool = {}, active = {},
        graphicsPaused = {crit = false, kill = false},
        failedSounds = {}, lastSound = {},
        lastAudioAt = -math.huge, lastAudioCategory = nil, lastAudioPriority = 0,
    }

    function E:Count() return #self.active end

    function E:Clear()
        for _, effect in ipairs(self.active) do
            if effect.frame then pcall(effect.frame.Hide, effect.frame) end
        end
        self.active = {}
        api:StopAudio()
    end

    function E:ResetFailures()
        self.failedSounds = {}
        self.graphicsPaused = {crit = false, kill = false}
    end

    function E:RetrySound(id)
        if id then self.failedSounds[id] = nil else self.failedSounds = {} end
    end

    function E:FreeFrame()
        for _, frame in ipairs(self.pool) do if not frame:IsShown() then return frame end end
        if #self.pool >= 3 then return nil end
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

    function E:Draw(kind, config, anchor)
        local frame = self:FreeFrame()
        if not frame then return nil end
        local font, fontSize, fontFlags = api:FontStyle(NS.Logic.FontStyle(config, kind))
        local ok, applied = pcall(frame.text.SetFont, frame.text, font, fontSize, fontFlags)
        if not ok or applied == false then
            pcall(frame.text.SetFont, frame.text, api:Font(), 55, "OUTLINE")
        end
        frame.text:SetTextColor(NS.Logic.Color(config, kind))
        frame.text:SetText(NS.Logic.PickText(config, kind))
        local size = NS.Logic.EffectScale(config)
        frame:SetScale(size)
        frame:SetAlpha(1)
        frame:ClearAllPoints()
        local x, y = NS.Logic.Position(config, kind)
        if anchor then
            frame:SetPoint("CENTER", anchor.plate, "TOP", 0, 45 / size)
        else frame:SetPoint("CENTER", api:Root(), "CENTER", x / size, y / size) end
        frame:Show()
        return frame
    end

    local priorities = {crit = 1, heal = 1, low = 1, healLow = 1, record = 2, healRecord = 2, kill = 3}

    function E:PlayCategory(category, config, now, preview, retryID)
        if not priorities[category] then return false, "No sound category selected." end
        local enabled = category == "kill" and config.killSound
            or category == "crit" and config.critSound
            or category == "heal" and config.healSound
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
            config, category, api.env, math.random, self.lastSound[category], self.failedSounds
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

    function E:Show(kind, soundCategory, config, now, preview, anchor)
        local graphics = preview or (kind == "crit" and config.critGraphics or kind == "kill" and config.killGraphics)
        if config.displayMode == "nameplate" and not anchor then graphics = false end
        local frame
        if graphics and #self.active >= 3 and kind == "kill" then
            local oldest = table.remove(self.active, 1)
            if oldest and oldest.frame then pcall(oldest.frame.Hide, oldest.frame) end
        end
        if graphics and #self.active < 3 and (preview or not self.graphicsPaused[kind]) then
            local ok, result = pcall(self.Draw, self, kind, config, anchor)
            api:Diagnostic("draw_result", kind, ok, ok and result ~= nil or false, not ok and result or nil)
            self.graphicsPaused[kind] = not ok
            if ok then frame = result end
        end
        if frame then
            local x, y = NS.Logic.Position(config, kind)
            self.active[#self.active + 1] = {
                frame = frame, started = now, scale = NS.Logic.EffectScale(config),
                intensity = config.intensity, x = x, y = y, anchor = anchor,
            }
        end
        local played, reason = false, nil
        if soundCategory then played, reason = self:PlayCategory(soundCategory, config, now, preview) end
        return frame ~= nil, played, reason
    end

    -- Static per-frame step (no closure per effect and frame). Identity checks
    -- run on every frame so a reused plate stops the effect immediately.
    local function step(effect, scale, alpha, rise)
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
        effect.frame:SetAlpha(alpha)
        effect.frame:ClearAllPoints()
        if effect.anchor then
            effect.frame:SetPoint("CENTER", effect.anchor.plate, "TOP", 0, (45 + rise) / size)
        else
            effect.frame:SetPoint("CENTER", api:Root(), "CENTER", effect.x / size, (effect.y + rise) / size)
        end
    end

    function E:Update(now)
        for index = #self.active, 1, -1 do
            local effect = self.active[index]
            local scale, alpha, rise, done = NS.Logic.Animation(now - effect.started, effect.intensity)
            if done then
                if effect.frame then pcall(effect.frame.Hide, effect.frame) end
                table.remove(self.active, index)
            elseif effect.frame then
                local ok, errorText = pcall(step, effect, scale, alpha, rise)
                if not ok then
                    api:Diagnostic("animation_error", errorText)
                    pcall(effect.frame.Hide, effect.frame)
                    effect.frame = nil
                end
            end
        end
    end

    return E
end
