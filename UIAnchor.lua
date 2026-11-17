local _, NS = ...
local T, K, I = NS.Theme, NS.Kit, NS.Locale
local function tr(value) return I.Text(value) end
-- Draggable position marker for the fixed text positions (shared, crit, heal, kill, streak, proc).
-- Saving always goes through app:Changed(); the profile root in ZenialCritDB is never replaced here.
local Anchor = {}
NS.UIAnchor = Anchor

local KINDS = {shared = "Shared position", crit = "Crit", heal = "Heal crit", kill = "Kill", streak = "Kill streak", proc = "Proc"}
Anchor.Kinds = KINDS

function Anchor.Define(view)
    local app, api = view.app, view.api

    local function currentPosition(kind)
        if kind == "shared" then return app.db.x, app.db.y end
        return NS.Logic.Position(app.db, kind)
    end

    local function store(kind, x, y)
        if kind == "shared" then app.db.x, app.db.y = x, y
        else app.db[kind .. "X"], app.db[kind .. "Y"] = x, y end
    end

    function view:AnchorTitle()
        return string.format(tr("Drag to move: %s"), tr(KINDS[self.anchorKind] or KINDS.shared))
    end

    -- Without separate positions every event shares one position, so the marker always moves that one.
    function view:Anchor(kind)
        if not app.db then return end
        if not KINDS[kind] or app.db.separatePositions ~= true then kind = "shared" end
        if self.anchor and self.anchor:IsShown() and self.anchorKind == kind then self.anchor:Hide(); return end
        if not self.anchor then
            local marker = api:Frame("Frame", nil, api:Root(), BackdropTemplateMixin and "BackdropTemplate" or nil)
            if not marker then return end
            self.anchor = marker
            marker:SetSize(250, 72); marker:SetClampedToScreen(true); marker:SetFrameStrata("TOOLTIP"); marker:SetMovable(true)
            marker:EnableMouse(true); marker:RegisterForDrag("LeftButton")
            if T then T.Panel(marker, "raised") end
            self.anchorTitle = K.Text(marker, "", "heading", "gold")
            self.anchorTitle:SetPoint("TOPLEFT", 16, -28); self.anchorTitle:SetWidth(220)
            self.anchorTitle:SetJustifyH("CENTER")
            marker:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
            marker:SetScript("OnDragStop", function(frame)
                frame:StopMovingOrSizing()
                local x, y = api:Position(frame)
                if x then store(view.anchorKind, x, y); app:Changed() end
            end)
            marker:SetScript("OnMouseUp", function(frame, mouse) if mouse == "RightButton" then frame:Hide() end end)
        end
        self.anchorKind = kind
        self.anchor:Show()
        self:RefreshAnchor()
    end

    function view:RefreshAnchor()
        if not (self.anchor and self.anchor:IsShown() and app.db) then return end
        local x, y = currentPosition(self.anchorKind)
        self.anchor:ClearAllPoints(); self.anchor:SetPoint("CENTER", api:Root(), "CENTER", x, y)
        self.anchorTitle:SetText(self:AnchorTitle())
    end

    function view:CloseAnchor()
        if NS.Form and NS.Form.ClosePopups then NS.Form.ClosePopups() end
        if self.anchor and self.anchor:IsShown() then self.anchor:Hide() end
    end
end
