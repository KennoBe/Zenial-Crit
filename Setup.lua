local _, NS = ...
local S, W = {}, NS.ConfigWizard
NS.Setup = S
local tr = W.Text
-- Only these wizard fields are committed; advanced sound/chat rules stay intact.
local fields={"displayMode","scale","nameplateScale","intensity","separatePositions","x","y","critX","critY","killX","killY",
    "critGraphics","critFont","critColor","critTexts","killGraphics","killFont","killColor","killTexts",
    "critSound","healSound","killSound","critSoundMode","critSoundIDs","healSoundMode","healSoundIDs","killSoundMode","killSoundIDs","soundCooldown"}
function S.Initialize(app, fresh)
    if S.wizard then return end
    ZenialCritSetupDB=W.Store(ZenialCritSetupDB,fresh)
    local function capture()
        local result={historyEnabled=app.history.enabled}
        for _,key in ipairs(fields) do result[key]=W.Copy(app.db[key]) end
        return result
    end
    local function sanitize(raw,current)
        raw=type(raw)=="table" and raw or {}
        local input=W.Copy(app.db)
        for _,key in ipairs(fields) do input[key]=raw[key]~=nil and raw[key] or current[key] end
        -- Preserve explicit false values as well as arrays and sound mixes.
        for _,key in ipairs(fields) do if type(raw[key])=="boolean" then input[key]=raw[key] end end
        input=NS.Logic.Sanitize(input)
        local result={}
        for _,key in ipairs(fields) do result[key]=W.Copy(input[key]) end
        if type(raw.historyEnabled)=="boolean" then result.historyEnabled=raw.historyEnabled
        else result.historyEnabled=current.historyEnabled end
        return result
    end
    local function commit(draft)
        local clean=sanitize(draft,capture())
        for _,key in ipairs(fields) do app.db[key]=W.Copy(clean[key]) end
        app:Changed(); app:SetHistoryEnabled(clean.historyEnabled)
    end
    local function finishPosition(v)
        if not v.anchor or not v.anchor:IsShown() then return end
        local x,y=app.api:Position(v.anchor)
        if x and y then
            local xKey=v.anchorKind=="shared" and "x" or v.anchorKind.."X"
            local yKey=v.anchorKind=="shared" and "y" or v.anchorKind.."Y"
            v.draft[xKey]=math.max(-2000,math.min(2000,x)); v.draft[yKey]=math.max(-1200,math.min(1200,y))
            v.store.draft=v.draft
        end
        v.anchor:Hide()
    end
    local function position(v,kind)
        finishPosition(v)
        if not v.anchor then
            local a=CreateFrame("Frame",nil,UIParent,BackdropTemplateMixin and "BackdropTemplate" or nil)
            v.anchor=a; a:SetSize(300,84); a:SetFrameStrata("FULLSCREEN_DIALOG"); a:SetClampedToScreen(true)
            a:SetMovable(true); a:EnableMouse(true); a:RegisterForDrag("LeftButton"); NS.Theme.Panel(a,"parchment")
            v.anchorTitle=v:Label(a,tr("Ziehen zum Verschieben","Drag to move"),10,-12,280,24)
            v.anchorTitle:SetJustifyH("CENTER")
            v.anchorText=v:Label(a,"",10,-44,280,24,"GameFontNormalLarge","gold"); v.anchorText:SetJustifyH("CENTER")
            a:SetScript("OnDragStart",a.StartMoving)
            a:SetScript("OnDragStop",function(frame)
                frame:StopMovingOrSizing(); local x,y=app.api:Position(frame)
                if x and y then
                    local xKey=v.anchorKind=="shared" and "x" or v.anchorKind.."X"
                    local yKey=v.anchorKind=="shared" and "y" or v.anchorKind.."Y"
                    v.draft[xKey]=math.max(-2000,math.min(2000,x)); v.draft[yKey]=math.max(-1200,math.min(1200,y)); v:Changed()
                end
            end)
            a:SetScript("OnMouseUp",function(_,button) if button=="RightButton" then finishPosition(v) end end)
            a:Hide()
        end
        v.anchorKind=kind
        local xKey=kind=="shared" and "x" or kind.."X"
        local yKey=kind=="shared" and "y" or kind.."Y"
        v.anchor:ClearAllPoints(); v.anchor:SetPoint("CENTER",UIParent,"CENTER",v.draft[xKey],v.draft[yKey])
        v.anchorText:SetText(kind=="kill" and "KILL!" or "CRIT!")
        v.anchor:Show(); v:SetMessage(tr("Marker ziehen. Rechtsklick schließt ihn; „Fertig“ übernimmt die Position.","Drag the marker. Right-click closes it; Finish applies the position."))
    end
    local steps={}
    -- Actual content bounds: welcome, positions, size, graphics/texts, sounds, history, summary.
    local heights={90,218,242,262,264,262,264,270,214,264}
    local function step(de,en,descriptionDE,descriptionEN,build)
        steps[#steps+1]={title=tr(de,en),description=tr(descriptionDE,descriptionEN),build=build,height=heights[#steps+1]}
    end
    local function preview(v,p,kind,y)
        local panel=CreateFrame("Frame",nil,p,BackdropTemplateMixin and "BackdropTemplate" or nil)
        panel:SetSize(552,64); panel:SetPoint("TOPLEFT",0,y); NS.Theme.Panel(panel,"inset")
        local text=v:Label(panel,"",12,-12,528,44,"GameFontNormalLarge","gold"); text:SetJustifyH("CENTER")
        v:AddUpdate(function()
            local d=v.draft; text:SetText((d[kind.."Texts"] and d[kind.."Texts"][1]) or (kind=="kill" and "KILL!" or "CRIT!"))
            text:SetTextColor(unpack(d[kind.."Color"]))
            local font,_,flags=app.api:FontStyle(d[kind.."Font"])
            local scale=d.displayMode=="nameplate" and d.nameplateScale or d.scale
            local size=math.min(34,math.max(16,22*scale))
            local ok,applied=pcall(text.SetFont,text,font,size,flags)
            if not ok or applied==false then text:SetFont(app.api:Font(),size,"OUTLINE") end
            text:SetAlpha(d[kind.."Graphics"] and 1 or .35)
        end)
    end
    step("Willkommen bei Zenial Crit","Welcome to Zenial Crit",
        "Gestalte deine Krit- und Kill-Effekte Schritt für Schritt. Du legst fest, wo Texte erscheinen, wie sie aussehen und welche Sounds du hören möchtest. Jede Seite behandelt ein kleines Thema.",
        "Set up crit and kill effects step by step. Choose their position, appearance and sounds. Each page covers one small topic.",function(v,p)
        v:Label(p,tr("Die bisherigen Standardwerte sind bereits ausgewählt.","The existing defaults are already selected."),0,0,552,36)
        v:Label(p,tr("Diesen Assistenten öffnest du später erneut mit /zcrit config.","Open this wizard again with /zcrit config."),0,-54,552,36,"GameFontHighlightSmall","muted")
    end)
    step("Wo sollen die Effekte erscheinen?","Where should effects appear?",
        "Wähle zwischen einer festen Position auf deinem Bildschirm und einem Effekt über der Namensplakette des Ziels. Krit und Kill verwenden denselben Modus. Bei festen Positionen kannst du die Texte hier direkt platzieren.",
        "Choose a fixed screen position or an effect above the target's nameplate. Crit and kill use the same mode. Place fixed effects directly on this page.",function(v,p)
        v:Label(p,tr("Anzeigemodus","Display mode"),0,0,552,24)
        v:Dropdown(p,"displayMode",0,-32,552,{{"nameplate",tr("Über Namensplakette","Above nameplate")},{"fixed",tr("Feste Positionen","Fixed positions")}},nil,nil,function() finishPosition(v) end)
        v:Label(p,tr("Standard: über Namensplakette. Ohne sichtbare Plakette bleibt die Grafik aus; Sounds bleiben aktiv.",
            "Default: above nameplate. Without a visible plate, graphics stay hidden; sounds still play."),0,-78,552,38,"GameFontHighlightSmall","muted")
        local positions=CreateFrame("Frame",nil,p); positions:SetSize(552,80); positions:SetPoint("TOPLEFT",0,-134)
        v:Check(positions,"separatePositions",tr("Getrennte Positionen für Krit und Kill","Separate crit and kill positions"),0,0,function() finishPosition(v) end)
        local shared=v:Button(positions,tr("Gemeinsame Position verschieben","Move shared position"),0,-42,270,function() position(v,"shared") end)
        local crit=v:Button(positions,tr("Krit-Position verschieben","Move crit position"),0,-42,270,function() position(v,"crit") end)
        local kill=v:Button(positions,tr("Kill-Position verschieben","Move kill position"),282,-42,270,function() position(v,"kill") end)
        v:AddUpdate(function()
            positions:SetShown(v.draft.displayMode=="fixed"); shared:SetShown(not v.draft.separatePositions)
            crit:SetShown(v.draft.separatePositions); kill:SetShown(v.draft.separatePositions)
        end)
    end)
    step("Größe und Bewegung","Size and movement",
        "Passe die Größe der Texte und die Stärke ihrer Bewegung an. Die Größe wird für feste Positionen und Namensplaketten getrennt gespeichert; die Bewegung gilt für beide Modi.",
        "Adjust text size and movement strength. Size is stored separately for fixed and nameplate modes; movement applies to both.",function(v,p)
        local function sizeKey() return v.draft.displayMode=="nameplate" and "nameplateScale" or "scale" end
        v:Number(p,"size",tr("Textgröße","Text size"),0,.6,function() return v.draft.displayMode=="nameplate" and 4.2 or 2.5 end,.1,
            function() return v.draft[sizeKey()] end,function(value) v.draft[sizeKey()]=value end," ×")
        v:Number(p,"intensity",tr("Bewegung","Movement"),-92,1,3,1,nil,nil,nil,{tr("Dezent","Subtle"),tr("Normal","Normal"),tr("Kräftig","Strong")})
        preview(v,p,"crit",-178)
    end)
    local fonts={{"standard",tr("Standard","Standard")},{"comic",tr("Comic","Comic")},{"epic",tr("Episch","Epic")},{"heavy",tr("Kräftig","Heavy")}}
    local function graphics(kind,de,en,descriptionDE,descriptionEN)
        step(de,en,descriptionDE,descriptionEN,function(v,p)
            v:Check(p,kind.."Graphics",kind=="crit" and tr("Krit-Grafik anzeigen","Show crit graphic") or tr("Kill-Grafik anzeigen","Show kill graphic"),0,0)
            v:Label(p,kind=="crit"and tr("Effekt- & Schadensschrift","Effect & damage font")or tr("Schriftstil","Font style"),0,-44,552,22)
            v:Dropdown(p,kind.."Font",0,-72,552,fonts)
            v:Label(p,tr("Textfarbe","Text color"),0,-120,552,22)
            v:Color(p,kind.."Color",0,-148,180)
            preview(v,p,kind,-198)
        end)
    end
    local function texts(kind,de,en,descriptionDE,descriptionEN)
        step(de,en,descriptionDE,descriptionEN,function(v,p)
            v:Label(p,kind=="crit" and tr("Zufallstexte für Krits","Random crit texts") or tr("Zufallstexte für Kills","Random kill texts"),0,0,552,24)
            v:Edit(p,kind.."Texts",-32,function() return NS.Logic.JoinTexts(v.draft[kind.."Texts"]) end,
                function(value) v.draft[kind.."Texts"]=NS.Logic.SanitizeTexts(value,kind) end)
            v:Label(p,tr("Bis zu 20 Texte mit jeweils 40 Zeichen. Eine Variante pro Zeile.","Up to 20 texts, 40 characters each. One variant per line."),0,-150,552,28,"GameFontHighlightSmall","muted")
            preview(v,p,kind,-200)
        end)
    end
    graphics("crit","Krit-Texte gestalten","Style crit texts",
        "Ein kritischer Schadenstreffer kann als kurzer Texteffekt erscheinen. Wähle Schriftstil und Farbe. Normale Schadenszahlen folgen dieser Schrift nach dem Ausloggen zur Charakterauswahl und erneutem Einloggen. Die Krit-Aufzeichnung läuft unabhängig davon.",
        "Show critical damage as a short text effect. Choose font and color. Normal damage numbers follow this font after logging out to character selection and back in. Crit recording is independent of these choices.")
    texts("crit","Deine Krit-Texte","Your crit texts",
        "Trage einen Text pro Zeile ein. Für jeden Krit wird zufällig eine der Zeilen ausgewählt. Kurze Ausrufe sind während des Kampfes am besten lesbar.",
        "Enter one text per line. Each crit picks a random line. Short exclamations are easiest to read in combat.")
    graphics("kill","Kill-Texte gestalten","Style kill texts",
        "Feiere einen erkannten eigenen oder Begleiter-Last-Hit mit einem separaten Texteffekt. Grafik, Schriftstil und Farbe sind unabhängig von den Krit-Effekten.",
        "Celebrate a detected last hit by you or your pet with a separate text effect. Graphic, font and color are independent of crit effects.")
    texts("kill","Deine Kill-Texte","Your kill texts",
        "Auch für einen Last-Hit kannst du mehrere kurze Ausrufe hinterlegen. Schreibe eine Variante pro Zeile; das Addon wählt zufällig eine davon.",
        "Add several short exclamations for last hits too. Enter one variant per line; the addon picks one randomly.")
    step("Deine Sounds","Your sounds",
        "Wähle für Krits, kritische Heilungen und Kills jeweils einen Sound oder schalte sie einzeln aus. Mit der Soundpause begrenzt du, wie häufig Klänge direkt hintereinander erklingen.",
        "Choose sounds for crits, critical heals and kills, or disable them separately. The sound pause limits how frequently sounds play in succession.",function(v,p)
        local options={{"__keep",tr("Aktuelle Auswahl beibehalten","Keep current selection")}}
        local known={}
        for _,item in ipairs(NS.Sounds.Catalog(app.db,app.api.env)) do
            options[#options+1]={item.id,NS.Locale.Text(item.name)}; known[item.id]=true
        end
        for i,entry in ipairs({{"crit",tr("Krit","Crit")},{"heal",tr("Heal","Heal")},{"kill",tr("Kill","Kill")}}) do
            local kind,y=entry[1],-(i-1)*48
            v:Check(p,kind.."Sound",entry[2],0,y,nil,62)
            local dropdown=v:Dropdown(p,kind.."SoundChoice",102,y,344,options,function()
                local ids=v.draft[kind.."SoundIDs"]
                return v.draft[kind.."SoundMode"]=="single" and known[ids[1]] and ids[1] or "__keep"
            end,function(id)
                if id~="__keep" then v.draft[kind.."SoundMode"]="single"; v.draft[kind.."SoundIDs"]={id} end
            end)
            local listen=v:Button(p,tr("Anhören","Listen"),458,y,94,function()
                local ids=v.draft[kind.."SoundIDs"]
                local id=#ids>0 and ids[math.random(#ids)] or nil
                local ok,reason=false,tr("Keine Soundauswahl vorhanden.","No sound selected.")
                if id then ok,reason=app:PreviewSoundRef(id,kind) end
                v:SetMessage(ok and tr("Hörprobe abgespielt.","Sound preview played.") or NS.Locale.Text(reason))
            end)
            v:AddUpdate(function() dropdown:SetEnabled(v.draft[kind.."Sound"]); listen:SetEnabled(v.draft[kind.."Sound"]) end)
        end
        v:Label(p,tr("Standard: Krit Klong · Heal Ta-da! · Kill Bruh. Auch Krit- und Kill-Mixe sind auswählbar.",
            "Defaults: crit Klong · heal Ta-da! · kill Bruh. Crit and kill mixes are also available."),0,-154,552,34,"GameFontHighlightSmall","muted")
        v:Number(p,"soundCooldown",tr("Soundpause","Sound pause"),-202,0,30,.05,nil,nil,tr(" Sekunden"," seconds"))
    end)
    step("Krits und Heilungen aufzeichnen","Record crits and heals",
        "Speichere die 100 höchsten und 100 letzten beobachteten Schadenskrits und kritischen Heilungen pro Charakter. In der History siehst du Werte, Ziel, Zeitpunkt und Gebiet.",
        "Save the 100 highest and 100 most recent observed critical damage and heals per character. History shows amount, target, time and location.",function(v,p)
        v:Check(p,"historyEnabled",tr("History-Aufzeichnung aktivieren","Enable history recording"),0,0)
        v:Label(p,tr("Standard: aktiviert. Grafik und Sounds beeinflussen die Aufzeichnung nicht.","Default: enabled. Graphics and sounds do not affect recording."),0,-40,552,40,"GameFontHighlightSmall","muted")
        v:Label(p,tr("Hinweis zu beobachteten Treffern","About observed hits"),0,-110,552,24)
        v:Label(p,tr("Bei Ziel-Krits und Ziel-Heals kann der Client nicht unterscheiden, von welchem Spieler sie stammen.",
            "For target crits and heals the client cannot identify the player who caused them."),0,-150,552,64,"GameFontHighlightSmall","muted")
    end)
    step("Zenial Crit ist bereit","Zenial Crit is ready",
        "Deine Grundauswahl ist getroffen. Mit „Fertig“ speicherst du sie. Weitere Optionen, eigene Audiodateien und deine History findest du jederzeit im normalen Addon-Fenster.",
        "Your basic setup is ready. Finish saves your choices. Additional options, custom audio and history are always available in the addon window.",function(v,p)
        local summary=v:Label(p,"",0,0,552,168)
        v:AddUpdate(function()
            local d=v.draft; local function on(value) return value and tr("An","On") or tr("Aus","Off") end
            summary:SetText(table.concat({tr("Anzeigemodus: ","Display mode: ")..(d.displayMode=="fixed" and tr("Feste Positionen","Fixed positions") or tr("Über Namensplakette","Above nameplate")),
                tr("Grafik für Krit / Kill: ","Crit / kill graphics: ")..on(d.critGraphics).." / "..on(d.killGraphics),
                tr("Sounds für Krit / Heal / Kill: ","Crit / heal / kill sounds: ")..on(d.critSound).." / "..on(d.healSound).." / "..on(d.killSound),
                tr("History: ","History: ")..on(d.historyEnabled)},"\n\n"))
        end)
        v.settingsHint=v:Label(p,tr("Alle Einstellungen öffnest du mit /zcrit settings. Dort findest du weitere Optionen, die du in Ruhe prüfen kannst. Den Assistenten startest du erneut mit /zcrit config.",
            "Open all settings with /zcrit settings. Review additional options there at your own pace. Restart the wizard with /zcrit config."),0,-174,552,90,"GameFontHighlight","gold")
    end)
    S.wizard=W.New({title="ZENIAL CRIT",steps=steps,store=ZenialCritSetupDB,capture=capture,sanitize=sanitize,apply=commit,
        closeTransient=finishPosition,beforeShow=function()
            for _,view in ipairs(app.views) do if not view.embedded then view.frame:Hide() end end
        end,busy=function()
            for _,view in ipairs(app.views) do if view.frame:IsVisible() then return true end end
            local community=_G.ZenialCommunity
            return community and community.UI and community.UI.frame and community.UI.frame:IsShown()
        end})
end
function S.Open() if S.wizard then return S.wizard:Open(false) end end
function S.Schedule() if S.wizard then S.wizard:Schedule() end end
