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
    local defaults=NS.Logic.Defaults()
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
            local K=NS.Kit
            local a=CreateFrame("Frame",nil,UIParent,BackdropTemplateMixin and "BackdropTemplate" or nil)
            v.anchor=a; a:SetSize(300,84); a:SetFrameStrata("FULLSCREEN_DIALOG"); a:SetClampedToScreen(true)
            a:SetMovable(true); a:EnableMouse(true); a:RegisterForDrag("LeftButton"); NS.Theme.Panel(a,"parchment")
            v.anchorTitle=K.Text(a,tr("Ziehen zum Verschieben","Drag to move"),"body")
            v.anchorTitle:SetPoint("TOPLEFT",10,-12); v.anchorTitle:SetSize(280,24); v.anchorTitle:SetJustifyH("CENTER")
            v.anchorText=K.Text(a,"","title","gold")
            v.anchorText:SetPoint("TOPLEFT",10,-44); v.anchorText:SetSize(280,24); v.anchorText:SetJustifyH("CENTER")
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
    local function step(de,en,descriptionDE,descriptionEN,build)
        steps[#steps+1]={title=tr(de,en),description=tr(descriptionDE,descriptionEN),build=build}
    end
    local function note(form,de,en) form:Note({text=tr(de,en)}) end
    local function toggle(form,key,label,extra)
        local spec={key=key,label=label}
        for k,value in pairs(extra or {}) do spec[k]=value end
        return form:Toggle(spec)
    end
    -- The sample text of an effect in the draft's font, colour and size.
    local function preview(form,v,kind)
        local text
        form:Custom({height=72,
            build=function(frame)
                local panel=CreateFrame("Frame",nil,frame,BackdropTemplateMixin and "BackdropTemplate" or nil)
                panel:SetPoint("TOPLEFT",frame,"TOPLEFT",0,-4); panel:SetPoint("TOPRIGHT",frame,"TOPRIGHT",0,-4); panel:SetHeight(64)
                NS.Theme.Panel(panel,"inset")
                text=NS.Kit.Text(panel,"","title","gold")
                text:SetPoint("LEFT",panel,"LEFT",12,0); text:SetPoint("RIGHT",panel,"RIGHT",-12,0); text:SetJustifyH("CENTER")
            end,
            refresh=function()
                local d=v.draft
                text:SetText((d[kind.."Texts"] and d[kind.."Texts"][1]) or (kind=="kill" and "KILL!" or "CRIT!"))
                text:SetTextColor(unpack(d[kind.."Color"]))
                local font,_,flags=app.api:FontStyle(d[kind.."Font"])
                local scale=d.displayMode=="nameplate" and d.nameplateScale or d.scale
                local size=math.min(34,math.max(16,22*scale))
                local ok,applied=pcall(text.SetFont,text,font,size,flags)
                if not ok or applied==false then text:SetFont(app.api:Font(),size,"OUTLINE") end
                text:SetAlpha(d[kind.."Graphics"] and 1 or .35)
            end})
    end
    step("Willkommen bei Zenial Crit","Welcome to Zenial Crit",
        "Gestalte deine Krit- und Kill-Effekte Schritt für Schritt. Du legst fest, wo Texte erscheinen, wie sie aussehen und welche Sounds du hören möchtest. Jede Seite behandelt ein kleines Thema.",
        "Set up crit and kill effects step by step. Choose their position, appearance and sounds. Each page covers one small topic.",function(form)
        note(form,"Die bisherigen Standardwerte sind bereits ausgewählt.","The existing defaults are already selected.")
        note(form,"Diesen Assistenten öffnest du später erneut mit /zcrit config.","Open this wizard again with /zcrit config.")
    end)
    step("Wo sollen die Effekte erscheinen?","Where should effects appear?",
        "Wähle zwischen einer festen Position auf deinem Bildschirm und einem Effekt über der Namensplakette des Ziels. Krit und Kill verwenden denselben Modus. Bei festen Positionen kannst du die Texte hier direkt platzieren.",
        "Choose a fixed screen position or an effect above the target's nameplate. Crit and kill use the same mode. Place fixed effects directly on this page.",function(form,v)
        local function fixed() return v.draft.displayMode=="fixed" end
        form:Select({key="displayMode",label=tr("Anzeigemodus","Display mode"),onChange=function() finishPosition(v) end,options={
            {"nameplate",tr("Über Namensplakette","Above nameplate")},{"fixed",tr("Feste Positionen","Fixed positions")}}})
        note(form,"Standard: über Namensplakette. Ohne sichtbare Plakette bleibt die Grafik aus; Sounds bleiben aktiv.",
            "Default: above nameplate. Without a visible plate, graphics stay hidden; sounds still play.")
        toggle(form,"separatePositions",tr("Getrennte Positionen für Krit und Kill","Separate crit and kill positions"),
            {visible=fixed,onChange=function() finishPosition(v) end})
        form:Buttons({anchor="positions",
            {text=tr("Gemeinsame Position verschieben","Move shared position"),visible=function() return fixed() and not v.draft.separatePositions end,
                onClick=function() position(v,"shared") end},
            {text=tr("Krit-Position verschieben","Move crit position"),visible=function() return fixed() and v.draft.separatePositions end,
                onClick=function() position(v,"crit") end},
            {text=tr("Kill-Position verschieben","Move kill position"),visible=function() return fixed() and v.draft.separatePositions end,
                onClick=function() position(v,"kill") end}})
    end)
    step("Größe und Bewegung","Size and movement",
        "Passe die Größe der Texte und die Stärke ihrer Bewegung an. Die Größe wird für feste Positionen und Namensplaketten getrennt gespeichert; die Bewegung gilt für beide Modi.",
        "Adjust text size and movement strength. Size is stored separately for fixed and nameplate modes; movement applies to both.",function(form,v)
        local function sizeKey() return v.draft.displayMode=="nameplate" and "nameplateScale" or "scale" end
        form:Slider({key="size",label=tr("Textgröße","Text size"),min=.6,max=function() return v.draft.displayMode=="nameplate" and 4.2 or 2.5 end,
            step=.1,live=true,format="%.1f",suffix=" ×",get=function() return v.draft[sizeKey()] end,set=function(value) v.draft[sizeKey()]=value end,
            default=function() return defaults[sizeKey()] end})
        form:Slider({key="intensity",label=tr("Bewegung","Movement"),min=1,max=3,step=1,live=true,
            labels={[1]=tr("Dezent","Subtle"),[2]=tr("Normal","Normal"),[3]=tr("Kräftig","Strong")}})
        preview(form,v,"crit")
    end)
    local fonts={{"standard",tr("Standard","Standard")},{"comic",tr("Comic","Comic")},{"epic",tr("Episch","Epic")},{"heavy",tr("Kräftig","Heavy")}}
    local function graphics(kind,de,en,descriptionDE,descriptionEN)
        step(de,en,descriptionDE,descriptionEN,function(form,v)
            toggle(form,kind.."Graphics",kind=="crit" and tr("Krit-Grafik anzeigen","Show crit graphic") or tr("Kill-Grafik anzeigen","Show kill graphic"))
            form:Select({key=kind.."Font",label=kind=="crit" and tr("Effekt- & Schadensschrift","Effect & damage font") or tr("Schriftstil","Font style"),options=fonts})
            v:Color(form,{key=kind.."Color",label=tr("Textfarbe","Text color")})
            preview(form,v,kind)
        end)
    end
    local function texts(kind,de,en,descriptionDE,descriptionEN)
        step(de,en,descriptionDE,descriptionEN,function(form,v)
            form:Texts({key=kind.."Texts",label=kind=="crit" and tr("Zufallstexte für Krits","Random crit texts") or tr("Zufallstexte für Kills","Random kill texts"),
                desc=tr("Bis zu 20 Texte mit jeweils 40 Zeichen. Eine Variante pro Zeile.","Up to 20 texts, 40 characters each. One variant per line."),
                maxLines=20,maxChars=40,
                get=function() return v.draft[kind.."Texts"] end,
                set=function(lines) v.draft[kind.."Texts"]=NS.Logic.SanitizeTexts(lines,kind) end})
            preview(form,v,kind)
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
        "Choose sounds for crits, critical heals and kills, or disable them separately. The sound pause limits how frequently sounds play in succession.",function(form,v)
        -- The list of sounds is read again on every refresh: it follows the sound library.
        local function soundOptions()
            local options,known={{"__keep",tr("Aktuelle Auswahl beibehalten","Keep current selection")}},{}
            for _,item in ipairs(NS.Sounds.Catalog(app.db,app.api.env)) do
                options[#options+1]={item.id,NS.Locale.Text(item.name)}; known[item.id]=true
            end
            return options,known
        end
        for _,entry in ipairs({{"crit",tr("Krit","Crit")},{"heal",tr("Heal","Heal")},{"kill",tr("Kill","Kill")}}) do
            local kind=entry[1]
            toggle(form,kind.."Sound",entry[2])
            form:Select({key=kind.."SoundChoice",label=tr("Klang","Sound"),parent=kind.."Sound",translate=false,default="__keep",
                options=function() return (soundOptions()) end,
                get=function()
                    local _,known=soundOptions()
                    local ids=v.draft[kind.."SoundIDs"]
                    return v.draft[kind.."SoundMode"]=="single" and known[ids[1]] and ids[1] or "__keep"
                end,
                set=function(id)
                    if id~="__keep" then v.draft[kind.."SoundMode"]="single"; v.draft[kind.."SoundIDs"]={id} end
                end,
                button={text=tr("Anhören","Listen"),onClick=function()
                    local ids=v.draft[kind.."SoundIDs"]
                    local id=#ids>0 and ids[math.random(#ids)] or nil
                    local ok,reason=false,tr("Keine Soundauswahl vorhanden.","No sound selected.")
                    if id then ok,reason=app:PreviewSoundRef(id,kind) end
                    v:SetMessage(ok and tr("Hörprobe abgespielt.","Sound preview played.") or NS.Locale.Text(reason))
                end}})
        end
        note(form,"Standard: Krit Klong · Heal Ta-da! · Kill Bruh. Auch Krit- und Kill-Mixe sind auswählbar.",
            "Defaults: crit Klong · heal Ta-da! · kill Bruh. Crit and kill mixes are also available.")
        form:Slider({key="soundCooldown",label=tr("Soundpause","Sound pause"),min=0,max=30,step=.05,live=true,format="%.2f",suffix=tr(" Sekunden"," seconds")})
    end)
    step("Krits und Heilungen aufzeichnen","Record crits and heals",
        "Speichere die 100 höchsten und 100 letzten beobachteten Schadenskrits und kritischen Heilungen pro Charakter. In der History siehst du Werte, Ziel, Zeitpunkt und Gebiet.",
        "Save the 100 highest and 100 most recent observed critical damage and heals per character. History shows amount, target, time and location.",function(form)
        toggle(form,"historyEnabled",tr("History-Aufzeichnung aktivieren","Enable history recording"),{default=true})
        note(form,"Standard: aktiviert. Grafik und Sounds beeinflussen die Aufzeichnung nicht.","Default: enabled. Graphics and sounds do not affect recording.")
        note(form,"Hinweis zu beobachteten Treffern","About observed hits")
        note(form,"Bei Ziel-Krits und Ziel-Heals kann der Client nicht unterscheiden, von welchem Spieler sie stammen.",
            "For target crits and heals the client cannot identify the player who caused them.")
    end)
    step("Zenial Crit ist bereit","Zenial Crit is ready",
        "Deine Grundauswahl ist getroffen. Mit „Fertig“ speicherst du sie. Weitere Optionen, eigene Audiodateien und deine History findest du jederzeit im normalen Addon-Fenster.",
        "Your basic setup is ready. Finish saves your choices. Additional options, custom audio and history are always available in the addon window.",function(form,v)
        form:Note({text=function()
            local d=v.draft; local function on(value) return value and tr("An","On") or tr("Aus","Off") end
            return table.concat({tr("Anzeigemodus: ","Display mode: ")..(d.displayMode=="fixed" and tr("Feste Positionen","Fixed positions") or tr("Über Namensplakette","Above nameplate")),
                tr("Grafik für Krit / Kill: ","Crit / kill graphics: ")..on(d.critGraphics).." / "..on(d.killGraphics),
                tr("Sounds für Krit / Heal / Kill: ","Crit / heal / kill sounds: ")..on(d.critSound).." / "..on(d.healSound).." / "..on(d.killSound),
                tr("History: ","History: ")..on(d.historyEnabled)},"\n\n")
        end})
        form:Note({anchor="settingsHint",text=tr("Alle Einstellungen öffnest du mit /zcrit settings. Dort findest du weitere Optionen, die du in Ruhe prüfen kannst. Den Assistenten startest du erneut mit /zcrit config.",
            "Open all settings with /zcrit settings. Review additional options there at your own pace. Restart the wizard with /zcrit config.")})
    end)
    S.wizard=W.New({label="Crit",steps=steps,store=ZenialCritSetupDB,capture=capture,sanitize=sanitize,apply=commit,
        default=function(key) return defaults[key] end,
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
