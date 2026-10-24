-- qos-MM2 v0.3.124
-- ] (RightBracket): menu. End: unload. All gameplay switches start OFF.
-- Prism: https://raw.githubusercontent.com/3xjn/qos-mm2/main/prism.lua

local ENV = (type(getgenv) == "function" and getgenv()) or _G
local PRISM_URL = (type(ENV.QOS_MM2_PRISM_URL) == "string" and ENV.QOS_MM2_PRISM_URL)
    or "https://raw.githubusercontent.com/3xjn/qos-mm2/main/prism.lua"
local prismSource = game:HttpGet(PRISM_URL, true)
local loadPrism, prismErr = loadstring(prismSource)
if type(loadPrism) ~= "function" then
    error("Prism did not compile (" .. PRISM_URL .. "): " .. tostring(prismErr), 0)
end
local React, ReactRoblox, Prism, PrismPackage, PrismCleanup = loadPrism()
if type(React) ~= "table" or type(React.createElement) ~= "function" then
    error("Prism runtime unavailable: " .. PRISM_URL, 0)
end

if ENV.QOS_MM2 and ENV.QOS_MM2.Unload then pcall(ENV.QOS_MM2.Unload) end
local A = { alive = true, connections = {}, esp = {}, collision = {}, localCollision = {},
    statuses = {}, roles = {}, lock = nil, movement = nil, diagnostics = {},
    config = { murdererESP = false, sheriffESP = false, heroESP = false, innocentESP = false, droppedGunESP=false, tracerMurderer=false,tracerSheriff=false,tracerHero=false,tracerInnocent=false,
        antiAfk = true, antiFling = false, silentGunAim = false, cameraAim = false, showFov = false, farm = false, autoGun = true,
        fov = 160, prediction = 0,
        farmWalkSpeed = 16, requireRound = true }, version = "0.3.124" }
ENV.QOS_MM2 = A
A.Players = game:GetService("Players")
A.Run = game:GetService("RunService")
A.Input = game:GetService("UserInputService")
A.RS = game:GetService("ReplicatedStorage")
A.Tags = game:GetService("CollectionService")
A.GuiService = game:GetService("GuiService")
A.player = A.Players.LocalPlayer
if not A.player then error("qos-MM2 needs a Roblox client") end

function A.connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(A.connections, c)
    return c
end
A.tasks={}
A.resources=setmetatable({}, {__mode="k"})
function A.schedule(kind,delay,fn,...)
    if not A.alive then return end
    local args=table.pack(...)
    local tasks=A.tasks
    local thread
    thread=coroutine.create(function()
        local ok,err=pcall(fn,table.unpack(args,1,args.n))
        tasks[thread]=nil
        if not ok and A.alive then warn("[MM2 task] "..tostring(err)) end
    end)
    tasks[thread]=true
    if kind=="delay" then task.delay(delay,thread)
    elseif kind=="defer" then task.defer(thread)
    else task.spawn(thread) end
    return thread
end
function A.spawn(fn,...)return A.schedule("spawn",0,fn,...)end
function A.defer(fn,...)return A.schedule("defer",0,fn,...)end
function A.delay(delay,fn,...)return A.schedule("delay",delay,fn,...)end

function A.antiAfkPulse()
    if not A.alive or not A.config.antiAfk then return false end
    if os.clock()-(A.lastAntiAfkPulse or -60)<30 then return false end
    local ok,err=pcall(function()
        local controller=game:GetService("VirtualUser")
        controller:CaptureController()
        local camera=workspace.CurrentCamera
        controller:ClickButton2(Vector2.zero,camera and camera.CFrame or CFrame.new())
    end)
    if ok then A.lastAntiAfkPulse=os.clock() end
    A.log(ok and "anti_afk_activity" or "anti_afk_error",{error=err})
    return ok
end
A.connect(A.player.Idled,function() A.antiAfkPulse() end)

A.playerList=A.Players:GetPlayers()
A.connect(A.Players.PlayerAdded,function(p) table.insert(A.playerList,p) end)
A.connect(A.Players.PlayerRemoving,function(p)
    local i=table.find(A.playerList,p); if i then table.remove(A.playerList,i) end
end)
function A.new(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props or {}) do obj[k] = v end
    obj.Parent = parent
    return obj
end
A.botLog={sequence=0,lines={},pending={},part=1,bytes=0}
local function logValue(value,depth)
    local kind=typeof(value)
    if kind=="Vector3"then return {x=value.X,y=value.Y,z=value.Z}end
    if kind=="CFrame"then return logValue(value.Position,depth)end
    if kind=="Instance"then return value:GetFullName()end
    if kind=="EnumItem"then return tostring(value)end
    if kind=="number"then return value==value and math.abs(value)<math.huge and value or tostring(value)end
    if kind=="string"or kind=="boolean"then return value end
    if kind=="table"and depth<4 then
        local result={};local count=0
        for key,item in pairs(value)do
            count=count+1;if count>80 then break end
            result[tostring(key)]=logValue(item,depth+1)
        end
        return result
    end
    return tostring(value)
end
function A.log(event,data)
    local log=A.botLog;if not log then return end
    log.sequence=log.sequence+1
    local ok,line=pcall(function()return game:GetService("HttpService"):JSONEncode({sequence=log.sequence,time=os.clock(),utc=os.date("!%Y-%m-%dT%H:%M:%SZ"),event=event,data=logValue(data or {},0)})end)
    if not ok then return end
    log.lines[((log.sequence-1)%5000)+1]=line
    table.insert(log.pending,line)
    if #log.pending>500 then table.remove(log.pending,1)end
end
function A.flushLog()
    local log=A.botLog;if not log or #log.pending==0 then return end
    if type(writefile)~="function"or type(appendfile)~="function"then return end
    local ok,err=pcall(function()
        if not log.session then
            if type(makefolder)=="function"then pcall(makefolder,"qos-MM2-logs")end
            log.session="qos-MM2-logs/"..os.date("!%Y%m%d-%H%M%S").."-"..tostring(math.floor(os.clock()*1000))
        end
        local payload=table.concat(log.pending,"\n").."\n"
        if log.bytes+#payload>1048576 then log.part=log.part%4+1;log.bytes=0;log.initialized=false end
        log.path=log.session.."-"..log.part..".jsonl"
        if not log.initialized then writefile(log.path,"");log.initialized=true end
        appendfile(log.path,payload);log.bytes=log.bytes+#payload;table.clear(log.pending)
    end)
    if not ok then log.diskError=tostring(err)end
end
function A.logText()
    local log=A.botLog;local lines={}
    for i=math.max(1,log.sequence-4999),log.sequence do table.insert(lines,log.lines[((i-1)%5000)+1])end
    return table.concat(lines,"\n").."\n"
end
function A.logStep()
    local now=os.clock()
    if now>=(A.nextBotSnapshot or 0)then
        A.nextBotSnapshot=now+0.5
        if A.config.farm then
            local _,humanoid,root=A.body(A.player);local move=A.movement
            A.log("movement",{position=root and root.Position,velocity=root and root.AssemblyLinearVelocity,state=humanoid and humanoid:GetState(),role=A.role(A.player),target=move and move.target,targetPosition=move and move.target and move.target.Position,waypoint=move and move.pathIndex,direction=move and move.walkDirection,planning=move and move.planning,recovery=move and move.recoveryGoal,coins=#A.coinCache,combat=A.collectorCombatRole})
            local threats={}
            for _,threat in ipairs(A.collectorThreats)do threats[#threats+1]={player=threat.player and threat.player.Name,current=threat.current,predicted=threat.position,future=threat.future,provisional=threat.provisional}end
            A.log("threats",threats)
        end
    end
    if now>=(A.nextLogFlush or 0)then A.nextLogFlush=now+2;A.flushLog()end
end
A.log("session_start",{version=A.version})

function A.note(key, value)
    if A.statuses[key] == value then return end
    A.statuses[key] = value
    if A.log then A.log("status",{category=key,message=value})end
    if A.statusLabel then A.statusLabel.Text = key .. ": " .. tostring(value) end
end
function A.body(player)
    local ch = player.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local root = ch and ch:FindFirstChild("HumanoidRootPart")
    if hum and hum.Health > 0 and root then return ch, hum, root end
end
function A.finite(v)
    return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z
        and math.abs(v.X) < 1000000 and math.abs(v.Y) < 1000000 and math.abs(v.Z) < 1000000
end
function A.findTool(player, kind)
    local direct=(player.Character and player.Character:FindFirstChild(kind))
        or (player:FindFirstChildOfClass("Backpack") and player:FindFirstChildOfClass("Backpack"):FindFirstChild(kind))
    if direct and direct:IsA("Tool") then return direct end
    for _, container in ipairs({ player.Character or false, player:FindFirstChildOfClass("Backpack") or false }) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") and (tool.Name == kind or
                    (kind == "Gun" and tool:FindFirstChild("Shoot")) or
                    A.Tags:HasTag(tool, "Weapon_" .. kind)) then return tool end
            end
        end
    end
end
function A.roundData(player)
    local data = A.round and A.round.PlayerData
    return type(data) == "table" and (data[player.Name] or data[player.UserId]) or nil
end
function A.isZombie(player)
    local character=player.Character
    local data=A.roundData(player)
    return character and (character:GetAttribute("Zombie")==true
        or character:GetAttribute("Role")=="Zombie" or player:GetAttribute("Role")=="Zombie"
        or (data and data.Role=="Zombie")) or false
end

function A.roleUncached(player)
    local d = A.roundData(player)
    if not A.espAlive(player) then return "Dead" end
    local _, hum = A.body(player)
    if not hum then return "Dead" end
    if A.isZombie(player) then return "Murderer" end
    local role = (d and d.Role) or player:GetAttribute("Role")
        or (player.Character and player.Character:GetAttribute("Role"))
    if role == "Murderer" or role == "Sheriff" or role == "Hero" then return role end
    if A.findTool(player, "Knife") then return "Murderer" end
    if A.findTool(player, "Gun") then return "Gun holder" end
    return role=="Survivor" and "Innocent" or role or "Innocent"
end
A.roleCache=setmetatable({}, {__mode="k"})
-- Death records belong to a character life, not permanently to a Player.
A.lifeState=setmetatable({}, {__mode="k"})
function A.trackLife(player,character)
    local previous=A.lifeState[player]
    if previous and previous.character==character then return previous end
    local data=A.roundData(player)
    local state={character=character,ignoreRoundDeath=previous~=nil and data~=nil
        and (data.Dead==true or data.Killed==true) or false}
    A.lifeState[player]=state
    A.roleCache[player]=nil
    if A.clearESP then A.clearESP(player) end
    if A.tracers and A.tracers[player] then A.tracers[player].Visible=false end
    return state
end
function A.espAlive(player)
    local character=player.Character
    local state=A.trackLife(player,character)
    local hum=character and character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health<=0 then
        state.wasDead=true
        return false
    end
    local data=A.roundData(player)
    local roundDead=data and (data.Dead==true or data.Killed==true)
    -- Some event rounds revive the same character instead of replacing it.
    if state.wasDead then
        state.wasDead=false
        state.ignoreRoundDeath=roundDead==true
        A.roleCache[player]=nil
    end
    if not roundDead then state.ignoreRoundDeath=false end
    if not character:FindFirstChild("HumanoidRootPart") then return false end
    if character:GetAttribute("Alive")==false or character:GetAttribute("Dead")==true
        or character:GetAttribute("Killed")==true then return false end
    -- Infection round data belongs to this mode; legacy player Alive flags
    -- can remain false for healthy zombies and armed survivors.
    local liveZombie=A.isZombie(player)
    local liveSurvivor=data and data.Role=="Survivor" and not roundDead and A.findTool(player,"Gun")~=nil
    if liveZombie then return true end
    if not liveSurvivor and character:GetAttribute("Alive")~=true and
        (player:GetAttribute("Alive")==false or player:GetAttribute("Dead")==true
        or player:GetAttribute("Killed")==true) then return false end
    return not roundDead or state.ignoreRoundDeath
end
function A.watchLife(player)
    A.trackLife(player,player.Character)
    A.connect(player.CharacterAdded,function(character)
        A.trackLife(player,character)
    end)
end
for _,player in ipairs(A.playerList) do A.watchLife(player) end
A.connect(A.Players.PlayerAdded,A.watchLife)

function A.role(player)
    if not A.espAlive(player) then return "Dead" end
    local cached=A.roleCache[player]
    local now=os.clock()
    if cached and cached.character==player.Character and now-cached.at<0.1 then return cached.value end
    local value=A.roleUncached(player)
    A.roleCache[player]={character=player.Character,at=now,value=value}
    return value
end
A.partCache=setmetatable({}, {__mode="k"})
function A.characterParts(character)
    local entry=A.partCache[character]
    if entry then return entry.parts end
    entry={parts={}};A.partCache[character]=entry
    for _,part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then table.insert(entry.parts,part) end
    end
    local added,removed,ancestry
    added=A.connect(character.DescendantAdded,function(part)
        if part:IsA("BasePart") then table.insert(entry.parts,part) end
    end)
    removed=A.connect(character.DescendantRemoving,function(part)
        local index=table.find(entry.parts,part)
        if index then table.remove(entry.parts,index) end
    end)
    ancestry=A.connect(character.AncestryChanged,function()
        if not character:IsDescendantOf(game) then
            added:Disconnect();removed:Disconnect();ancestry:Disconnect();A.partCache[character]=nil
        end
    end)
    return entry.parts
end
function A.inRound()
    local ch = A.player.Character
    if not A.body(A.player) then return false end
    if not A.config.requireRound then return true end
    local d = A.roundData(A.player)
    if d then return d.Dead ~= true and d.Killed ~= true and d.Role ~= nil end
    return A.player:GetAttribute("Alive") == true or A.player:GetAttribute("InGame") == true
        or (ch and (ch:GetAttribute("InGame") == true or ch:GetAttribute("Alive") == true))
end
A.spawn(function()
    local modules = A.RS:FindFirstChild("Modules")
    local m = modules and modules:FindFirstChild("CurrentRoundClient")
    if m and m:IsA("ModuleScript") then
        local ok, result = pcall(require, m)
        if A.alive and ok and type(result) == "table" then A.round = result end
    end
end)

-- Prism UI. Gameplay state remains owned by A; React only renders controls.
A.colors = { bg=Color3.fromRGB(128,136,141), panel=Color3.fromRGB(185,195,201),
    text=Color3.fromRGB(243,249,252), muted=Color3.fromRGB(199,214,222),
    accent=Color3.fromRGB(226,239,245), red=Color3.fromRGB(255,93,116),
    blue=Color3.fromRGB(100,170,255), gold=Color3.fromRGB(255,208,100), green=Color3.fromRGB(100,230,150) }
local guiParent = A.player:WaitForChild("PlayerGui",10)
if type(gethui)=="function" then local ok,p=pcall(gethui); if ok and typeof(p)=="Instance" then guiParent=p end end
assert(guiParent,"qos-MM2: PlayerGui unavailable")
A.gui=A.new("ScreenGui",{Name="qos-MM2",ResetOnSpawn=false,IgnoreGuiInset=true,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=500},guiParent)
A.worldGui=A.new("Folder",{Name="qos-MM2-Visuals"},A.gui)
A.uiHost=A.new("ScreenGui",{Name="qos-MM2-Prism",ResetOnSpawn=false,IgnoreGuiInset=true,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=501},guiParent)
A.prismPackage=PrismPackage
A.bundleCleanup=PrismCleanup
A.readyPages={Combat=true};A.uiVisible=true; A.uiCollapsed=false; A.activePage="Combat"; A.search=""
A.pages={}; A.toggleButtons={}; A.uiMounted=false
function A.dirty()
    if not A.uiMounted or A.uiQueued or not A.alive then return end
    A.uiQueued=true
    A.delay(0.05,function()
        A.uiQueued=false
        -- Hiding must render once, even while background updates are paused.
        if not A.uiVisible and A.uiRenderedVisible==false then return end
        if A.alive and A.renderUI then
            local ok,err=pcall(A.renderUI)
            if not ok then warn("[qos-MM2 UI] "..tostring(err)) end
        end
    end)
end
A.window=setmetatable({}, {
    __index=function(_,key) if key=="Visible" then return A.uiVisible and not A.uiCollapsed end end,
    __newindex=function(_,key,value) if key=="Visible" then A.uiVisible=value==true; A.uiCollapsed=false; A.dirty() end end,
})
function A.textProxy(node)
    return setmetatable({}, {
        __index=function(_,key) if key=="Text" then return node.text end end,
        __newindex=function(_,key,value) if key=="Text" then
            value=tostring(value)
            if node.text~=value then node.text=value; A.dirty() end
        end end,
    })
end
A.statusLabel=A.textProxy({text="Ready"})
function A.page(name,order)
    local page={name=name,order=order,nodes={},group=name}
    A.pages[name]=page
    return page
end
function A.group(page,title) page.group=title end
function A.addNode(page,node)
    node.group=page.group; node.id=#page.nodes+1; table.insert(page.nodes,node); return node
end
function A.label(page,text,height)
    return A.textProxy(A.addNode(page,{kind="text",text=text,height=height}))
end
function A.button(page,text,callback)
    return A.addNode(page,{kind="button",text=text,callback=callback})
end
function A.set(key,value)
    value=value==true
    if A.log then A.log("setting",{key=key,value=value})end
    if key=="farm"and not value and A.stopCollectorCombat then A.stopCollectorCombat()end
    if value and key=="silentGunAim" and not A.config[key] and A.enableSilentAim then
        if A.enableSilentAim()==false then A.dirty(); return false end
    end
    A.config[key]=value
    if key=="silentGunAim" and not value and A.disableSilentAim then A.disableSilentAim() end
    if key=="farm" and not value and A.clearCollectorThreats then A.clearCollectorThreats() end
    if key=="farm" and not value and A.movement and A.movement.owner=="farm" then A.releaseMove(true) end
    if key=="antiFling" and not value and A.restoreCollision then A.restoreCollision() end
    A.dirty(); return true
end
function A.toggle(page,text,key,onEnable)
    local node=A.addNode(page,{kind="switch",text=text,key=key,onEnable=onEnable})
    A.toggleButtons[key]=node; return node
end
function A.input(page,title,initial,callback)
    local node=A.addNode(page,{kind="input",text=tostring(initial),title=title,callback=callback})
    node.proxy=A.textProxy(node); return node.proxy
end
function A.number(page,title,key,lo,hi)
    return A.addNode(page,{kind="slider",text=title,key=key,min=lo,max=hi})
end
function A.safeAction(fn)
    if not A.alive then return end
    local ok,err=pcall(fn)
    if not ok then A.note("Error",tostring(err)); warn("[qos-MM2] "..tostring(err)) end
    A.dirty()
end
A.visualPage=A.page("Visuals",1)
A.combatPage=A.page("Combat",2)
A.farmPage=A.page("Collect",3)
A.settingsPage=A.page("Settings",4)
A.group(A.visualPage,"Player ESP")

local e=React.createElement
local palette=A.colors
-- One shared theme supplies every control, including hover and focus states.
A.theme=table.clone(Prism.DEFAULT_DARK_THEME)
A.theme.colors=table.clone(A.theme.colors)
A.theme.colors.primary={main=palette.accent,light=Color3.fromRGB(246,250,252),dark=Color3.fromRGB(142,158,168),contrast=palette.bg}
A.theme.colors.secondary={main=palette.muted,light=palette.text,dark=palette.panel,contrast=palette.bg}
A.theme.colors.background={default=palette.bg,surface=palette.panel,raised=Color3.fromRGB(38,43,53)}
A.theme.colors.text={primary=palette.text,secondary=palette.muted,disabled=Color3.fromRGB(98,106,120),inverse=palette.bg}
A.theme.colors.border={subtle=Color3.fromRGB(43,49,61),default=Color3.fromRGB(57,65,80),strong=Color3.fromRGB(88,101,122)}
A.theme.colors.action={hover=Color3.fromRGB(53,61,75),pressed=Color3.fromRGB(66,77,94),disabled=Color3.fromRGB(102,109,121),disabledBackground=palette.panel}
A.theme.fontFamily=Enum.Font.Gotham
A.theme.fontSizes={xs=11,sm=13,md=14,lg=16,xl=20}
A.theme.radius={xs=8,sm=18,md=20,lg=22,xl=28}
A.theme.spacing={xs=4,sm=8,md=12,lg=16,xl=24}
A.theme.shadows={xs={color=Color3.new(),thickness=1,transparency=0.95},sm={color=Color3.new(),thickness=2,transparency=0.92},
    md={color=Color3.new(),thickness=5,transparency=0.85},lg={color=Color3.new(),thickness=7,transparency=0.83},xl={color=Color3.new(),thickness=9,transparency=0.8}}
for _,shadow in pairs(A.theme.shadows) do shadow.transparency=1 end
local shortNames={
    ["Camera aim assist (hold right mouse)"]="Camera assist",
    ["Silent aim (visible murderer)"]="Silent aim",
    ["Walking coin / candy collector"]="Collector",
    ["Auto grab dropped gun"]="Gun pickup",
    ["Require round data before moving"]="Active round",
    ["Prediction (seconds)"]="Prediction",
    ["Aim radius (pixels)"]="Aim radius",
    ["Kill all (murderer)"]="Kill all",
    ["Fling target: exact username or unique prefix"]="Username",
    ["Turn all features off"]="All off",
}
local hints={silentGunAim="Hits a visible murderer. Typing pauses it.",
    cameraAim="Hold right mouse.",showFov="Draws the circle.",
    antiFling="Stops sudden flings.",farm="WASD or Space stops it.",
    autoGun="Picks up a dropped gun.",requireRound="Moves only during a round."}
local function txt(text,props)
    local p={text=text,size=13,weight=500,color=palette.text,width="100%",height=20,wrap=true,align="left"}
    for k,v in pairs(props or {}) do p[k]=v end
    return e(Prism.Text,p)
end
local function stack(children,props)
    local p={width="100%",gap=10,slotProps={root={AutomaticSize=Enum.AutomaticSize.Y}}}
    for k,v in pairs(props or {}) do p[k]=v end
    return e(Prism.Stack,p,children)
end
local function card(children,order)
    return e(Prism.Card,{width="100%",p=16,radius=22,variant="outline",bg=palette.panel,bgTransparency=0.89,
        stroke={color=A.theme.colors.border.default,thickness=1,transparency=0.58},shadow=false,
        layoutOrder=order,slotProps={root={Name="GlassPanel",AutomaticSize=Enum.AutomaticSize.Y}}},{Content=stack(children)})
end
function A.renderNodeUncached(node,order)
    local title=shortNames[node.text] or node.text
    if node.kind=="switch" then
        return e(Prism.Box,{width="100%",height=hints[node.key] and 58 or 38,layoutOrder=order},{
            Title=txt(title,{size=14,width=UDim.new(1,-64),height=24}),
            Switch=e(Prism.Switch,{checked=A.config[node.key],width=44,height=28,position=UDim2.new(1,-44,0,0),
                color="primary",slotProps={root={Name="Toggle_"..node.key}},onChange=function(value)
                    A.safeAction(function()
                        if value and node.onEnable and node.key~="silentGunAim" and node.onEnable()==false then A.dirty(); return end
                        A.set(node.key,value)
                    end)
                end}),
            Hint=hints[node.key] and txt(hints[node.key],{size=11,color=palette.muted,position=UDim2.fromOffset(0,26),width=UDim.new(1,-64),height=28}) or nil,
        })
    elseif node.kind=="slider" then
        local value=A.config[node.key]
        return stack({Title=txt(title,{layoutOrder=1,color=palette.muted}),
            Slider=e(Prism.Slider,{width="100%",height=36,value=value,min=node.min,max=node.max,
                step=node.key=="prediction" and 0.01 or 1,tooltip=true,layoutOrder=2,
                slotProps={root={Name="Slider_"..node.key}},onChange=function(v)
                    A.config[node.key]=math.clamp(v,node.min,node.max); A.dirty()
                end}),
            Value=txt(node.key=="prediction" and string.format("%.2f s",value) or tostring(math.floor(value)),
                {size=11,color=palette.accent,layoutOrder=3,height=16}),
        },{layoutOrder=order,gap=2})
    elseif node.kind=="button" then
        local danger=node.text:find("Unload",1,true) or node.text:find("all features off",1,true)
        return e(Prism.Button,{label=title,fullWidth=true,width="100%",height=36,layoutOrder=order,
            color=danger and "error" or "primary",variant="outline",
            slotProps={root={Name="GlassButton_"..node.id},label={TextSize=13}},
            styleOverrides=function(_,context) return {textColor=danger and Color3.fromRGB(255,213,214) or palette.text,
                backgroundColor=Color3.fromRGB(224,233,238),
                backgroundTransparency=context.state=="pressed" and 0.78 or (context.state=="hover" and 0.85 or 0.92)} end,
            onPress=function() A.safeAction(node.callback) end})
    elseif node.kind=="input" then
        return stack({Title=txt(shortNames[node.title] or node.title,{layoutOrder=1,color=palette.muted}),
            Input=e(Prism.Input,{width="100%",height=36,value=node.text,slotProps={root={Name="GlassInput_"..node.id,BackgroundColor3=Color3.fromRGB(192,205,212),BackgroundTransparency=0.94},stroke={Enabled=false},corner={CornerRadius=UDim.new(0,16)},textbox={BackgroundTransparency=1,TextColor3=palette.text,PlaceholderColor3=palette.muted}},placeholder="Enter username…",layoutOrder=2,
                onChange=function(v) node.text=v; A.dirty() end,
                Event={FocusLost=function() A.safeAction(function() node.callback(node.text,node.proxy) end) end}}),
        },{layoutOrder=order,gap=5})
    else
        if node.text=="" then return nil end
        local window=A.uiHost:FindFirstChild("QosPrismWindow",true)
        local width=math.max(220,(window and window.AbsoluteSize.X or 760)-226)
        local bounds=game:GetService("TextService"):GetTextSize(node.text,11,Enum.Font.Gotham,Vector2.new(width,10000))
        return txt(node.text,{size=11,color=palette.muted,valign="top",height=math.max(node.height or 44,math.ceil(bounds.Y*1.5)+16),layoutOrder=order})
    end
end
function A.renderNode(node,order)
    local signature=tostring(node.text).."|"..tostring(node.title).."|"..tostring(order).."|"..tostring(node.key and A.config[node.key])
    if node.renderSignature~=signature then
        node.renderSignature=signature;node.renderElement=A.renderNodeUncached(node,order)
    end
    return node.renderElement
end
function A.switchPage(name)
    if not A.readyPages[name] then A.readyPages[name]=true;A.activePage=name;A.search="";A.dirty();return end
    if name==A.activePage then return end
    local hadSearch=A.search~=""
    A.activePage=name;A.search=""
    if hadSearch then A.dirty();return end
    for _,page in ipairs({"Combat","Visuals","Collect","Settings"}) do
        local scroll=A.uiHost:FindFirstChild("Page_"..page,true)
        if scroll then scroll.Visible=page==name end
        local nav=A.uiHost:FindFirstChild("Nav_"..page,true)
        if nav then nav.BackgroundTransparency=1; local glass=nav:FindFirstChild("GlassSurface"); if glass then glass.ImageTransparency=page==name and 0 or 0.45 end end
    end
    local subtabs=A.uiHost:FindFirstChild("VisualSubtabs",true)
    if subtabs then subtabs.Visible=name=="Visuals" end
    local heading=A.uiHost:FindFirstChild("PageHeading",true)
    if heading then heading.Text=name end
end
function A.pageCards(pageName,search)
    local page=A.pages[pageName or A.activePage]
    local groups,ordered={},{}
    local query=(search or A.search):lower()
    for _,node in ipairs(page.nodes) do
        local haystack=(node.text or "").." "..(node.title or "").." "..node.group
        if (page.name~="Visuals" or (node.visualTab or "ESP")== (A.visualTab or "ESP")) and (query=="" or haystack:lower():find(query,1,true)) then
            if not groups[node.group] then groups[node.group]={}; table.insert(ordered,node.group) end
            table.insert(groups[node.group],node)
        end
    end
    local cards={}
    for i,name in ipairs(ordered) do
        local children={Heading=txt(name,{color=palette.text,size=14,weight=600,height=26,layoutOrder=1})}
        for j,node in ipairs(groups[name]) do children["Control"..node.id]=A.renderNode(node,j+1) end
        cards["Group"..i]=card(children,i)
    end
    if #ordered==0 then cards.Empty=card({Text=txt("No matches.",{height=28,color=palette.muted})},1) end
    return cards
end
function A.PrismApp()
    local rail={Brand=txt("qos",{size=20,weight=600,height=32,layoutOrder=1}),
        Sub=txt("MM2",{size=11,color=palette.muted,height=20,layoutOrder=2}),
        }
    for i,name in ipairs({"Combat","Visuals","Collect","Settings"}) do
        local selected=A.activePage==name
        rail["Nav"..name]=e(Prism.Button,{label=name,width="100%",height=38,layoutOrder=i+3,
            variant=selected and "light" or "subtle",color="primary",
            styleOverrides=function(styles,context)
                return {textColor=selected and palette.accent or palette.muted,
                    backgroundColor=selected and palette.accent or A.theme.colors.action.hover,
                    backgroundTransparency=1}
            end,
            slotProps={root={Name="Nav_"..name,TextXAlignment=Enum.TextXAlignment.Left}},
            onPress=function() A.switchPage(name) end})
    end
    rail.Hotkey=txt("]  Menu\nEnd  Unload",{size=10,color=palette.muted,height=42,layoutOrder=20})
    local content={
        Heading=e(Prism.Stack,{width="100%",height=62,p=20,gap=0},{
            Title=txt(A.activePage,{slotProps={root={Name="PageHeading"}},size=22,weight=600,height=28,layoutOrder=1}),
        }),
        Search=e(Prism.Input,{slotProps={root={Name="GlassInput_Search",BackgroundColor3=Color3.fromRGB(192,205,212),BackgroundTransparency=0.94},stroke={Enabled=false},corner={CornerRadius=UDim.new(0,16)},textbox={BackgroundTransparency=1,TextColor3=palette.text,PlaceholderColor3=palette.muted}},value=A.search,placeholder="Search…",variant="outline",color="primary",
            position=UDim2.fromOffset(20,62),width=UDim.new(1,-40),height=34,
            onChange=function(v) A.search=v; A.dirty() end}),
        Footer=e(Prism.Box,{position=UDim2.new(0,0,1,-36),width="100%",height=36},{
            Text=txt(A.statusLabel.Text,{position=UDim2.fromOffset(20,8),width=UDim.new(1,-40),height=28,
                color=palette.muted,size=10}),
        }),
    }
    content.VisualTabs=e(Prism.Box,{position=UDim2.fromOffset(20,108),width=UDim.new(1,-40),height=36,
        slotProps={root={Name="VisualSubtabs",Visible=A.activePage=="Visuals"}}},{
        ESP=e(Prism.Button,{label="ESP",width=100,height=32,variant="subtle",styleOverrides=function()return {textColor=palette.text,backgroundTransparency=1}end,
            slotProps={root={Name="VisualTab_ESP"}},onPress=function() A.visualTab="ESP";A.search="";A.dirty() end}),
        Tracers=e(Prism.Button,{label="Tracers",position=UDim2.fromOffset(110,0),width=110,height=32,
            variant="subtle",styleOverrides=function()return {textColor=palette.text,backgroundTransparency=1}end,slotProps={root={Name="VisualTab_Tracers"}},
            onPress=function() A.visualTab="Tracers";A.search="";A.dirty() end}),
    })
    A.pageElementCache=A.pageElementCache or {}
    for _,name in ipairs({"Combat","Visuals","Collect","Settings"}) do
        if not A.readyPages[name] then continue end
        local query=name==A.activePage and A.search or ""
        local parts={query,name=="Visuals" and (A.visualTab or "ESP") or ""}
        for _,node in ipairs(A.pages[name].nodes) do table.insert(parts,tostring(node.text).."="..tostring(node.key and A.config[node.key])) end
        local signature=table.concat(parts,"|")
        local cached=A.pageElementCache[name]
        if not cached or cached.signature~=signature then
            cached={signature=signature,element=stack(A.pageCards(name,query),{px=20,pb=20,gap=12})}
            A.pageElementCache[name]=cached
        end
        content["Scroll_"..name]=e(Prism.ScrollArea,{position=UDim2.fromOffset(0,name=="Visuals" and 158 or 112),
            width="100%",height=UDim.new(1,name=="Visuals" and -200 or -154),scrollbarSize=3,
            slotProps={root={Name="Page_"..name,Visible=A.activePage==name}}},{Cards=cached.element})
    end
    local camera=workspace.CurrentCamera
    local viewport=camera and camera.ViewportSize or Vector2.new(1280,720)
    return e(Prism.ThemeProvider,{theme=A.theme,density="compact"},{
        Window=e(Prism.Window,{title="MM2",width=math.min(760,viewport.X-24),height=math.min(580,viewport.Y-50),
            minWidth=480,minHeight=360,center=true,visible=A.uiVisible,collapsed=A.uiCollapsed,
            onCollapsedChange=function(v) if v then A.window.Visible=false else A.uiCollapsed=false; A.dirty() end end,
            onClose=function() A.window.Visible=false end,
            slotProps={root={Name="QosPrismWindow",BackgroundColor3=palette.bg,BackgroundTransparency=0.64},
                rootCorner={CornerRadius=UDim.new(0,28)},
                shadow={Visible=false},
                rootStroke={Color=Color3.fromRGB(224,241,248),Transparency=0.52},
                title={TextColor3=palette.muted,TextSize=12},titleBar={BackgroundTransparency=1},
                body={BackgroundTransparency=1,ClipsDescendants=true},
                content={BackgroundTransparency=1,Position=UDim2.fromOffset(18,0),Size=UDim2.new(1,-36,1,-22),ClipsDescendants=true},
                resizeHandle={Visible=false}},
        },{
            Sidebar=e(Prism.Box,{width=150,height="100%",bg=palette.bg,bgTransparency=1},{
                Nav=stack(rail,{p=14,gap=8,height="100%"}),
                
            }),
            Main=e(Prism.Box,{position=UDim2.fromOffset(150,0),width=UDim.new(1,-150),height="100%"},content),
        }),
    })
end
function A.renderUI()
    A.reactRoot:render(e(A.PrismApp))
    A.uiRenderedVisible=A.uiVisible
end
-- Static surface decoration: no per-frame work or scene-wide post processing.
A.glassTexture=nil
if type(writefile)=="function" and type(getcustomasset)=="function" then
    local ok,id=pcall(function()
        local hex="89504e470d0a1a0a0000000d4948445200000200000002000806000000f478d4fa000052cb49444154789ced9d89931cc775a72b1b20450c409d5eafbd77ac784a1bfbffff212b1217e5b5bdb675d292080c281298dac84666e2e5ab97599955d5337d7c5f44b3aaebee1a067eefca976eb870fecf175ffac57bc330dc579f7bc330ec9c734e1c2ed70100e0f818d3ca38faf59b6118de0cc3f05a7dbeff5fbff87cb8642e4ed0fecf175f7a617f5f7cde0b221fdf45b60cfaef2efdbd01009c8af0e7fa9fed4b4b8f37028661f82e7efed72f3ef786c2c570f642f6ab2f1ffbc507c330fc207cde93225f137ff57ed2baf89f0a00008e803c589b1903e38c11308aedde20f86bf87cfbcbcf3f1bce99b334007ef5e5631744ff41583a25f6f233c8f5711c2df1cfbe630000009c8c0190be3be7a4d88f6a7d544681ff7c3b0cc3ab600c9c9de7775606c0afbe7c1c45ff81c8df973e1ea7055f7c1facef61db6dfc1c0000586600c46dd93fd6ca0018c277d3105006c14d30045efdf2f3cfbc5170169cbc01f0ab2f1ffb9cfe55f8dc77ceed2aa21f057fe2ed47518fdba4c8630400009caef8c7fd715bf83eaae3466110948c819b504078ed3fbffcfcb393ae19385903e0575f3ef6057c0fbdf0074f5f0b7ffaae843e8abd14fd89f09796000070dc08c12f2d47b56dff5d46049431e0853ffb1e2203de1078f9cbcf3ff3458427c7c91900bffaf2b12fe47be49cfb208a7cf4fa83884f843f887ee6e507d1cf04defa1ed7e51200008e134bf4f5baf5dd89e84030104c43207e0fd180680cf8b4c08b5f7efe992f1e3c19dca90abf08f54bf1cf96dadb8f9f9b9b9b4cf0f5c713d683918711000070a2e2ef0a823fc8cf6eb7d306428a0a44d1d7cb181908c6c0c91902476f007cf1f8891fb6f7a128ecd3c23f310062485f08be5c1f0bc640b65d7ff7246b2040440000e0b8f2ff51ed95c03bebfb4e89fe6ef7b6763cac470320a50c0c43e0c6320442c1e037bff8ec533facf068395a03e08bc74ffcb3fdd07bfd42f893f81b9ebe14ffbd0110c53d2c47f93d1a02719f651ce808806e2a810100007034064026fc62dd1544de4503c06f13eb7a9f34005244c0880cc8944034045e0cc3f0975f7cf6e951e68f8fd200f8e2f193ab20feef298f3f79fd4af09df4f485d0ef455f0b7edc1e8d0229fcca08281a00883f00c071203bb6d60c00e5e13b29f6ca0888dbd239629f4c0d48834046036444e0fb6004f882c1a3e2a80c802f1e3ff13df87fe4c3fdc2e39f08bf5f1761fdbda7afbd7b29fc7ef9e6cd9b24f6c2189051816214c03f1b85800000275703607aff52d477625b14fe7bf7ee65468161206491016f14c448806108c488804f0bfcf9179f7dea87111e054763007cf1f8891fd2f76343f8275e7f10ed24fc5aecfdf2cd9b375afca501902d4b9ebff0fa27c580000070d4068099f7d786c02e17fab49446c0bd7bf7ac633243401804a611200c813ffde2b34f5f0e47c09d1b005f3c7eb20bc27f2573fda1b82f8afe4e86f92de18f822f96a3f1bd28fc8d9e3fb97f008023af055810097052dc83f827e137be9b86804a0fc421837e290d00bfbc0e8680ff7e9906c0178f9f7c10c43fe6faf753f0c6f1fcc2e34f9e7ffc5882efd7c33289bfe1fd6b0320f3f8a3b76f55fee3fd03009ccea8003d224045059c91f34f698028fcd20888df0b06818e08c842c1640cf8a989bd21308ee3f7c108f8f6e20c802f9f3cfd30e4fb6585ff3de5f1a75cbf107d29fe13e197db6424c02afeab097fa9d00f230000e0a45a02ef170d86802ba40192e8ab4fda268d80b8140583292d108c80376aa4c09f3ffff4936f2ec200f8f2c953bff86968e1bbf7f8e32708ffae26fc96e8bf7efd3a137f2bf46f88fe44fc1b4bfc29020000384e8a9a96f202768d80b38c012b15103ff7efdf378d81194320a503445d8037087c4ae0ebcf3ffde4b6ded3dbf7709b37fbf2c9d37b41fc3f2888bf0cf7ef43fe4aec27a2afc55f14ff4dc2fdaab8afe4ea97043ef58e060080e324767f2dec9e160a0c931a0157480b4c2201d1082818037234c1de0090868061047c1b8c805b9b60e8d614edcb274ffde43d3ff3f9fe18ee17e2efc53e2e53a19f147d2df89601a02bfeb5d72fb45e16f3c9d9a1d2f7f482c4ac5100007032a4f95fe436ff1fb1dd19c5836634408e0c2819008641901901a23e40d604eceb028221e0eb02fef8f9a79f7c773606c0974f9e7e10c4df8bfec4f3975ebf08f77b71cf3cfef879f3e6cd8d10feacf04f8abf6ae653f2f2ade9218bf349ebfd000070f7146ab6de797642f4e5faf08e6cdd4a0d88484026f041f0777e193fc248484640480bc8684016090805826f821170f0e2c0832bd9974f9efae17d3ff5e21f2bfde310bf20fc3be5f54f3c7efd91fb75a15f45f8e59ccff1f1e4949099f85b73494b300200008e83b9826d63ba7727be4fd6e5b2640888fa80ccf3d71f1d1150d1809bd04428d606c411026f423ae0fa640d002ffece399ff3b7c43fe5fc85f027f1373e3796f8ebee7e41f5275ebf9ada51cff694d68d63b2f400c20f00709c18825e14fdf15d11783655bc5c1aa901591f901903ca08c8a2012a2a900a044534e0461b0161795023e06006c0e3a7cf92e72fc6f7ef973ae45f11ffbde87ffffdf7c56a7f99e7d7c26f897e6cdd28c55fef8feb7289f803009cbe11a0d7c7dc20a81903992120ea03ccd101efbdf79e690c482340a7048211f046a503befeec938faf4fc600b0c43f7aff51fcdfbc799379fe96e8cbefaad84f86fba5e8eb30ff58137db54f1b0893c8407a69d40000001c751ac0f0eeb5c00fd6f4f186319096e1d24ea50674e320e9f5efc5df32066424e0debd7bba2ee0568c003ff9cea63c7efaec0325fed1fb4f617f39ae3f16fa79a18fa21f9649f8b5f807afbf28fcd2f3b7c4de98dad18a04a4eb45107e0080e3c6e8e922c57d54d3c60fa266ccdabefff87ffb8d4671fbe3836e94cebd11cdedf6dfd594f691bde1e0752df60e90cd8bc671fce9e3a7cf6e3efbe4e36f8fd60078fcf4991feaf73796f8c771fe41fc5dacf2d75efff7df7f7f63e5fd8d0a7f59dc3727f4d9524fe7e8918680fc1e210a00007052de7f5cdf8b75dcaebe7bb269e45b3ff25efe5c31922c4e551f3f3b69088473fcf738d5fd1096a33702e2315a7fc671fc9bc74f9ffdeeb34f3efeeee80c80c74f9fddb386fa45f10fc57e697cbf147f29fcdafb97e21f48f97ee1a59bf333cbe91a8defcdde3fe20f00709a46800af967eba3f878c730d4a645a3407f378d00b95e3022a4f867eb71b6db683844add979b13286a78fe3f8b36004bc391a03e0f1d367436cf22366f3bba7c55f14faedc55f887e0cffa734802cf693f81b05b1cec4de127e3d5f33e17f0080f3477be82d06c0f8ce10c8843c86ff4b868075df78bedc1ec3ff52fcc3b6cc0888510169040843e03d61041c4d04c0e7fc637b5f2ffc32ef9f55fb1b61ff2c0210f7a91efe31cf3f3100446b45594db9ca00104b0a0001004ebf10309bca7d2ebcef44ce3fae0b4320edf3ebfaded290f09a17230941e8a321908c8050f427d301fb678e4680bc7fd0a50f7c4d802f0cbc7303e0f1d3673f74ce3d2c84fed334be6a985f127d1dfef75dfe54d8dfdf261900054fbf6a00e854803600f66fdb3002c4bad51e1800008e8428928258bdafc53f3308c69928803600a421e0d7a5b72f0d90b03f7af5fb4d31bf2fc2ffda1818e40883f03c71bbd4a7878f9f3e7bfdd9271fffe5ce0c8027cf9efb8aff1fc9897d62e85f7bfe35f18fe17fddd25755f767a17e43f48bc25f32005423a05eaf9ff90100008e03d9d37fcfdeed16dbac68c05889089484df6b88d7b628fed208b05203324a10845ed700a46548a1cb1f334907048df29afba327cf9e7ff7e9c71f7d7beb06c09367cffd03fd2476f81315ffa9fa3174e9331bfca8b07f26feb1c84f0cb1182daf5fad2ff5fc4bd5fe93680000001c25e69c2d4288f79a2a8d82318cf58f5a230affe60c8024fa7119afa7c47e7fcdb78efc645f14fb9406f0df55317a160908bf214610f6da358ee34f9e3c7bfedb4f3ffe28bff12d44007e320cc3fb958aff495f7fe1f5cb4aff89f8cb2a7fe1f92703200abefede92fb172f775cd2e6d74a090000c0f1cdfe673974424c07110d30d30251e42d032088ff5ee1b521600d15f4482320e6fea3f887678c86407cf6d47dd04701449a630cdafb7ed0e23fde9a01f0e4d9f3473e07112bfef5587fd5e12f56fc67debf6ef2a3c53ffcf26c0e653daf72147d611024c1b78afe74c8bf24fa883c00c0c95173e2927160fcfbeea2971e04364502ac7cbf3400a4f0476f3dd6ae09832045193c2a122087b3eb28406a04241e32a60252647c1cc7874f9e3dffeba71f7ff4e2e006c09367cffd393f0e0fba177d19fa8f33fbc9617ca2ea3fe5fbe3b4be52f8f5f87e356da2f6f64be29f3a29c9f0bf7a9156511f5e3d00c06518074e79d3933481ec0510f2fe51f0f7df45987ebf5e1a1110b627a3426ef71a18530141536fc275f70ebfb847bc4f6c43bc8f184443601cc71f3f79f6fcdb4f3ffee8f5a123005efcd3ec7eb2e25f4ceb2bc53f0defab35f9b1aafc95a75f34006a61fff0578d7f5d9910927ff85ed21f120000ee96e82c2f34089ca83793d78986405640588a04585101bff4daa40b10751420fc861401089a96d20171e2a1b07d1f09902defc3f0fb1f0fc3f0878319004f9e3df761ff2b29fecafbaf4df0a3853f79ff85217ea601e0274d302202d268300bfdc2327be13320f2000027801ceeb7c03818d531134320e4e0b33441705cd33d4ae9075500181bfec8d482af838b79ff28fcb107c0deeb1751ed18a5d84709c235bd43eeaf79e535fad38f3f7ab9b901f0e4d973ffe03f8a33fb1979ffd4e6377cb2c97c6ab3f9899768897e97f7bf46f8517c0080f3360e26e305df91e5de556a60325220ecb08c019922c8a201fb8b8a7908c2f6fdf1de69f69ae6ebe694137c131b028974c0be3f40b85f2c081cc3d0c0eb4f3ffe68dcd40070ce79f14fad7e2dcfdfa8fccf3c7fd1e14f6b7f29e49f89bde5fd0bab295ea757f867759f703f00c06951f1c8a53e38eb90b0df8a08ec3df2306b5f0ae9c7ebc9b482a53b72a480984170ef10eb3440107e1f498ff500934880aa07f0cbf782a3fea7cd0c80a7cfbff217fd508bbfbfb9177f51d0208bfeb271ff6a463f1dfa2f8a7f982f796210c86640bad25ffc71e51f2fff0b57541dc10700386d2a4302e5fe31ec2b190232e49e06f5c7bcbe88045829811623204b11441df597f3aa6f15c24743c06b6f983d301a017bc3611cc70f9f3effeae5271ffdfcfbad22003f94e21f3b19c9691465e19f3604ac897d640563aff8cbfeffd6303ff1c76bd6fe16d1c7300000386e6ab9f8d231e3bb0641fae4cc40884302acda8082d75f3502e4b3f98f8fa0474df3da1975cf6ba7d0bf983688e9845810982201e338feb0a537c0ac01f0f4f9573ff063fe75c39fe8fdebd0bfa8fcbf31c43faa6fe6fd1b023fcc897f8c02843f8e1ee231b6087f4dd0117b0080d3c3fab7bbe0fd67fb6244a06208243b206c8b01819812a81901f23ab51903f743e8e368b66004ec53013ee5209731cae0b5528c0a88f5000f9f3effeac5271ffdfcafc3ca08c0defb17d3fceeacd07f8c00a86aff2ce72f26f7492f3e0abef8a45c7f4bd15f83d7df2cfc883e00c0f931e3fd0f8d8640d62f201a05a167cd9c11906e2fbfe889844267c1a4ab5efc630d402c06f4fa182205592a404402f6d1801005f8fd6203e0e9f3affc643f0f8cb07f14fffd8f56d5ff938f1eeb2f3dff99e23fb3e1cf96e2df23fa18080000c74da51b60d51818d56c82a23740311a205202ba28706204686f3f3ac03a12107b0c040360af7d5a5383c1914610c49a3c35bdf003afe19f7cf4f36f974600f6857f22ffef54f57fabf867a1ff4aa31f331db085f8f70a3f620f00709e298019ef7f90df7b8c805813106f2b8e2dce0da0ef1d9d6b3934d0300064d42136328af309a49a005f10380c43bf01f0f4f957ef3be71ea8e2bf6cccbf55fca7c7fb1b63fd65e8df2afc9b08bf51ed2fffc2e3565e7f87e8b7870d0000e036704b520015efbf25253049072823409e3316b466afa792289b7a745d08ff27ad8c5a2c660e8c46401c16e8a300ef7ff2d1cfbf1b7a0c00e7dc87aaea3f85fee54c492aff3ff1fcadd0bfecdaa76b0062f18312fe45e2bf81f023f40000a74153de5d7bf92ba301e9bbd8970c03690878fd0c350299b72f8bd88d54406aad1f8b02bdf00b4320d3e4980a0856491c1af8616944409a5b58f2ecab5fefab082def5fe4ff536ebf14fa97732b4bf157025f4c0188befe07117f398e535d377e0000e0b431ff4d1fed7fffabda5168392c23dcb2395dd2b082be4dbe8bc97de2f3553556f4d5895d0a93f007f1f7cb8741d3db0c8061181e899cfffe23bdff52f85f3e90f6fead09134a2f43ee97c7cb97dc2afed61f7946f80100e03c69320446b56dce08d013cd591a5611fe8936c6e7945a6a39dc62ff240a203ebba0e9cd2900effd274b220efd1333fe45f19f1400aa4e7f836ef8a37ebc350cd06cf4135f78aff84ffefab6f00300c0e53086a52bd501e86dc67a960e10d5f85951a068551f9b090d6a991509aae7d85fb4d46ccf6bb0ae0508d74885803e8b308ea3efe5f3e7d908c0b3af7eed87fdbd27c2079308807c20eba1e23185e2bfc96c7f7a48a0ccfbcb3f56fc2e2edb2cfe869587c70f0070d98cba38af210520d7334db2344bd5b115b54f4603c43d9294565200a968504700441affbda0edb329003fdd6f2c22d0e22f3bff25f1d73dfe45c39f62e19f2e0094db6766f4b3ff8a7df97fbc7e0000884cd202a5ef73a3c52cedead4be14358f4eaed456e9788b654c0338c308887a7e5535009e7df5eb7850d6f73ffe68510390ddb832e65fe736ac7cff64dd3002d21fc8f2fe3bc41faf1f00009aa201d94e4367ac2840ac7933c4bf45fbacbab7d14a0348475c1402cae7c80a02bdb6078d2f4600bcf79f42ffa2ea3f7e264509c60364159131022066f193968ff9a38d663f5b893f0000408d2d8d80c9a4758633ac230359dd9cb85f8a0618d1f71425d0ba1d530141d7af6a06406afb2b4701a859ffe20348eb2345068411508d00889efe59e843beeb42d8bf69363fc41f00000e6904cc0c0fcca2d7e17be6f08a796d66230052636534406ab2180da04701c4e503d30078feeb7f1842e7bf6c08816efea3f3103aff5ff8b1c51f5d3004b21f2f5e7046291783f80300c0a18c80c88c2e6927b84703652d80b8745d7f9556675a1e78e0b5de8a003c3072ff7bf18f3f4a4500b254806efa63450054bec37a11138b69fa6eeba17fc41f00000e69048c33a900eb3ac668804c03adbe00e21926cd818c1e0193d905551460a7a300d200f8400efb13e2af87ff4d6e3a23fca50880ac7ccc84bfe0fd9b2fb6529149ce1f0000d632f66a8f150588df95536c69e144332d43c072c695239e345c0d0bf4b3fc4e0d00d14338150f48f1afa500e4b07f51fc500c79e8e10ec6d8ffe20b6f08c720fe0000b015638bf6d48608ea2877490fb53120ebe15a34d83002e4fc006e62003cfff53ff83ec1efabf68156fbdf34cc4f341f90378b2fcaaaead73fccf4fef50b37d6272f7deec50300006cc1d8a63b35fd32dbff9652e2421f931122843ed3641d9537da02fbcffb41f35304e007baf98f7858ab0850df4836fe797b521ecaa8163818398fc90b2e2d675e3c0000c0168ce6c60e8dd25a572a94d7fa99dfee9de66ac75cf502c8745c3505fa416600185642a9fa5fe61adec5fd55f57fa916404601c4b1fa05778938a17f0000b8eb544085924e56bdff788ea59352834b7500ba06407caa06400a1d2823200b3bc808807cd0921553f99863fe6354a1c3fb070000b855465ba3cc9e3585c64096264eb454897f1a99a7d3f1460dc0601a00614ce0fb7afcbffa3199a5210d015978d0f22355f143f60ed7bc7842ff000070c4518088992a2fd4064c9c6355ec9734d88acc8b67ccfa01843a80fd8c7fefe9e17f7a8a44fd29f41d4ecce5339431a073ff66f1045e3f00001c3b63b905bd16fefdb616cfdf1a1d57d364439b7553a0bdf6ef42f57f7640ac1ed4430a8c7186d60fcb7ea49516d0fb3b5e66a902939c000000dc5914606c6819acafa1f5b034fc2fec2f3ac7b24ecf18ba3fe907104e7d7f3f4fb051fd3f49c8abfc825504981e4a872f54d15fb1e2bff3e50100001c3563c3f4c1258d2cb5c60fd79d48b1958e8fb711cb9806d84700de534d0252fedf6a02540a31140a164a850dd93e61e9cc8efd6f7da900000087666cf0f4e5ba95fe2e0d05ac696bbc778b56077443a0bd01703f8a7ea9125f5e44d617547e7ca9f82f1d50ebf8673d43ed5eadd7010000d88871b261c148b542da7ca29fa57bc9de00717ba53e2fad7aed8f06c050ea03202e2873ffbaf2df6ce8a3c631a66d3a9c514a07e0e50300c0a932160c014b03956e66da68a4ceb3e1804293e5b65a1f80211a00be1a7052f56ffd80425861f29bd583170b00e7ea00000000ce1557d0459d469feb4468e5ffb58eab94bdbfe82e8a7fb1074058cfaeabef2fd7addc85fec173cc79fe44060000e0581837d02c4b2bad7a3979597d9b78af8221a08702eec7ff373ff45c6ec118e237cca40664fea35a0048fe1f00008e8c71b261be566d2ce4fecd51722d91f39236cf191eba0150ba8fb840a9a7a1f9bda1c94f57d11ede3e00009c1ae3b2f902aacd82c471fabc6146b3b5beef3f3a0260c6e7e50880c2034cb01afed42a1a0100002e94b13262aee9fcfd7fc4488002ce8a00140f28decd9efe377be0da8fa0001000002e1d57d1464b537554bd23d230d1fa9db8707349bebf61e9810a3f266f4a6c180800000097842b6b61b5805e3bdc9d7d0752df9f9d16ff16516e38664908030000e0e2719d73e6f4ea76d4fca61a80a510f6070000381acd9cd400940e92e305dbaedc10da271a00000090d3a29b9d5a6c75ff1b660d80d24d3a8a152629858d520b0000002789ebd04175ac5b535c5fda1ee701304f2835ef69b9300000006c4fad957eada9502d02908a035b6e3c77acb65e6ad704000080446b61be6b117a79acbcb6d507a07a818e63e55d979c0600007071b8e59ad9a5e7d5b900baee6a5820b51005bd000000e05271e5e63e9363e4f72d1dea5d4705e2643440a928a1f70189100000c0a5e0166864ad43a0da5e1db927f7ed3b018aa34b273689ffdccd107a000080f57a396704148e4f1642ea0458ba7ee9e22d8d016802040000d0c712ed8c825e38af7881521f805459b83544040000008683eba11821d0de08489e5f1b8ed09afb27f40f0000d0464b01bd759c31fcbe6a555806402977601e673dd0da0a7f0c0600003817dc4a2dace96caf66170d809e3ec32b459ac6000000006f593ef0bf438ff5715927c096130f35c40faf1f0000ce1d77204decd0e8ac13e0560fa1672ea8ee07000080c368698b764f0c809e99867a1a00d1fd0f0000a02cd63d3aba44a3e73a01b64e40507de0c6718bb3c70000009c336e815ef638d47a6480ee04683510280eff6bb150f4fa1ab1c75000008053c36da07bad7d0266220313918fbd016204a0bbb3df5210740000803bd558d7da08482e9b6fd4d22e1800000086455a5adba59626f72b27ea1bc4e728361db01e66c95086711cbbce0100003866dc0643e867ae916974cbe88196464055efbff32127ad0909140000c0a5e16c816e8eb637d4d8cd7608dcf53e604f1120000000aca7b108b0cbc16eea04b8b4f5ef5c0523c60200005c2a6e461797eaee5caa60b611d09663f9b7180e08000070ceb84eadecd169eb585d04582a1ee8b6567ac49ec23f0000b8145ca73eceadcf5d5716f3d73a01ca838ac6404f4a80d03f0000c06174b2a4c74af4cdc67eb39301f53ed49a22415204000070aeb815dad8d9f2b709df0ad8f2fe0f0e620f0000978ebbbddab82c0ae03fbb99b187ae21c4504d156cf6e414100200c091e30eac7b4673bec97e51f8577a98bdee77a700f44334deacab59010000c099e396b6d857babbf8015a3a01a6075d3a4410ef1d0000a08d5efd34b4b9c9b82836022a5d684d112086000000804d4d3b171401cece096036026ab53eb66c16442a0000002e00d774d04a7dd53a6e1dab0d00d73a89c0928705000080e52cd46253db6b4580ba71803c31d5fbd58a1196763b221a0000006784db40174bc5f7d9f58d7afce20d4b9d00ab0fb3556882a80100005c2aae410b0fa9cdbb5e4ba533fc309b4aa0332000009c23ae43d86742f78b42ff737a3cd707a07ac7d66aff9eb9030000002e1567e8e58a9175aeb715701773a107841f0000a08f394d5dabdbb115f0fefbdc4d74a1813554b027448161000000978eebd0454b6b7598bfa0dd934b3577026cbc60f13c000000e8a3576b7b23f27132a0fdbec241b679d1f820000000b08c8e08bb3e604ed3279301a5b9064a17b21eac757b098c050000b814dc461a59b98e6bd1f6fbf57bba71feb9668f010000800da834002a1d3bdf0868c14334b70bc6c307000068a3474be7d2f235aa8d80e40d6b2d7f5bcf6f38170000e0e270f35a598ef7b7e974b91150cfac42adac890860280000c0a9e356e8dd52bd6dd5f3620aa023bf30d946e73f000080f5d434b5a51360ed985a11e0e442a5876bbe00e17f000080a2468e63bdaebe219dde2cca6b8a009bb66d756d00008053c41d501bd75c3bce0530dbec6726bfb0e809107a0000b854dc72f1368bed4bd7b4345ece0590b6d51e4ee7215a8b1b7aac168c020000b8f0a17d436ff1a0758ef1dd6f70c5148038c1494ba195928180e0030000b46be29a117842b8a39637150136dda55688b07414404b01040000c029e216eaa2d4c615bd75cc3e009b55dc151e848a3e0000803e9abbed2e64321950d383ac790872fc000000391beb6ad3c59a1b0115460b743fe8ccfd000000ce167740dd346af6aa357cbbad1fbea50521620f0000d0ae8d6bb4b744d35c00b59bcdb5293c445b600c0800003816dc0134ae5557976a772d02900d1b68bd81360a00000060394bc4de38de3c311a00c5f1825bb51ec420000000a8b395be16743cd3faac13a03e7fc94d010000e0f0346a7051db7746e8be38eb9f0845ccddb5cb32c0900000804bc1f53bcfb39a3b5773274708c4e5fd8607c9420673f50188390000c0b6c46e80954e80a656d7aeb7783ae0b90bab07338fc1580000804bc5cde8e0a187cecf3502eada67151dcccd5604000070e9b8c26cbb6b27d55bd308a8388bd0dc85971c07000070e9b895da3a37fcaf693220abe80f31070000382eac16c0337a5d9c0ca8381240af97c2162de70200005c3a6e8186f6a408e61a01550f9ab970d3feadcf0300003855dc813473ceeb2fcd0590860ecc8df52fb70a60b21f0000802d51daea7a455f9e277bfde856c08b1e6a83c641000000d0d8d8271c342c64d20af81037697a080000800bc41de4a28d9abd6b38311b016075213a547d400318100000705102eedab4580f0b985c673217c0cc03ccd6051c285c01000070d6b8f55d01abf501fa1ad51480357980f1005d3d02961801180e0000702ab803e95c8bf6aa8840bd1150afa7dff2c0d676441c0000a04e8f7e76e8aa5b3b1950974973c0ea45000080b3c06d3f695ef309b54640d56e806960e10aa1c7080000804bc5add04e4b8b4b8717d6cd0880152a701b1528341f0300007009b80edd6cd461eb20579b0ca8b998af51c00f5e1c080000704ab815c57e4baf59b85e7132a0a61be86d4b5b01d342180000ce1db7b146ae2db89f6d058c670e0000705ab4f40b909301f59c9c1dd76a85604c000000d8f468698f4697becf3502da2fac93f53e041f0000603b1a74b5360bef5c1fa0e25c0093c240635fd3035bfd8a7bce07000038755ca3f6f5e4fba797981a01957db901d0da6d68e10356fb0a0000005c0aae6ddcfea65aacb77737026a0151070000d886959a5a6f04d432e6b0d1a2c0cb07000038707460c1fc009373ef2f1c8f98e5132800040000d81eafafe33866dff5fe96823febbabbadbdf739c360ed3e00008053c26da0856bb458efaa0e032c55126e50a5d8751c0000c0b9e3568ee93734d91cbeafe99d0eb85bb9d7583000000097825baf975d3abd2b9cb0cf272c9dc487ce8000000077ab9f42c7271aef3f2d1100d318b82dcf9ea80100009c1aee9674d1d2e696a67d9e3903c0ea2d38fb408dc7910f0000804bc76dacad936b97d09301c974407337a2b97d4b2c213c7f00003875dc46fab762e49cd4f46cb8e06ecd4d7abf030000401b5b6aeeec5c00ad27f5ecd787f71c0c00007041b8e60337d0e6ac11508f98cf1521f43c44cb3d0000004e09b791fe6da5b1ba38b0a70f40cb85279bb7ba3e0000c085e10ee9183719007218e0da8e4500000060b3b6c36e6b0f9fd26c8029173037dca032feb0fb3c0000804bc0cdb4f42d9dd37b9ed86fb6065e9d025822f8d63e8c00000038775c83f6b51a046bd9953a06a9ed7311815b71e131120000e05871b714cd2e69aed168af72e8dbe980e55eab11d0dc8d26379eb15ae43d0000002e1d57134ee99077a4d02d2dcff4be7736c06ef0da0100006e4d3b9b4fec6e04b437531a7217000000b00d73b502a542bf1acd1180968bf53627c0580000804bc5ddb1ae669d004b27d766f0eb19733807060100009c2b6e43adac35df6bd5713d1be0e480c2050e62b90000005c32ee303a2babf48783b6025ed2e4000000e092710dcdf20ed60ab8657841eb703f000000381cb5e181d636fddd8a00ccaa7aaded2046010000c0b6d4f4b5517727076903205912ad0d7b7ae70be87858000080b3c72d6807dc2afa72e8bed6f46800740bfdc639092c020000b814dca16bee5aeedfd208284502e6860336dd958240000080459ad838fcafda5ab83a1d70e30d678f27d40f0000b08ca55adaaae97a32a0ae0b23f000000077c34a3d76713ae0fd17b963c94d4b558a3da303302a0000e0dc701d1ad8a2a39de23fd1f7381df06a7adb07d72eb5c5f30000001c21aef7d8438ea4ab1a00b5f6c04b3c7a86040200000cb37ab8226a6eb6fdb5686e04b475a1e056e70200009c12ee807ad9321f40b111900add57bd7ed986b07411000000584e4153279b0bd100994a301b01d56ebcb810e190510300008053c6756a644f017e8bbe96a603ee9e62b0e7a6000000d04ead0150edd89ab69bad806bc57f2d379863e9c40500000027869b3d608586b638e8a542c1ea74c0b50b1a0f54342264788208010000408ed4c8190fbe26d4cd3d7c6a35006e8b9101adc7f41c07000070aab80d35b1233d6f1eb8ebb11c4a55ff1d0f050000001d744cfddb15c96fee03507a989e5a00e6110000001836d5d0a57575ab2603dae8a10000006085b62e9a0c486fc8af57bee021c51dc3010000ce0577477a69a4eda78d80e60a0996142320e2000000eb58a2ad7393f1c5fddd9d007b1f04000000b667ad3ef74c07dc3c149068000000c0325a34b4a7436f895deb043ff286a587ab3d24d1020000803a4bf4b44167cd8983cc56c0ea42591dc0da097e3004e619c7b1e1280080d3807fd3e6d94a5b4bdaad0fef6a04b46588a2773b0000c0a9e336d0c40d52ecf54640b7d9be17d10700804bc3dda27e9652fbb522c0e2d8c1050f668622107f0000b8545c5913dd4a43a149bf773dc57fbdfb000000607b16ea7216e1af4e075cca05cc552062140000006cc39cc6566a08dc92e980cd13e44c430d450b29eccfc800000080b7b4686263357fa6c9bd73f1344f0664e5f42bfb7baf0700007071b86db47349cdc06432a0c9c56adb99fe170000e0eea7078e9b4a87ae6d056c5e104f1e0000e076999bf0a785160360f6e22207b176e8c2e49a000000a78adb500ba3c6365e73f620d90ad8f50afed2fd000000d0c6469a2b357ed20a585fb07ac5059311f43c280000c0c5e0fa7bfdb79e576f0434974b781775e81f66d0f3a0000000978a5ba1a9429f6b9a9fa510760b1e60d5a4418df7000000b808dc363ad915b56f29024c39832533f8f57406c42800008073c775e8e19276bfaaad7ff566bb82e5d1dcc5aff4b0083a0000c03a2c5d6dd5656b849edcbfa80fc09242bfdb9c62180000e098702b34f050c5f58b1b012d1d05000000007d2c1d05d06b00341712d0ec070000e0289a04cd1ebe7832a0d20d54c1010000001c16b330bfd3a078371990bf5a61c6bfb99e408b2065000000978a3b60dabc34122014063aab157076e056b9892d262cb0ae0d0000706cb8f55a551c85b781d190697d7311606feebf34740121070000a80edbcbb6cfb1b436afb51150f586f23b220f00007078e3c0faae4f5d620034e5fdf1e6010000ee860e9d360f9c4d01e8c2c0a5631097842830300000e05471b7a88f5ae85baeb35b23fe0d376af925ab0a0f010000ee0ab7be20affb98c67900669fadb511903be48b40cc0100e0527087d7ca261d5f321d7036ef70ed26083b0000c0320abd79d4217d93f6950c0027c71ff60ab91e0540a31f00008065acd1d44afa3ee97c3200965a0f5b17f3113100008073c5dd8266f6e8794b23206d4a74df0c000000b6a3418b67c5394e06a40fec9b510023000000e05658a0b996c6bbddc22e42727b73ad005d0201000096e963a528b045ab27d76a9e0b40debc364941cfb5881c0000c0a5e216e8606dd2bdde6bcdf601a8e5157a0a10107b0000803a3d1a5a1b26d85213b05b2bd2a587c2c3070000584e4d4bb7d0ebdda1abfbd73e24910300003835dc4a1d3b9406cbef3a05901515583f60a525221b0df59e0b00007016385b0717b7ddb734dae8d8eb6a9d004b375b3517c05a91c74800008053c11d48f33a1a04d50ecc3b012e61eb9401220f0000e78edb582bd75caf640058218364546c940e000000808dc2fe2ae43fdb27602e0250eb1038c9e7d71e14000000fa99d1d99ad057c5381a00ab14bb361470ee3800000018aa4d7e36d65227e70290176eadf9ebbb1be20f000050e550fa6b08bbdb6df9702d960a8600000040bf56f6eaef1cbbad86231c246c0000000045ad5d3364b0da08a874b18689073006000000b6c1d4d44af39fd2b9d346409d531056f759372738000000d086d1c1af2b9ddeaae9a54e80556b636e7b8be0d30e1800002e11d7d90ebf55631ba3f2f39d00d7cee687d70f0000b08eb53a5c3bbf7514c0a2b9000a379e7414040000b8349cddc16fb2bff4bd76e9968376331774a53cc446c3fb667f300000c0a9e30a0ef1daeb541cea897eebf3ac0840bb89b1207701000000b7aeafaeda0ab863aac145c509180300000043b74ed6b4768176a756c0ad27564309b5ef000000b08cce2180cd029c0c00a308a1949f47dd0100008e8b92f6bbd23193c9808c2bf6dcbd6b1d00000086cdf5b3e1d8e264404dbd86e78ea14810000060ca2debaa7992d909b0a5c520457d0000007787d4e18ed6c0f39d004bd709172b1a0b8d218aae56c3000000a78e5b3181decc2880f8a54b44773355048b3a00b6ee0300008083e9aa74d68b7d0036654d14a0f31a000000478b6b28c6dbe01a8ba81a0062d8dfea48000000002ca7d3f39f6d09509d0d507fef0949cc9d8fb1000000978e53bad8a2a5b56bf51c9fb5029e6b043477a356107f000080b7acd1d2ce1443a6f5dd3500bdd6c8dc312dd701000038075c871eae89bab7d0d408a8e7c67ab2815b00cb0100006e1b779bf75932099fbe465323207de14379e778fd000070a9b8036a6b4bcf81ddca877007b0540000002e0ab72cb2be4850e3f5ee775c9071fb00000077c4ca1e3b13ad9f2b0274732186d203957a0f371c0b000070b6b88e9c7d4d631b52f4d59dbbdbea630c0000009bb0c97c3abb4abe3e1b2f589b0570eb798c0100002e11b7404f0bb3024efafbe86be808002a0d0000709eb8d914c06c03e1de3b7634046abd160000c0b1e036d4b7ad75aea4e9bbdafe99a63eae2104010000002ba8a5e06bfa5cd1f565ad80e5455a9a04addd0f0000706eb80db4736da33eab13a09b8904b40d44ece8610c000070a9b86df432e973e19c89c64f22004bc2f84b04bd318c010000704eb803e8e7ecb1d639b38d80acb98a0feddd132100008073c11d58172d6d96b9fe128b6b00e4bd6b0fd5b20d0000e09271fd7ab95a4cefb75e9c623e000080bba3c581ee49afefd4ce2e8ba2711e80eab1000000d0af9f0b7435d3fb520ac0320acc88c0428b040000000c7a74b5e2f1cf3af75bd4002c16780c030000b854dc1d6be7260640cd2a614220000080792cbd3c6487ddd40a583ec3dc4978ee000000c741a3264f745e8e02a85d2175172a8d2ddcca28f0d719c771936b0100005c402f00a7fa00ccea79730aa0b302d19c7bb8032a060100e0dc70dd27e41adaec78b76aef6ee622b34d7e16cc2208000000f3cccdea37d721d0f6d2c3e6dd168d80b60cff1fe2ba000000b78d3b90a675ea71b511d0e44069351c428469140400009788bba546796a4481d9cf6777a82285d2a40478f500000039b9df5d1e0eb8067d8d9622c05515ff8d798ae6eb0100009c32ae410f97e8acde3c77deaeb7c2bf76fc060f0c00007031b84edd9cd1ecae91027a3220f3024b1e060000000ec302fd9d68fd6e6907c05a8bdf52080363010000c06689962e68b73f69049442fbb72dd2180500007069b83bd25a992a982b02ec9a2300000000ee9466dd6e6a04a42affaa17bcab48020000c0b9e1da35b55bb3e56440f240bfcc66e499cb3320f800000087a365d45e6548e0586d04b4e4615a841fe3000000a08d565d5dabadbb0d3bfd558fefdd07000070ceb80db4734ddadd3200b279003a2e5a9d3f00b1070000a8d3a09f6d63fda6fa3d39afab1570af886f20fa84080000e05471ab4e5ea7b9f3ad80173c53cf0398fb8906000000b4ebe22174b3ab13600d441d0000e0b06c19595f14019045078562c0e2a441000000d086ecdca7f5766ddf9d381990352190b55d1fd30546010000c0a61a39a7d3458ddfad9909d0b24a000000e070ac88b6cf3702b242fb3da1069a03010000ccb3b5a6d6f45bd35a03b0d8c5a7ea1f0000e05675b3e9e45de7d841b755874000000018b6ecf8d7a4dff11a3da300cc5c43e3240418030000001df9fdcabe5ac7c066cf3b33005a3df66809e0e1030000dc0d222ad0dc1e78712be0d68b96b62d186500000070b2b81555faa5f35bf57e7527c096f987010000e0f659a0d1b39d00f74d0296b6f3eb398d510200007049b8ce2affa50e77d0f06253bf9d1e0170e80909881c000000dcaeb6ea0241ff7db755effe96210ab56348350000c0b9e03a42f36bf573c17339391740b6bf7673bdad362c21ee47dc010000726ada6869674b87bf96dc7ffcded407602e4d40581f0000e0762868f0a4d1cf1c5dd3011fba680143020000ce1577605decbdfee2b900106b000080bb654dcf9dae08402b2b1a17741f0b000070ccb895fa77284ddca413e016a308c48536b90e0000c0b1e0b6d5c8265d5eda09b0d83860ae00b0633e81a6e3000000ce15b750333bb457eb79b113a0ae22344f2a1db35918000000003294c69624b7768cdbbc0600dd070000b81db6d25ccb00686a07dcf000fbeb601c000000f421f4b32ab62d3a5bba4e6a053c73624fe141769e5e0700008083e86772e067ce4bad807baedc73b8793ec6000000c0f6fa78a846405d3746e40100008e5b5fadc98026379a9bb0a0f41d000000d6d3a3b7ad69805204a0b90f40c34d5a8ec76a0000804bc16daca13d7d00661b016d8e7838c41e000020e76da5fde1a3e8f38d80d4b689b542a81f0000e06e29e871c9eb9f3602aae40b569922180900000077a6a166aa212ecd46408bee52e84b3cd73f00230100002e0d3753a05772cc576866b111d0e28baf290a44fc0100e052712bb4720baddeadc933680ba5541bc054c1000070eeb86da7fc9d6cb334b7744c0bb3ad804bcfd7797cfd62f40e0000800bc16daf798b347cb762880205820000004750e8b7449b7795f9844b6312178f55c4d3070000b059a9aba5e642e69040bf7fb7e4c66b841cc3010000ce1977cb0ef252fdd69d00ddd2c907f0ee0100000e4baf1eabe3339db72603722d3d846b0f132b119921100000a01d6bc29f85a3ebb47e4fb47eb76557a1da50c1d90b3312000000ce1cb750135b8601f616e7b71a003d1765b21f0000806dd95c87772be6125e0cde3e0000c0702b5a5bba7e570ac00841343d35820f0000d0468766667306f46a6dc90030c70c2e783800000038200dfaec7a5b017779f73d3705000080598ace784f94a0b4ad771480f9204b4e5d735f00008033c22d3a696534fefe560f318ea3f9307e3b0000006c23f05b39dfba13e0e4802d997be8da7eea0e0000e0d8712b74ecc03a37d1f8b91440ad8b50db1d2918040000e862232fbf7a915dcf3083352ce92d80f1000000a78a5ba0771beaedec85765be52098e50f0000a09d2d74734d9d80351950f5c65b4df283770f0000978edb40436b9306d52ed1da08c81ee4dfd81590e23e0000804d7431ebfe573a66e6fb9ecc0030e60dee62492b427a020000c005e26e415fb3fbe8f3279d00b71877b8e24101000060a19e366ab8d909d06fdc4cb931020000008e424327fabe2be5f00f29ded4040000c025e1eea8d19d71ed5443d0d308287e7f6b2da8228486b0435351020000c005e1acef739a6a68af15c15fde08e8b642f8a40a0000e0527047a2ad8b66032c592008390000c061d85a7b5bfa006c521bc0c800000080c3e8a495eb2fac17a7036ebdc15cd31f37b6cd03ec0f66be600000b8445cd341f35641b56ea0c4ce0a21e85101b7dde79f540200009c0bee96f5508ff9b7daf7fb654f0dc0f2b90917cc1d8011000000a78e5ba0792bf5aff9643d1950a911903590d05c5ac7000000401f355d9d29002ce978a6f79356c0733703000080e3a451b327ad80174dfed3714300000058c8469a9b4eeaed0468dd746edec2b627c27800008033c76da7892d85facb3b01ce3c548b71000000002b9913f925dadbd208a89b9607d9a23110c6060000dc156e030d6bd5cb95b8a51180963b174709000000c0323aaafcbb8fd92d15f58e6284497802e3000000e02d057daca6d92b4dfc26a70c5b4e06547aa0b9ed083f0000c0b04a33b7d2526d00941a01ad7a08841f0000e04eb575a2ef9b4400163ecce2730000004e1977047ab95b32bd60ed2110740000806d69d45d3d0b50f59ab215b075e2e2f18500000070fb4883a0e0c8a756c04dc309e2555a8a126a558918130000003935ad6c1945274605b4d6f2a5c980f44556170222f4000000ebd84863ad48c0a222c0dab87e7205000000876153fdddcd4df2739b057f440d0000e05c71b7a8999661a08fb722006ec18c43e67e041d00006019bd9a3a3353efe4e4fb7307c0dd308e23af1e0000b6c4d50c80b62b54720e7e5f102fbf6f94c797448d4801ef0300e0527033a1fb8e74fcaaa1fabbad041811070000382c5beaf56eed0dac632bc31648310000007468648fceb69eaf0d0067ac17a7046e9dde973e01000000db69a4a5bf3353015bfa9eb502ee66e91041020100000077a6a5a91570dbd1f5e1056b1f060000002a5434b679b8bea43617407536812dc0600000804bc51dc869569a5dd4f8964640bd3736d7010000e0cef47472819d2a20702da1853515891805000000db6968419b4d3d97c7f64c06644e31b876780200000094e9d0d9d6a980f7540d00bc7a000080e3622b6d5e321d70ba70cf43341e4be8000000ce157747daba6d23a0d2c3b41c5783f40100009c1b6e034d5cd013a0a91150ef459be99d4278ebfb030000dc36ee8eb5afe5fca20170db7dfb117a00003877dc2d3bb5352db75a01af6a0b4c0b600000807e5af4736dfb5fb9bea8087041ae9f383e0000c086c582d67a0fda00d86452a00d2c150000808bc615b474a32840730440a611e6ee8cea0300006c4b93f656bafa764d0634b9a90a394c6a0bf0f80100000e83a5b99977de306bafdc5f8a00e457d938948fa1000000706b1a6bde6077a807617c3f0000c07168a5759d5defb081d2c3b4ce1488f70f0000d0a79373c5f5853abdaaf5e00d80b1b0af3a35b0bc696d2a61e3a167a7179e6b42841101000027e4c53beb782b67aff6157575a6f5efdc36cfd8320a6032bda0fa31ee50165087d033f20000006e0bd77490d2b18d9d57e94cbb25d302470360ec0825242b45dcd434105a460934bc90dbee4a0c0000b09896a1782d7a28a20196c0ebd178c5897f8c7b8d3a05305a8640b87a0c3954fb01cc45ee0bebfa87d6ae0100007072b8bac63545d56be72a8d0eaba6f027cdcf22003363086348c1758e3b9ce43eb431211e78724dbd0d030100008e0d57d1aa9ad6452d6c1cba57eccb2335bae19c2c0230f1fec58951a9b38f302fb287b742169542c1ec1afa656e9442000000d814d718c22fe898d455b57b523730290e545ebea9cf953a80a4f9bb711c93f087756908e88b56df875a663f56bf9c9275b442f8b1040000e0d0b8a586402d3aa0d62dbd3535d6b86f291a306abdf71180d75614603a6a2179ea99753153ec6086300c4b661239a884450000008e1a27d2dd339e7cad68b0a8ad52ec55443e137ea5a152eb5f7b03e0db61186e8c14c024ac20e60e90050693dcbdfaa199d562fdd0863cbf9966000000b86b9c119e2fed97cbfc90779aadb759c683d04553a30b51802168bdd7fc6ffdc17f151bac9100dafbdf19f9052b1230a901903f427bf885e288494a6026dc826500000087c235e890a95f158dcb84de887c67ba6a38d6136d2e0c011895d6ffd59ff04ae4fe752a205915fee2ba1e40ddc40a734c0c03f550d9c39644bfe585030000dc26ae33ffaf745387ea4da1d75100a9b532122ff4d46bb5d4eb41ebbbc76bbf3fe895b708821190a5028c8282bd85a16fa0c313854840f6432b1652a90ea0db40000000d8123723f04aab2cc7d8340ae425d532ad2b8dcc1cf4b06de2a80b46a5f57b03e0a59102d0118024fef10699db9e3fd024d4a122066983167f9d1aa8097ee98f411a0000000e809bd19eb4bdf0296a9ef89e45cd0b5aaa2300a64657220051eb5ffa03af87617813369ac580e226d1d288918024ec859794fd08713db93f33264ac2df520f402d000000dc56eedf15f2fefabb0effeb14c08c464ed6a5f6c6a87c8cccabeb4ba2f8df04cdbfde7df8f0caef7851a801884f122f2c2d0b1d6a30020266ce5f3c7f55e88bd79a33040000000e8533845f6b948e7ccf84ffcd5479e15ad278c8b458a4e7633420a2f5fd85d7fed80af8851105f09fc98d8c08c0aef00332e13784bd16ee9f8d04587f08f51dab0000006ecdfbf7f4689a726aa5a150ab09c8b45747000cdd1e0defdf6b7e3200be19c771bf332e8d8e80c9b290864021849fd505881f340971e893d58b9a58502d51008c0000003884f8bb8af73fa75d13a133c2ffb9f33f298897e76ae1971fedfd276d0fcb6fa401f01743fc5314405a18ceb97b4698213d90b656e48f3342fb6ece62daed76a5fd6674000000e010b8ba979f7d84764923c04a1964c6c2bb5b4da2d999d686a574c8f7daaca2f259f19fd0f8bf2403e0c38757dfcd1403ca5c834c036437d3d68a91cfb06a00ac4240275f5e589f4401ac3f8cf11dab000000baf57e9809fd4b7d93fa24354bac6bef3dd340792975692baa2e9d721d05d0058093e2bfa0f92902e0f993384877054cf9ff70ce3d656d4c8c002b8ca15f947c09f1c596f226fe25aa68406655597f1c8c0000003854e8df75ea94d23ae9fde72ebfd8279ea524fef7bc262b8d8ed7d2f9ff9ba0f5c3c40018c7d15b076f8c3a80146eb0720eaa1861f2e0ea1a717bf6c383d5548c02d44229b55400460000006c21fe6e3ef49f6995f6fe95c62547588bbcd2cda49ff252859a3c5d942f43ff6f82c69b06c0bffbd98184f897d200f7440420d603b8423d80b664e4afb02ca08905155e58c9a29246d3e40f85110000005b89bfa4a44796761991817089cc60c8eae6a4c3acb43516dfc7bc7f8c00dcab85ff83b6bf0e5a9f1b00a11fc0d72147f0c6480364c506462d8099cb37520156146082b094e2cb9b180aa554408311405d00000044a4d3fa6ea3a1295af0b5b07bad52356c96c4255d34f2ff99661a7a1ac55f7afd5971be11fe8fbafe75d0fa4904c0f3754c0358510055fd2fa30056f561fc01fa474ea200eabb8e06484360ff6267a202e61f4eaf63040000c0906b5397f86bd117dab417fec22836ad79c91a90c688d04e299bb2e23f7d54b33eb3f82f68bb77f213f7d59fff8f210db037029c737e192f9e4602c490c3388e52fcfdd28719fc7a6c22b49f74283c7d9880c8f98dfbefeac5c72187fa658dfe25caebf96de1058f373737328f928c95708f6c29ff98e1bbcc930000c0850b7f8ff8ab116ac9085011ea89236f4502b4f7af23e4c670bf2c1daf743a79fe5ecf83a6bf0e1a6f47003e7c78e54ff8834a03e862c06c24406d4480b664c44afa81b25640125e62faa8179cbdf8de7480f19db40000c065a023d243b6b32fec5fd224ad5f13c5373472b08c002bec2fb5578d00c88aff54f8ff0f41e38b1100cfefc771fc8fceb9d7d208d8bbdd6fbdf924fe3102208c8037c25291730f47cfffadfb9e7be39348807f91d1b3972116352c31addfdcdca473e62201719bfc03c7ef44040000ce96dceb7365a7b045fc45d87fb26ea5b34be17f29f2e19edafb9723edb2f0bf3602c2795e6aa5f8fba8bed7f3dfeb173231003e7c78f5efdfbcbcbe1ec7f1fd9006988c06f00f21c55fa402eec5e3c332595a52fca3f087f5ac62514609e28b8bfbf4b5647aa0660448744a60c61088f7050080d36352f0ad85df538a18cf89bfda97f2fe25cf5f1b01e21e132340610abf582fb5ff8de17fdffc2755ffd722009edf0dc3f028e40c62f860ff00220ae0bfdf17b5026f6214208623f60a1f04547afea2c5f0606d8b2fc588048c2a1a90845faefb6bdedcdc4c8c805a3440fed1d5f6d288010c030080e3a03ab2cb12fd39af5fac67c57c52fc0b85e9ef545b1901b2a84fe6fd0bdb64de5f17ffdd8f1fd901303cb70cfbbf0e1fafe943ab01f0db711cff9b17731f3af037095e77f4e25d3006fc8d2c8be4263cec4d78b09b4a31e0240de089e2ef0bfd8c3f6e2a32b48c8078bebf8fbf9914f9ec22054340ff8f61ed67140100c07152127c6bbf5b50edafc55f7afd321260190132125029fe8b5e7fadf25fa600e2f951f0bce6ee1df8b0fc6db301e0fb047ff3f2fa77e338fe97e8ddc72880b44c6414c08719420d403400f646809a567822fe69c394bdb71f8307622480690408957f9b00799b0a88e78c73e25ff0fecdff610000e0b498cbf9bb42d85f84fe539e5fac5be26f190f530b20cff74faafe4be2ef75dbf2fec34ff1e295343b88ffef62efffd60880e737e338fe5d28067c2d3b0d85f0be8c02f887914307a301909a09c5b4fdfe09c330c05803a005388aba8802c454803604f470c3bd72c7757f5d910e48f78c7f642df4ba38506e030080d36249be7f08426c75a495e17e43fc65ca40a70074ee5f1a01f19ed9be82e71f85ffbef2fefd7959e19f28fefb4de9fd140d800f1f5e7df3cdcbeb3ffa1101d1e2f0621fbdfa20dc722202590f7023a201fb90440cfd875f6a4502e41f6332442316031a6901190148c22f2301b12e20debf257f6f19030000707acc85fc3d3adcaf3d7f9502b0c4bf38ec4f8abbf2f8cdf0bf35e65fe6fde5d8ff707c74b4e3d87f2ffedffb71ff5ecb8702b50880e75fc771fc998802e890435cf70fb4af38941180d0a8c7afcb96c23796f88b707c96121095fdda0890cf292300b1d830191cb10e407cd2314307440300004ed7eb6f157ea78aff2a1180d4a7468bbf5100985cfb821120bdfefd67b7dbe9823f1901905a3c16bcff7fadbdabaa01f0e1c3ab3f7df3f2faeb1005f0c580fea271a89f5f7a21f54b2fb0fb078dbd030c43201a01fb1f6b75ea8bdd00754ac0320284c7bf3f56e4fcd3be180a88825f3204443a02910700b88cb0bf2b097f2102a03bfd158bfdacea7f6d0718e22f4edf99a1ffa0b1b2f03efed834d94ff0fe5f87beff69e6bf251100cfff1b86e1a7e1d8580b20871dc454c07d61816406404819c828407c605908b817e452619e3602642a4078f3fbc7791b74484b7f6c14fe342a401b02ea394c6300030100e0e4c53f398eae2efeae6604a86d2de22fc3fd43cdf32f89bf2cfe13e21fbdffd7e2f37dd0ee619501f0e1c3ab3f7ff3f2da7710fa7b117e882302e2f483717d9f0a10c29fc2ffb233a0181510c576121110fbd2b38831fe693d1e17ffa0c148c8c2fffefaca08b0a201d673c40882f93f1829010080bba554a725b64bd14d4b3733dccf4a03c870bf34002ce12f887fcdf38f868016fef7e23216ffa9caff34ee3fe6fec771fcbdd7eeb977d71201f0fcf3388e7f13c30f21dc9fea0062d39f302ae0be3400621d804a0344a25a470f7c620458540c81d44c288e1af05100610448e18f8640da16ae2197593ac2880830440000e06e710b0afe062dfa5af0b5d75ff0f8e58cb545036046fc33cf3fe4fdfd3289ff300c7bf117857fb1084ecef4e7bd7e2ffe7ef9cf2d2faec900f8f0e1d5cb6f5e5effcb388eff3d3c84b732e4e403fb1f11eb01c470849b521a408a75a526a06a0cd42202c208d82f45ae5f1b026974403406e2ba5ceaf5f8ff57cbfb030080dba1a5e02f6e7305e15729001d0d901effb046fca57e56c2feefa9fcff4eb7fb15b97f2ffeffe235bbe55db546003cff348ee37f880f21ea00a411e02300a3a807c8845f4601e254be626861364b91a46204ecab1fc530bf74bc2c04f40f168604caa2bf4904407afd2aaa90ae0b000027630064f97eb9eea6118028f8729f167d4bf08705a1ff5843170bfea4f71f453f7e74f19fccfdc7aaffe8fd5f7bad6e7d57cd06c0870fafde7cf3f2fa1fc771fc54cd0628bb0326234008bf0ffffb2cc0240a20fe50fb89835abdff28e8561e7fff56dee5f493f72f0b0ea321a00c85523a40ce6120b70300c091a0b5622eecef91dfb5f06befbf620044611f3abdff62c15f08ffc7bcbf0cff67e22fbc7f2ffebedbdf3f7aad1e1ae989007823e0b7dfbcbcfed9300c7e586014ff9d5510a8a624d45180fdf5fc7a0ce187f727470658cbd4f0a0f088fe0f9455fcc7730d43208a7d2a0adcbf55111908dfe3cb46f801008e9c52f15f49f89db16e84f74beb96a73fcc88ff5e33a5e75f10fd28fcbaf04f8ef9ff3e8aff388e7ff01addf3aeba0c80c03f8ce3f893588ca00b02553d80ff01b2fa7f920af01794f97bcb08887f4c29c43acf5319e2a7457ff613ee31d6a200621f0000dc118528f1dcd03f37b32e977a7dffdd0af38bf5fd7e4bfcade17e85d0fffea3a6fb4de21fc6fafbd0ff77c1fbff87de77d76d007cf8f0ead5372faf7f3d8ee327221510c724c68fff1e87e059464036aedf20fec8b75f2a298128fe322ae09f4555fb170d032b0d10470f960a006554000000ee9c28baf14bb62e1d73230a503200b27571ce6493b1d451003db39ff6fcdfab887ff4fe65e8ffb5f0febd11f06bafcdbd2f6d4904c01b01fff6e2fad58fc671f4bd01b2d100ca08b8178beeaceb548c001f05d84f272cc6e7c7d9013549fc652420ed7ce7f94743209b22b8543f10d7e552d50432020000e088109eb71905b0ea01867786c16429ce33ed8074b230000c23a055fcdf179f6cd89f55f417c2fedef3ffadd7e425ef6b910110f86a18861fc61a00352cf09e110998440162057fc90808d7ce72feba26401906a6316085ffe3b5c430403912a075182000001c1149e5a74640f2f4e5bacb555d1b062da25fcdf98b617ec59cbfaefaaf887ff4febf0b9f97418b875b35001e5d3df8fec5f5abe7e338fe5234039256903402fc4c8266ae468fe7579ef5d85213a0bfcbb4805a4f510011e64fb97e21fac920480f126a0108fd03001c2d99f72fd627deff9047052caf5fac4ec2fde6f742c15f3400f6b97c21fcf7a3b7af3cff68044cbafd8570ff77c2fb7feeb578e9cb5a1301f046c0d72fae5ffddf711cff672115b02b1801da9576c210f03f327aef3134908508c4d07e19f299180351fcc5b8ff140d98137d5957a00c01390c0300008e57f8c3ea3412e0993af513c14fdbc486f47dc62828f5f7d75e7f3402aae22fc6fa47f1ffbf5e838715ac32003c8fae1efcf38beb5757e338fe27394190b8fecea809d8bf28e372d170b0d8a702443ae1dd8e72644017076606415c0ae1cf2202f1fc42e89f1a000080d3aa0790df5dc3520b7fbce644f0559ac00cfbabee7e96e76ff5f997057f51fc7fe3b577ed3b5a6d00049e0cc3f0c1300c3f0b822a5fca207a0598d5fc4189e347a602bcd513af137b0aec116981fde9615b5ad78680167d6b19af6115fb95ac00000038de3a80f05d6f7673e23f27fc05af3f86fdada17e99e71f045f8b7f3400e4587fd9e8e7af7e9adfa0b9c35118008fae1e0c2fae5f3d19c7f17fc71721ea010665084435d65e7bfaf8fe08c22088298178dcbeb190515038171148cb82f8a736c1715d151f6a8f1f830000e038b0045f7c9da60386bae897b617f3fdc2eb9739ff52d83f8abe0efbcbc2f724fea1e0efafe338bef0e2ef35770bb68a007823e0db17d7af1e7b2320be1015ee979d02fdf6786f692ce88fac29f02fc3cf1b10bd71b32ea020fa25b234802e1e94868051c0480a0000e0a4020153f11fa6e9029ddfd7c797f2fd31d5adf3fdf74ae21f2bfe65945c89ffbeda7f1c472ffedefb7fecb576ab17b49901e07974f5e02f2fae5f7d398ee32fe24b8a53fd0ae40442c9aad29fa0ccfe05c868409cf9e8a6100dd029015d246819061323c010fe980688bf01ef1f00e0b8c8f2fd0d8680330ed0fb6643fe6a9cff3d2be72f045f7bfd31ec2f73fea9c5af12ff2fbdc66ef9c23635003c8fae1efc31a4033e2be5fc8501b0ffe1b10640be54df5740450076a226603fc57010ed524a2013fb8a31a0b70d2a1ab0ff1e7f8b381e00004ec72030f30043d92028450426857e95897da4a76f89ffae22fe7f15e2efc3fe7fdcfa056d6e00781e5d3df8dd8beb572ecc1c386704ec9411a09b0ac51e033e1ab053918078dec40888c97d21fe49f00bc30727eb62c8a07c70bc7f0080d3aa05b004bf180510df75fe3f2d0de1df0f778fe21f855ee5fbe5e43eae43fc7f371c808318009e47570f7efbe2fad5a08c8018521fd510412b1d905e6e8806f817f67dd8f65a1802372222d0140dd0622f9e4b1b01f1592578ff000027808efd7744015ca9d8cfa8f2df1b00b17b5ff4f895d77fbf90ef9743fdac9cbf17ffdf1eecfd0c07e6c5f5abbf1d86e153e7dc077ec8c3300c3f10d31da6598e44d5fdfe65c8798ed5327ee25cc8fb65300662e740b94c43fbd57a5a1a93fb4c1a00c9ed00007076510057c9f7efac7c7f9cac47e6fc83d847d1973dfd93d31b1de1e0b46acfdf1b00df1ed2f3375fd4a17871fdea67c3307c1e8c801f0cc390c63e869793f22041746f54dfe3890120d6a32170232302c220482901b1dcdf2adc6f22fce239107c0080d366520468ec70e27b362acdf2fa63633b11ee97057f52f865a1df7e6e9c4014ffd4e44778fedf8682bf3f1efcc50cb7c48beb573f0c46c0232312102da4f8d2a350bf310c0129fe715d46034c23c03206fc736983406d4b9b6eeb3d0100c02698a5ff729f330afce642fed2eb3784ffbe21fcfed8a46d4162e4ac7ed2f37f71886affa61774685e5cbff2dd023f73cefd344401f61f6504c86880ec861445de320462ba606f0044434045054a46c0242da0f4bf26fe18060000774b4dc7a4b73f9be31f2a15fe3165adf2fd99f00b1d935ebfac278b05ec7a4a5fbffc7aeb71fe73dc7a419b2f0cf43501c330fcbd4f07c85688aa2e203545983104a4f8fb6d3225a05303ba36a0c508b0441ee10700382edccc50c0d902bfe15d8e3e0bf58b656aeea372fb25e14f55fe32dfaf7afbfb62bf7fdbb2c35f2b7756d1fee2fad57f1b86e17f442320f645162f336b18a4d202d1cbdf0bbe3004b411904502d4726204540c01041f00e0b4a856f60f76431fe9f16721ff28fee27b5c9763fa65b87f104ea7aef497e2ef67f5fba73b7941c31df2e2fa954f057c2cea0252a304951290432662f144fcc88840127e6504bca919016a3dde43d7069446060000c0116055f687ed5294b5b7ef0ae29faafc452e3fae4b8f5f9e273535ea8ccef77f2ff2fdcfd64ee9bb863b1fd3fee2fa9517fb8f8661f88fb2262056518a97ae5feec410281800f10f601a014afce33507232a10b769b00800008e37ec2f7bcda4de331e25de692975a76000d4845fe6fae5707699f3f763fb9f3fba7ae0b70f176b00445e5cbffa4fc330fcbc6004486b4b5a728312ee6808c8979fd503c8b48030047414c04a0fc47b0100c0f122bdff28f43aecbf8bb97e25e452f4e377e984c6fd5913bb40d40a5da7a6c5ffab47570ffe7538028ec600f0bcb87ee52b20fee7300cff41cd935c8a06940c01592b20c57f6200682340151d4ae1a71e0000e0b809fa9ee9836ce4638affa00c006504c4ed6e46f84b5eff5efc8761f8fd300cbf7e74f5605f097f0c1c9501107971fdeaef4281e0956104940c01d9c637eb08a83fda0050c76a43c08a0010090000382edc4c0440ce2fe3a4f8abf0bfde2ecf8dd71d4bc26f88ff7528f4fbcd70641ca501e07971fdca0bfc7f1f86e1bf886840eab0648466b25c8f36065474200abfacd09406802e0e8cd731bb060200c09da29bfcc8e23fad0f3a02e0e434f572223ac3a82809ffa4757df0faffdf300cfff8e8ea81df7f741cad01107971fdeae1300c7ec8e0df1a73294b43405a6d5688262e75c15ffa63eafdd40100009c4ffe5f1b01c334acaf530711a913724c7f14fe54e51f8c00dfc3ff9f1e5d3d78391c31476f00445e5cbffaf1300cffd539f733a3d7f29c21a07fa7691018c3ff74f89f16c10000c785fef75d8bb88e08589fa1a0132dc22f3d7fdfbfff9f1f5d3df8d370029c8c01107971fdea27c330fce761187e16a75d542305e28c4bd218b0fed89a529e9ffc3f00c0e9d601d4961aed144ad1cf66aa15ade8bdf87be1ff9747570ffe7d38214ece0050930bfd7de81f904db9a8c66a6a4340a7085ade01f97e0080d3a2e7dff651a582b5b79f86f6a9a9eafd78fe7fbbadc97bb6e6640d80c88beb577e7ae1bf0b86c043d59a517613b41a37b486820000e0b429a67e07bbb19cece227dbccbf0cc2ff9b47570f7c2bdf93e5ac842eb416fedbd047603241831ad7a98779b4180367f5be0000ce90b1a3deebc618126e79fdafc338fedfdd65ebdead394b417b71fdca0bfbdf84cf4f438aa0d4cdc92a1a8cc3418686c8c059be43008013a0d69e5d3770d3a3be6e545f98ac8b6c08f17bb1ff83ff3cba7a10dbc49f0d672f5e61fa611f19f0c5833f896902a3f3536c10417a0000e0bcc3fca3d1193686f7ff3d7cbebeede9796f9bb337000a3503be80f047c3307c380cc323951ad0e342e34c84d40800001c2fd690ede4f5eb4670e35b4fdfcfc8f7cd300c7f1e86e12fa79ed3efe5e20c804284e061f85c85cf07fe135207a59a808b7f7700004782355c3b0abf0fe57f1b3ed7e1f3d27fceddc39fe3ff03b875199eecd47dc20000000049454e44ae426082"
        writefile("mm2-glass-surface-512-v26.png",(hex:gsub("..",function(pair) return string.char(tonumber(pair,16)) end)))
        return getcustomasset("mm2-glass-surface-512-v26.png")
    end)
    if ok then A.glassTexture=id end
end
function A.glassSurface(obj)
    if not A.glassTexture or not obj:IsA("GuiObject") then return end
    local control=obj.Name:match("^GlassButton_") or obj.Name:match("^GlassInput_") or (obj.Name:match("^Nav_") or obj.Name:match("^VisualTab_"))
    if obj.Name~="GlassPanel" and obj.Name~="QosPrismWindow" and not control then return end
    if obj:FindFirstChild("GlassSurface") then return end
    local stroke=obj:FindFirstChildOfClass("UIStroke")
    if stroke then stroke.Transparency=1 end
    local corner=obj:FindFirstChildOfClass("UICorner")
    if not corner then corner=A.new("UICorner",{},obj) end
    corner.CornerRadius=UDim.new(0,control and 16 or 28)
    A.new("ImageLabel",{Name="GlassSurface",BackgroundTransparency=1,BorderSizePixel=0,
        Size=UDim2.fromScale(1,1),Image=A.glassTexture,ImageTransparency=obj.Name:match("^GlassInput_") and 0.38 or 0,
        ScaleType=Enum.ScaleType.Slice,SliceCenter=Rect.new(100,100,412,412),SliceScale=control and 0.20 or 0.36,
        Active=false,Selectable=false,ZIndex=obj.ZIndex},obj)
end
-- Roblox stroke decorations can draw past a scrolling clip rectangle.
function A.clipGlassStrokes(scroll)
    local function refresh()
        if not A.alive or not scroll.Parent then return end
        local top=scroll.AbsolutePosition.Y
        local bottom=top+scroll.AbsoluteSize.Y
        for _,stroke in ipairs(scroll:GetDescendants()) do
            if stroke:IsA("UIStroke") and stroke.Parent:IsA("GuiObject") then
                local surface=stroke.Parent
                local y=surface.AbsolutePosition.Y
                local inside=y>=top+2 and y+surface.AbsoluteSize.Y<=bottom-2
                if stroke:GetAttribute("GlassOpacity")==nil then stroke:SetAttribute("GlassOpacity",stroke.Transparency) end
                stroke.Transparency=inside and stroke:GetAttribute("GlassOpacity") or 1
            end
        end
    end
    local queued=false
    local function schedule()
        if queued then return end;queued=true
        A.defer(function() queued=false;refresh() end)
    end
    A.connect(scroll:GetPropertyChangedSignal("CanvasPosition"),schedule)
    A.connect(scroll:GetPropertyChangedSignal("AbsolutePosition"),schedule)
    A.connect(scroll:GetPropertyChangedSignal("AbsoluteSize"),schedule)
    A.connect(scroll.DescendantAdded,schedule)
    schedule()
end
function A.attachOuterShadow(window)
    local ok,id=pcall(function()
        local hex="89504e470d0a1a0a0000000d4948445200000200000002000806000000f478d4fa00003a4049444154789cedddeb8eabb0d6a56128adfed152dfffe5c6ad96362d7fdef3e80381f87da4528239049cb59803934a9dffeb7fff9f03aaf301db99b50f00f00de54bebaed8ce4ff9f7ed1d78a0f34bdb9859e8090d00562813cf47a563ddde425e6f8730f01f04803905f37c594078c2eb00f88e72d3f9a1746c2bbbce682029c7c6760e007716fd55cbce580fc05e669d2b7a0abcb75eb6c08f16f37370fd57db3100dc753ffe9cb8bd277c1601c03e7a86e7a3dbc95cf99f5f0803e5d8c44e016075e19fb1cc1d2305dfda2e80df2aee91ed4647012257fe99d18191627e0eacfb2a3b04809543eae7e262ff844000e0b7acba05700e2e5b92a304912bfe915181b373bdd7f8f500b0e2c376bd457f755818591e0022bc22ad2d1f1909f0aef0cf4961a0270894e307fd6a007842e1ef29f86fb84500604f25715e89167eabe847e659b70a660681b3639dc7fbb50030bbf0cf2afab3dabd79339607804c31cf0405aff047034199302a701af3b60802bf14006616c619057ba4cd6af7e6659601809945cf2bfedabdfd4820f04600226160661028c7cbfd4200f856e18fb4ad0806debccc323d0816c0b3bda93069c5df6beb0908567b4f1078fd68c0db03c07973e1ef29fa338382d51e9defa1c003efe6fd1f1efd3a5defd7ef46bffb3f52fca361e0ae20508e177a6b0098f961b815457e743ad3169937637900bf21f289fcc8fad687ec66fe111faff8470abf35525094d7ce0481578e06bc3100acbcea1f29dcbdf322d35a9bd51e9d0f00d6b9a2a7404a8575f6e8403ded157eabe89fc232bdfbfdaad180b70580f301853f3a6f5538f0dabd7933d701f05ed92b7e6d9dcc30bb547c7b0a665bfc67058319b7055e1302fe6d74d53fb3f08f3cef5dce6ab3dabd7900f614392ff47c198f77e5bfb2406ac160661028bf724be0df06c5ffcec2bf2a3064daacf6dee500fcb6c857e9b6cb59f7d5bdb633f07cb4e0af0a02e7afdc12787a00182d64d9e23f5ae0570684c8fecf28f28402e0b75943dcdef2d272d94fe5cf0e0196481028d5f2d26b6b6df5765e19029e1c00ce0715fefab955cc47daa2cfa569ad2d322f8b80003c5b99f87fd8fb629f767b6572e1ef299ed73ecc1a1df04603a4f65784807f1b14ffd957fc9979d9f5a3cfb36d9179007ec38cffe75271b7e6796120f3bc7e3c94b691e31a0d0245d8eef9c610f0efc787fcb3c5bfa7b86bcbce183db09e4bd35ebb370f00bcab7e2b141c9d05ff3a377921a0a7a84afb5c122311de74665fa22306db058099c5bfb7f04b6dab1f336d9169ad2d331fc09eace27fcdf7d6d16e035857fb529b74d53f321a20bde631f0a1c1d1df12f87a08f8f703c5bfe7aa7fb4e07f2b0c58c7a4cd97100000482257d3569b15064aa06dc6635471428877f5af5dcdbf26043c250078a243dd91a1f391223d7b196bb99ee7569bd53e03a102b857f9c2b62301207a55ad15e0d122df5b588b11088e6028a8dbea751ee90901e0bca9f847affeb3c57d64dde87e459f5b6d56bb87e20ebc53f97200689f6b41a09e574f5b2160e4838145d9aeb6cc911819a879fbf7d551806f068048518914b2d957fd9922bf2210786dd673695a6bd350ec81df961d26f7dab201406bd30abe34ef0804829ee25a8c60901d19c884807a3b3f1f007a8bffe8557fbb4c6fb11f796eb579fb6f3d97a6bdf6ec32007e47993812102dfc910020b549453e7a851e0d02c5380f665eab3dcee83edc3e1af0845b00338b7ff6aa3f1b00ac696bb9e8eb79fb1e7d1e2dec147d0087537822216034007857fcedf3ebfc65b5f72aca2880340290fd5cc0a33e13f08d00707eb9f8478abe37afa7e0674702a2c7189df6da471126807bad2a263d57fded74f48aff7ad4dabc1020157ead106b05b808e72f2b04d4db9a1d026e0d09ff7eacf88f5cf547a67bd6915e3713007aaefea361404221077e5ba6c0f4147ded7934005885debae297a633c539c30b06af0801ff5e5afcb321207ad51f0d0199766bdadb5fef98ad3ed2a625147d604fd17be3d1e9c82840260844a6ad1180ba5d9b1e190da81fdb651f1f029ef21900aff87bcfa3c5bff72aff1c58c77a3d6b5fbd63b59e4bd32d8a3e809a5770460b7ffbd81b00b42bfd7674a05dbe5e27526cb5c2ae3dd6dbaad7d35ee3b62bfd6f07806cb1192dfe9900e0157c6bdeac00100932565f78f3bcf6dee500bc4bb4e05857c8da32d961ffebb1270078edb5361448f332a221c07a1eb13c20dc1100b257a291e23572c56fb5fd29f37a0aff6800881c6fb4ffb2ef01803d64affa7b0bfff57c6600b04602ac50f0ff96ff04afcaa551806c08b0b6ef15f9a521e0dfc38bbf55f0a245ff18b8aa1f29fcd1d7b79e47fb40ea3bad2d32af072102b857b9717b5e10880cfb5fcf33c5df0b00d92070fdfc4decbfc8ed80f2c410f06fc3e23f3304cc0800de31797d214d9f83459a620efca627dc02d0da46028036fc9f711a41e7ec1811787c08f8f7d2e21f09027716f99e10d053f8b341c06acbcc07f09beeba05900d023dc57fc64f841602daf98f0f016ffb22a04cf11f0d00d7e701fe1686006dffdbe36bfb456af3fa2edad700f6532685809e51801957fed6cf75bfffff3dce528410a0b51ddf2cf27707806cc1d1ae66a357c8912bec48b19fb14c4f10d08ec3eb0feb79a4af33080ac03bf51693de2bfffab9d6e615ff9985ffa8eef7ff19cbac0e017561d79e4742c0d480f0ef45c55f9a972df491227f28c57e5600888680683f487d1b0903120a3db087cc7077743a7af57f47f1d7b6d58e06fc25b7e7f59554dc1f1b029ef2e78023c53f523c470a7f6fdb8c10203d8f3cb6cfa569ad2d320fc0ef2b0b46027a0240fd7cc6d5ff9fd1f6376104e0dadffa1cea8d006442c072330340a6c83ca1f8f716fde8ed82c8be49c766b569fd64bd07147f007785002f0c444702b42bf04f47f197aef63f46db534280150aa604865901604691b9a3f8ff05daff060280364fdb57edf8bcfe90fa361206ac7600388cc212b9f29f7df5dfb65f85cf0a0287335d07844fb5df2361602404589686806fff1640a4d849cf8f09853f5af4230120f21b03da3e5bc79929fadf0a00040ae0bbca4303c0ece2dfce3b94207018d3ede8c0a114fd9e5b04f5957c2604d4857cb8a8df1d00ac02601525af6049c5be7ede5bfc7b0abfb58ed6160d02dab4f598ed4baf3d83820f3c5b79d12840645afaa90ba51500daabfdb6b0ff054605464603a2c3fb5608b042c15060f8f780e22f2d275d0daf2cfe7f3706002f043c3d00dcb14d007165c1ffc9bb02404ff1f7963f12cf3f42a1ff9b14028e2608b4a1c02afcb784806f7d13e0112c70e7170b3f0160cd7b0e608eb6c8ccf4cb01a0beda3f3a460a668d06b48f9ea1abfda7fc39e0c855eeeaabfe596dbd2300da55ffac1100adcd6a07f02eabfe2fd745cb6b9f1900eae733028054d4336dab4703acc725057f6600881618abf85bed6db16c97cf8681b68047e6bd250068ef877782200c003884e1e668f13f1f1c00a46d1f8940f0518abe75de6c0bb6d43f52b1d7dab5655a5d61a13700f4140eaf40b585500b03d27291821f29f4b36e09ac0a00d673ad8fadf6e87c007bde46d0e64bc5ff3486bd570580b3f94d006f785fdb978f50fca3a3025a9f68fd17b9d2ef29e8e975567f15b055f4bd22584f677facab74ebb12700f48480f6d8a47e68fb6f340478f37a111e80ef1a1926ce16fe6cf1b7828054f4af2216fdb17eadcf7abdc328fa6dc1bf8e416a8b9e0bb5db00f573695420330a90f66fe1093f52a4aca2d65bf4b357fc23a302330280f4dceba348d18fbc4f146fe0fd66fc3fb686aedb65b4e25f2fe315b8bad0d7cf8fc15b00f574bb3f6d81ef0903525be67d90aefab5e22f2de34985833bbe0ad80a028771553cfa932df6770580f638eb7e910281345febcfc87b308ad0003c5b99f8ffba2d486dfbe94cb74140bbdaed1d05388ce923f0f811c280150aea638c9e7f25d2e848a6f0a70afdac00103d40eb8ad4ea3c6bfbd962ef156faff8676f037841403a86f6b8ad3e8a3cf7de8391e500bc43f6ffb45548a4a22fb54b41401b05a897d38a7ebd0d6de8ff6886ffbd4ff81fca28c04728f4d7f93c3a32d0f689d5af52e16f439154e0a3453f1c0e56ff2d00afbd2d866ddbc88f57e8678f025c6d47334f3b26a91fda36a9bfbcfef542140078e705edaa539a57171cade05b05ae6db382c0a7798decf07fddfe71dab460501fa77531a69d6fdbbe92faabddce9251804c0018b9a28c76d6ac427f7616ff6ce1cfdefbd7828ff7e8f59df7fe50f8016468c55e9bd7b6d545fd6ab7428077e57fb9aee6eb2b7fedeadf1bfef74604daf9d739dfbb35103def7af7fba5021f2dfaa1e566ff2d00ebaa552b6a5e81f4daad30203dcf84022f0c6442c0614c47fa29d2e7d67b934160007e53591c04daf9de0880b44ce4168056fca5ab7eedf170aefe4fa7f85be7ec3afc1cc1f66c3fb5cf1ff5b700bcf5b475a562e7157a6d38debba76f15ffec87000f653fa463388221a0ed13a9cfa26d1e8a3ef0fbda22955daf0c0686ec6d807a5e5bf44fa1f87b57ffda15ff2914fb4359ee488e066857fa3dfd2be90e01ff161507ebaab6bd7a9dfd635da14b43fd333f0360fdb4c7ebf593d4efde74cf7bd5bb0e8077eb291cd23ad67622854d0a0475bbb4ae742bc0fb563feb7ebf746ba00d05ed74f4dc1d39bf5a9fa1d0fac7e32e7fc7af014af3db20202d3b52f8a52bfecc2880b72d2b70440b7fe41f8cf58fe85c50cc0902c01ea40fa28dd08ab7b7bc54dcdac27f066e011cc66700b469efeabf9daf2d9f0900d1a014edbf219100902d349924d473e5dc53f8dbe5bd0fffcdbefa8f147eafbfee08001a8201f04e5ec1b95ba6b0b54140e38d021ccd6d03e973001fa1c86b853f1304da7bfee7e00702b5fecbb64ffd5b0052f1d2969f51f4bd821c1d01887c1620f25ad16368fbca2afa5ec1f7fe0353b4019c0f1935900a9155d4ac366d04e068eec3476e019c4691b796698bffc807035bde2880d66f5eb8baedcf017b57b3d67a9910e015626b04c0fb80e0ac1180c3791eedaf48b8ea990f0023853f1b0cbcc2a6b56bc52dfb3900eb837ede088054fc23e7f6b6f8473e4ca98d024ce3058068d18ece8f14cbc8725a21960a7e5bf423f7feb3c5fffa47920901d2a3f55cebeb9e024f280020b13ea19e21153cad184aaf17b9177e0adfc7ef8d0058bfef7f3641a06eb702811606a4c768589af959007599997f0cc82b6ade1bee154eabe8470bbe161422c57fc6d0ff6800f0dabd7900700c9e3fa4a1f976decaf3d055d0a4df02388223007f8121fe6820f07e4ba00e3c6dbf643f14d83e6a7df388ef0190ae60b5a269cdf77ebc21792d0cac1cfe3f9ce7d2a3d56f997eef5d16003205bff7d7db460bbfa42efcd774e636c02914fdb6e05bc5df3befb7fd504fb77a7ea322cd0a00d28e7957a4da15ad77c56a15cf4c08b0aefaad3010090199e29f0d00d673abdfbd7923080ec06f298bce056db1caeccf8af34ce436c0a90401abe87ba301de795f1b09b86314405c766404c07be3a422a615ca7af968b1cf0602ed5640bbfc8ce2ef15fd48e11f2dfa14700033cf09915f29f46e0f48c5d0fabcc0aa10607dd98f54ecebe5ad9a13f960a0f4bd075f190558f15b006d11f30a995538ad36ef4adf0b0599ed78e1c1dbe7c378b49e5b6d917900304bb45079f3a24120ba4fd2af03b621403afffefde779661440ab0fd23ad7f1d4af396b14600a2d007845487a6e1531ade3ea79ed72d67a5a21ce8402ed437dde87ffb4366bffbd7e92fa2bfabe7808080046443e65aead2305026df9dee22f15fcb6cdba15702aa30056b12fc1f5eafd3c3b824ff40b82b4f9567f4d1f01b04280b57c3469596f8a1404bcdb00de870023c1413b8623f018ed33ab2f29f000563a077e7550bb252015b2abbd2d6e56716ce74921e05aa6e743802defb706acda70088fd1dfeff78a7b9759bf056015ae48e7688f2b7eb4201029f6d15ffdaba77b0abff71feeeea24fc800de69ea17c704ce0fde6f0c58bf15e08d02444709da10a0dd0af80b7ee9cfc8cff55a52a889849cb6df6aed36a604006947ac6215595f5beeaea21f29ee33dee048f1ef29fcbd0598c20dec6dd639205a60b482dfce8f0401a940463f30a89d5bb59af337b9f07bf5413b368f57ecebf9d2b2ffa36dd55f03ac0f565ace2af86dfb3150e07b8a7cefaffa69455f2af891c21ffd8f4b9107b09a759ef10a92b49c170432bf1920cdd3a6a52fea399be7524da85f27f353021f0c6c8f21724bc50b02b7fd3540a9c0d5d356d16cb71329b091a26f7d1e402bf691c22ff541f4d8a43eea2dfc147d004fa115796d392f0878b705b4366d9fdae9eb7cff119ed705ff307e4b201306da65dbe38cdc06c97c18b03d6ef53dc98e00cc284e5201b40ae8ec9fe87dfdec8fb4efd2a3d64f56bf51f001bc815798eb65aca276cdcf16cac87ed5e7e4bfcedf06c8fe14e779f4cade9b1f5d66ea2d00a998450a65a4bdb7b0cf5a7676f18f16febb8a3ee102d85bb9e9fc92f93cc0353d2b046801e0e82cfe7f1db7048ee4ad80d12f075a160022852dbaae5440ebe9a7ff3cb5f853d801cc3c578c0605ad60b5ede78210100900c7e25a511f93755cd90f0366d755038055a0b29ddcb67b45f28e3760a4b84bf3a47db71e23fd9445a1077007ed5c93293a75e1b6dadb02ef85006fff9e1000ce66dfbde3d2fa3652e8a580f05ff3ac2f3c88928a9b562cdf50fcdbfdf08ed33a2e6d3da90f33855ceb5b00b85bcff9485b3e522fdae5ac3a23eddfb76bcc29ecf739584f6fbb05a0bd0191f532c5bf5defdb3f47c79be8f551f63f0c003c597d9e8a0e65b7cbb66d3db70122df0f70568f2bc341fd7ad1918048ff9d461f85fc4d2c30d6fa5aa7d76d5a6749cbac28eced6b46dfd06361f1975e1300de2073feca146b6d5efb9a990bb6f386c26ff54bb46e44e6459c995b0067b03d72e0eda3b60debcd9b55f4236f9e76dcd63f28afef7aff4300c01bcd08016d9b761eb6b67f3ea0c6d4b44022cd97a6dbe523edff9f15007a0b97b7d3d69b172dcab3debca3731b5e7f640381d57700f00ba2455a6b8b14ba95e7fd33b04e663fb45a28f555a62e84ebce1500b20527b3bc5430ad8e6ad79d55ecad75eb36ebb5db79d2319d93fff103c02f19b908b2cebbbde7ef73616d89d435edd8227d25f54d78796d04e09cfc66d5cfa58e92b6d793a6bc37a7dd5febcd8b1cab55fc67f52100fc9aec0551e6bceb9dbfbdf3ffcabae3d5bb4c0818e9c3e16f02f4528df5c29175bd64a5b565b75fcff79697b62fbd0199624ee107b0ab33f99706adbf6ed73e9768df337056ed5a61b56a44b4adfdb1bed9cf3b9ee16f05bcbe127765a1b20aa7976046939437dd3e46f6477a2e6d4f5b2e3a0f007690394746ceb3999a720a8f993aa26dd75a36b25ee4582ca1f57abe0828b373d2b25ee7453bd24b56d636236faeb52fd23179c79f9907003be939574ae7df688d388275215b5ba4ed5adbac49fbd23e97740786bf4985c93a907afe4827450b7be6cdb14289758c91824ff10780b8f3a6f3efe1d48dcb48bdf196915ea36e3b94e5a6d6ea995f056ca51ae9b15dc66ab73ac2ea406b5b56d2b2f6473b2e6db9cc3c00d859f6dc19bd62f6aeaecf66b9c8f9bfa73669cb5afb23ad67d59fb06c00c8be68e420ce64fbd1b18c97b0ac7f1c91701145f1078075e7c9ccd5f529b449eb8ed41e6d7b5ebbb65f91633f6705802929a3d95e360d699deabd39d6fc9e63b30244647b147f00c89f6fa5f6e8f938fa3a67f598ad27913a25bd6ea6bd875be3466e01583b994d579176ebb5239dd693f8bcd7f5daa3f3010073ceab5a7df0eacbd92cefbd76a42e69fb1069cfec53578d99f11980c88b47ae8e474600dae9996fb6b56f0080efebb99a3e3b2f0a7bea5266dfdc2bf7e0fc7400c86e50eb2c6b7b56c7581d7c04a7add7b5de6c6dbd23b10e410100e6f1cea9daf93873b57c0a8f917379a6366917a4d27233eaace5cc8c007845b2e7eadf3b2069dd68677b1d1e09075e728c62940000be7f1ecd5c995f2257fc759bb4de35ddf26a53ef2840aa3e676e018c8c0e64d6f10af0c808c06852ccac0b0058cf3b1f8f8eecf68e0048cbf65e5c2ea9bfb33e03e0bdb894bada0e895e994bf3daed49db6ff7c3da4f6b1fa20807003047cfb93772957f38f5616404409ad72e638d4ca4aee67b5801a0e7ca38ba9cb76d6b6824326dbd6636680000de2f5a98b33525321db9faefa997d1e5ce995f0424b56b0738daa15af2b2925824f979fb154d89d6b6010073442e0ab357cf6760db579b5773ace9c8be78fb65ed4776fbff1500ce9b8664eab6c8c148af1519d6695fc3db1f00c07ecee6b16e8f5c4c6a6dd1916e6dc4bba7c6a696ffbb7bc82158ecdb04656d574b64dafe64f6aba71f081500b046cfb9d6ab19d13a11a935d6c566b4f669f3acf522fe6bb9997f0cc86bebd956cff07f74bfa2ff90bc370d00f03c9991e55379aecdcfde06d0b6f5ad5abbf4b700229d9ab90530f2fa5e4acba443ed350000f7cb9eab7b6ac139b07fdebef4d4a869560780de7b135a7aca262f6f7f660cab00009e6d564d383b47a27bc3c4d23af4377998413bc0682778b700acd7396fecc89efb340080779c7fcfe47cab46456b9577eb407a9dcc3efe575bf4cf01475ee869c54f1a5e19bdd73feb5e0e00608e9e8bc133b0bdd5b7a8478c0681ee5b00c32fda2c13b907326b9fb4759ef6e60200d63a95e73deb6797cd868b9975f7f6af028e2ea3dd5369e75bcb66afe497742c00e06b7aceeb6760d9e8e7d0b4ed7bb7c9a3fb3ac5ca3f06d4ae33b2bed5a9d9edcfdc2700c0f78d9c974fe579741d6d3b77ef93b6beaae7cf018fecc8378be6ea211e00c0f3bceddc7f4edc8f73c52d80ec4e69c9e8491f020400e0346ac84a91916e6ffd94913f0634a343667c0870f40384d2f6666d0b00f03dab6bc339b8eeac70d1559b473f0438b333eb76e960bc0f5b686dbdfbf6945b170080bc1523cfa75377ac51676b1f56d452d7aabf05306b5bdad0fdc88700010018714eae5f33f7e3abbf06f8d6427cd77d1e00c0f7bcf95c7fcedcd8dfc69dca103f00eceb549e3fddb45abbf28f013db943dffac60300f6ab05e78a8dce0a006fba47ff96371c00b0674d38036de7d3ff1cf053be4c419a0600e0e9f563d96baf0e00deaf48dcf1dad63400004fa81b915f757f5d0098fd653e91dffd5ff1fb9f00807d9cceed81d975eb76df0c00da6880f74540da725a1b0000339cc19a15fd22a0bb47c51f390270e18b8000004f773ee48b807e2a000000801b10000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d810010000800d11000000d8d0d3024051a6b576af0d0080d9cae4fab55d0028d58fd45e4f6beddeba0000cc5282354b2afed6ba65e71100ad63b46533eb120a0000a375a9246b8fd5fe88ba74470068d3d09d07fed8a11700c02315677ae5eb4af5f2b501e09b0597e20f00787bfd284f0f006ffa909e35a40300d84b519ebfe543868f1c01784a47bee50d0700dcab28cf9f66c9becd0c008ff850c30fbef10080f98af2fce9a6d5da1523006feac837071800c05ee7fa3273637f0fdb21be080800f074e5215f0454be1900465edcfa7d49eb8b80ac5f919895ecbcdfff04003cdb8aef83294edd91ea54641f56d4d2e901607651ac3bab37258dacab6d6fd6b60000dfb3ba3694c175670613edb5a68f006477f81bdfcc277530c51c006091aee6efac59ed7e64d64f890480d1037fca507acf6b131800e0ddde76ee2f13f7a3cc1a0118edc491f523c9a87c619f0000df37725e2ecaf3e83ada76eede276dfddbbf08a80c74a055ecad0f5b686d2bdf7000c0f3acb8202c819a13a95fbd17b0d36b504f00985930677c0830bbacb40ec51d00f65294e73deb6797cd7ebe60c985aa1700463e89ff6dd90f0166470ebced0100d6cb9e97bd737d69967b727d8b2e1b0e00a3f7d7adf5bdced4de486dd825b38f33dfc0e8fe0300e6bae3fc5b92f3ad1a15ad55910bd6d1c25feefc73c0da4e78cb6b9d10bdff124977debe51cc01e037ccaa0925f839b4767bbd23094bebd0ea0060756c3bbcb2e240239f2ff0925ce4350000f7cb9eab7b6a4119d83f6f5f7a6ad4e3ff1640ef0e7bb7007a9297b6fd6cea0300bc47ef6870092c9b1989cedeae8eecefe8b6cc0030728fc19b177953329de7058176bdcc7ef5f403610100d6e839d76646798bb1ed48ad895ec46aafeded57769eb95c1d0056de9b903a35730b205298ad37cc7a530000fb2acd63ddee5d505a6dd10b5d6df47ae5ade832fac780daf619c5d64a6a99db0091372d3222601d87f566132c0060ae32e9fc6cad17b998cc0efff78c2c474249cf68c1ff60058025430ec16d6b89283a3d32b4e38d460000de27729e2fcda3b7bde874cf48b7d79e59ae7cf3ab80a54e8fdc02b0deb04c12d3d261244848eb47102200608e9e736f6424f870ea4366e4599af66a9b3562d073a19bb2f28f01f5ec6c7478c3eafca3f34dd75ecb6aa7c803c07779e7e3c839be04d6d186e3b56969d9de11e625f5b7e7cf01675389d4c1d1a1919ed465a5376d7fbd84d78b800000df3f8f5a57da35ada68cd6a296579ba2179943f5f96f62cac814db7af9769ef7468d8c00b49d9ae9acc83a91d40800888914e9d191dd223cce1801885c904acbcda8b39632fb33003da300edfcec95b977c5ef8d00786f7664df0000dfe7d58fa3e3a2b0046a4a743ab36fbd57ff6923016066c746daadd7f6dee89e7d8a8e2c58edd1f9008039e755ad3eccba283c82f56146cdcb5ca8a645ff1cf0ac02964d43992b7ea9cd4a63d963b3de9cc8f6080100903fdf4aedd1f371f4754af598ad2733470022e123caad71bd5f04d4dbb92369c8ea646f994cbab2b699397609210000d69d27a3e7efe25c0c468abef63abdb54daa93ed7e458ebd7ce38f01450fa2270d491de62de36dcb4b92da36b4e3d296cbcc03809d65cf9dd679bc5dce3be75b75ec9a375a9bb465dbd7885c3c4bf353a400d0b3416d27dbf9d10ef49257cf32da6b48fbeb1d631958c69b07003b2a379d7f0fa76e5c46ea8db78cf41a75dba12c37b556f78c00643bb97dae1d484f27f5fc48fb920d10d23179c79f9907003be939576a85b27e1e2dce47a2b0cfac5735695fdae792ccb2471b00a22bf416acc89b63ad1be95ca93df36667f6477a2e6d4f5b2e3a0f007690394746ceb3999a5284c74c1dd1b66b2d1b592f722c9672f7af0146af9aa3eb5a1d6fb565b75fcff79697b62f7574e64d230400d8d5e8b93272816915e7487d886c3fda16ddbef77a990bcd7400c824102be148db194d52bd3fd2fe5a6f56e458a563b28e5d63bd2600fc9ac839cf3b9f6ae75deffced9dff57d61dafde79b5445ad7626ee70a00d9e29359de7ae3aee791cec926abccba759bf5daed3ce99866bd5900f08b462e88acf36eeff9bb2cac2d91baa61d5ba4afa4be092fff97dc58f405a20533dbe1edf646dfb8a3731b5e7f586160e41f3f00bc55ef4550e4e2aa7d8d15e7fd125827b31f5a2d94fa2a5317c27527fa198048c74776da3bc8ba6d46811fd996d71fd69be7f55de48d240400f815bde73c2f1058b5445aaf3ca0c6d4b4e22fcd97a6dbe523ed6200182d38d6fa5608b89e47c2c38a9f769f22ff1022c7a52d17e92fab5f00e00d32e72fef1c193dbf468bf2b1a0e85b752252efeac7f6796b4abdfed7b9e2593dd66dee0b36eb16e179dd7647e18f76fcb58f5a5b7b5c521f5dcb497de2a95f3bb23c00dc2d5b982217475af1b72ed8a4b66ffd5ca235a85d4fe305885bbf0ab89ed63a20fb267eebcdd2de3ce938ade3d2d693fa30f3c6697d0b0077eb391f9509c5dfda9656789f5867bc7a11a9a75dfe091b6baf50b357f9d232f54e6a57caedf327bc01d2557f3def088e0014631da99f3257f8defe01c00c65e136bc02ae3d6a85fe8945bf046b8f56ecbd3ef4faefbfa67b6e018cdc0690d69542c0f1900010e9e8ec6d002d60497d74c77f568202b0b7f2e5d7192dfedf2ee8255173a47d971e337d995df7180d00d2ce48f7b6bd82593fb657ff577bf4e7931841f8545f833c1a00463f0bd04e4baf7dfec07f7e00fbb1ce2f25387d57f1ff2c5a560b0399f63644787dbb2400b485be6799b6186ab70056dd0e688b7f3d7ded53bdafc7c41070cd93fa490b02d27e70d50ee0894ae732da797775f1ff4c2eec91822f3d8ff65f6fff760700ada0b7054e5ab6240b65db39d910f0115ea76e3b8ce2df060169ffadabf4f6d8bce31df9cd80fa35080300be295a70bcc25f4fb7e7612d08d4f3daed440bff479857ff48edbdc55f6a978ed13a3ea946959ef766d62d80eb85bc61ed769ed4096dd1ef1d09f808053f92caae2050ef57bbefd10f09b685ba3e9e231804b47ed4f6a9dd0700b8abc847d7cb1435af48b6d3d1c25f12ebf48e0c44f7b53d3ea9bfa43e1af2cf29e4529b34df5b5f5b2e320a907d83cbc4cf017801a0deff9e5b01912020bd6eb4b04ff9474290005eab3cecf522857f55f19f1d0ccac08f766c33fb575ab6cc1c01688b9bf96202ef57e7560400696440fb1c403d1a204d7bc715996f05817af95a1b387eed2402e03d4ac7bc4ce16f1fbdda10bdafff11a6570681cc7149eb6a7dd87d7e9e790be0688280160aa4e5bd4e3982455dbbef5f6b0b7fdd761578eb3680140222b702ac518091ef0788842c00e8d553602285bf9ef642805407da69abd8d7f3a4fbfa4568937e66878568ff4afd334c0b0052f1d68a7b5bdca4f5bde2d83eafb7e90580f6837cde7d7f693da9f84b61e0d2b645c28e75ec5ebb363250cfd34cfbc70200c9734c4914b39e0bc1baed1328fa52082889622e05814ca12fc1e3aae745faca7aaeb6cd1e01c87c18b0dda136086861a0eef868b16fd7a9d76bb773088f5a0838ab9f0ceb1680d4675a2090e649cb00c0a832310c58cf3301c03bdf678bf9a7e3ca5e5b47da5fed18ac3ef30a7bb77f930a7d64be57a8ea425f2f2f755c7bf5ee15fbcb5f70f440bafa8fdeffb7443e30a82d57b3e649cbf4ee2b80df51beb0ddc855ec113cef1f9dc55fbafaff3841c11afeef0d1c52b8b18e29dac791f9e900201578ade8d7c53b7a5fbb5eb77d7e76fc43b07edf5f5b4efa0e80cfe210d0f3a14169f94b5954c8579d2c00bc4be65c503aa7670600aff86bcb7d029f21e81d25b0f6dfea4ba93e4a21c2ea6375d959bf05109dafed701b16a474a43d6f0b78b4e8d7ed5ef16f43c0690481eb987b0b6fe4b702bcf5dbfd018059bca2e5b5478a9a5534a5b6b6a05bc53ff321c0120c1a3d61403b8e923c87779fe3ff4d2cfa577bfb58ef6074b8ba5ebe7dd3b50fef6905ff30e64786ffebc7baf0d79f01f89b50f823a440d053f019de0730ab9844ae386706807a9ef5c13f2f047c9c20d08601efb5b450e01d83d6a7917e8abc17dd01402bf69965a42070244702b47f1c5218381281a02dfcf5f3cc6d802b0c448edfea2bef73003dff397b7e751000a2e78b6831ea2dfcf573ef275bfc3fc6ad002b107845df2bf899e57afa3eb4cc8adf0288fe6aa0b6de25fbfd00d648801412aef6cc6d80eb6abfbdfab7fac01a2d89b64bbc50d573fb000034d962a44d6b41403bcf7b41c02ac8d1e1ff8f733bc07bcd4841970a7ca42fa57e9ba23700b4854a2af8daf2918368af76a57f18d207f7b4c2af7df04f9abef6333a02508781f6c7ea33afdf32616075e1e79601f04ee5c66d5a01c03b9fb78f56c1b77ebce21ff91cc027788b40fb4061340458cb45fad9eaefdbfe1aa0d62e1537293868af191d096883c0e17c319034ec5f4fd7ebb661203302d0f6477424a4b7f0cfb0ea570a013c4bf95200f0828076b51c2dfa5e719702c1c759d60b0b338b7ea48f46de935bfe1aa037bfe757038f0941a06db33e0b701ad3da8701ad91002d084841c9eb3f697a04b70b803d9549eb7857a325f1982d9e5ae1f71e3f4e681829fc9142dff68f56f7a2ef415a3400648b8d56dcdac21f39886800388cdb015210a88fa72df447c7e7008a321ad0167ea97fbc638f7cc0d06af3cc0c1300f62efe755b24085821406bbbced7d9fbff5adb2758e87b0b7f341868fda1f5b3c55d7ef5f70058eb1dc15b0b5200d03ea8d70601ef837ed2725218a81fa5e27f4d6ba301f5715d3ff5716a8129d36f3dcb49eb64d703f01ebd578eded5abb65cf4024e2af4edb4f6630df18f8e0294c00701a5cf1548c5ddea4769d9a8def5a6dc02900a59fddc2a6ed28e6bbfee96f960e02739d47f24be07e05a470a03336f0568fd2af57f7b1c91794bfe4101f829d1c22fb5458b7f6fe1d74240f456c0a7231458853e720c567ba49face74b03805584bce52245cd3b102d4959a301ed15bdf5fbfe8771d57f3d5ab701b45b0175c1d73e0cd88e0ad48f87119ccec54100c09e460a7f3ded15372b084845531bfacf14feb6d07f9436a9e047affa233f5aff497d17795fd2cbcdfa10a0160ebcf67a27bdcf05643aac2dfe5a0838036d5210689fb76d6d30a88fb9e736801408eaf62319046a8402606fa3452572756a5dd96ac55f6a938a7d2400448b7e31da7a0bbd56f8a563ededf72ed900a015f4c8725681bbe61f81a16e69da1ab6b74605bc1181fa4a3ff2ab80deed80ba1fa410208d081c4a20a8db2fda888af59e65ff11111880672b376cab04a7a58227cd8f167e2f08cc18052889f523855eea3bafbfca82a0f6955f032c892bd6cc3f5caf03b542df165bef437f91abff76dafb29caba523892aefcb55b019130305acc679e5c003c43e4ff75a42869855f7bb49edf11008a1304568c0048c7acf56934807dfd8f0159cbb5eb4885ae7d1ed97ead2df8529b170aac0ffdcd0c00871108dabe910252dd97da2880d4875af81ac18800f05d2b42b97705ab4d7bcfbd82bf3200f416fd8fb3cd6ce1f7fac6ebcb69ff1666ff2d00add04bcb440a5ce61f61dd568780d21906da622db549b703464701dad793fa467a2e4d1fc1fe3c1f76f201700fefff6ff40a3453f8af472f0cf484804c0028c92bfe191ff8b38e5beb6fabaf1ff1b7007ad7a9dbda4060152eadd06957ff75a18e5ce55f8fd2326dc12fff69cb06802319007a8a7fb4f053c481bdf504814808581d00ac429d29fc2538cf0a02d2fed7fd2115fc68df46a4d7191901d04240dbae15f9c82d819ea1eb7a9e773b400a06de557fddd67b0b602400487da2157fa99fda7e0700ed1ceab597970680d2d116f991fa470a03527f46c241e6bd71adfa73c02d2b04488f2357a775d16fa723c5dffbd4ff8c007018d3bd01205afc5715fd91db0800f25606f868a19919007a428037543f5af03f81d78b8682f618ad47eb3d98e6df0d053fb25cfb78cdeb2d5a75e16ea7ada2ae157aedf99303c05d459adb08c077ad2814bf1c00ee2afc453856ab4f7adf936e2bff16403baf2deed2f36bfab87134e04816fdd1007004a7ad47ebb934edb567b4db589e5201a494170580d110301a00caa2e25ff783160422fde7bd1fdebc5bff168037cf2bfcd6b223a3016d08904603ac79f587feaefd688bf6e17c18505a2f1234eac7e87369da6befc5d03ff05db343f8ace25f3f978aa057f0b5f6ab281fc14febf716fe3250fca520d0d397d27474de633e03703821c07a9c311ad016fabaad2dbc5ec16fa7ebfd3d1616ff278d0200f85db30240591802acc2ec5dc1473ee0f7e92cfcdef1598f56df2fb1fa6f0178f3a4e52221409a8ea80bbb372a9009006d10f873968b14fd48e18f147dabef0903007aae32b530e005814818b00a6ca4304786f03f938abeb6ffd6f17afdedf57d64de63be0a589a574f4bcf5786002b0c44da225ffa533a8b7ff4ea3f7be54f0800b0baf8d7cf238f3d2120fa7347d12f138abff65cebfbc8bc47df027852089046008af1a77e23c53ff273edf75dc3ffd12b7d4604803df45e81468a7f6f00b82b041c930a7f71f6df3a7eebf96d567f15b0372f1b02da79d1fdf17edaab7da9d01f37167fabe0f78600ad2d826000bc5399b85e6ff16fdbee0a013db70b4ab0d07b057fb4f85befdbb4b0b062046065083882a3025952c1af4703b465460a7fb4f847c38034adb545e601d847991406220530120266078163f23dfea2ecbfd5f6a8e2ff84df0288cebf2304b4acd18019c55f2af05ef1f74601a469ad2d331fc06ff2ce9999e25f3f8f3c6a6d2b42c0e8cf3150fc47fbfbe7be09b09daf4dd7ed6dc1bff486806b7bab7f8e40db21b41fc663fbdc9be7b5f72e07e05d32e747afbd37085885fff862083882f3bce7f5a3d616995e1e0e568e00ac0e015ae18f04026fdf6606889ea17f6fb83f1208b4b6c8bc1e8406e05ee5c6ed7957b3d1c29729a8d900105d2ebb8d9f2cfe77dc02b83304ccd8d7ebbe7fe6eade5bfe4816ffb6ad6daf1fdbe7d2b4d696990fe037f5141eab7879c5509aef85806372e13faacf05940901c03a5eafbfa4e95b8aff5d9f01180d0152bb1402a2a300d2f6afb68f31af3708f40600ebb17deecdf3da7b9703f02e657039a9c059f3228fbd01406bcf2cd753f033c5ff786af1ffd69f03ce2eef3dd742c0c8beb5c55c5bc71bea8f0600abed088680c84840663e80bd648b9156f02257c35a211d0d00dab299757a8abed717edf388a5c5ffdb5f04142dc2d7f323783bc01b11c8bc6e3dddfe6821a00c0480769e34df7a1e99961006803d458a4c991c04ac221a0900ed74b65d5a2e1a4aac47ad4d9ad6da6e756700f0460132c5580a04d111016b94407b3d69999182df33fc1f7d1e99b6100680df96293ca3c5bf7e9e29fcdaf3de80105d275bf4bd1100695a6bcbcc7fe508c0cc1070048afdc8be49afa315fe76ba9d278d1cd4ed87f1e8b545a7bdf6510407e05eab8a847581149d8e5c1d47aebc47824166f96c00f0dab469ad2d337fdb2f028a848063c26880b4ad769e345fbb4520058243696be76bf3ace7ed316a28da00aef3d84820c85efdb76dd951816860886c2f7bd5efb569d35a5b66fe4f7e066066083892b7047af74b2af05abb76e5dfb68d040069da6bcf2e03e0779445a3013d01a03708cc78deb65dd3d6a3f55c9ad6dabeea5b01c01b05d096a90b7cbb8c15085ad1205092af1529fcd7e3c8907f3604f0190000f5792d2a52c87a46028e8eabf0194121f23ad9826f0501af3dbbcc54dffe73c047c7ed80b6bdbdead79e8f8c02440bbe34ffda07693f560400adcd6af7303a00bc536f51c914b2990160552088ce9b7dd56fb547e7fff42d80322104f48c06ccba3d6005022f0c5cd3ed6379580088202400f75a593856058048811d0d069965665cf54bd35e7b74fecf078091d1022f0478a3012b6f5d788fdafe6841a04c0800d1f900f6d453b0a285b1771420fb38a3e097e03149d35adbe33c2500440aabb65c5b38232303a381205ae4238ff5be7b6dda748b0000e01b01c09afe4618b01eb357fdde3cafbd77b99f0f00a321a06d97428177557d4cfa9c801640ace2afb5d5c720edb3b69f563ff68e7e00d883757e8816bd4841cd8480ebf9487088ceebbdeab7da7b97db26001c4ad19bf5b98076da1a19c814cb6820d16e0378c5df0b2c47629f29fe00568400afad2710648a7c76deb78aff230aff530340663420130232a301338aa457e8b3055f1bf6f7da22f3b2f8fc00f06ce541416034048cb4f5be7636e858edd9656ef5d40090090147e07301525b4f011eb935a0b5459f1f893050cbee73b4cf01bc53cf392c337fc568c0aaf97714fecc72b77a72008886806bb9c86f09486d52a19d3d2230abf04b6dd6157fbbbcb55c647900bf69b490458be6c855f98c02df33bc5f826d9ac79e539f1e003221405b363b1ad04ecfbe659029fcd63ed76d567b3bafdd1700b0ce57d979b36e0d4497bbb3f0ff4cf17f4b00b0aef0b565ad2bdb994160366b7442dbe7b6dd9ba7e1de3eb097f2a540102df2d6bc9e7522d3bdc7d8bbdc57bd2500ccba25303308cc0a065ed1f70abe378c9f193d0180ecb961d64880373db3d097c0be45e78d2cfb556f0b00336e09d4f38e64f1ed09063db42bff68a091e6b7b8e20710395768b205737620e8998e2ef3f3c5ffad01a0e79680b5ac56f42385ff6acb4c8fc8061a6f5b128201f0dbca8b46045617f9a2b47bf346967d8cb70680ded180237915ed15fea3a3f8af181db0f6b967fb160202f06c2b3fa3f48d5101a96d645b56fbec9190477b7b0018b9f21d0902755bddde53fc577ea8708537ed2b80670700ad7d5581a7f0ff5800e8190db896ef0d02edbc9e8070b54bff20ad50100d0ca3230100509f4ba26685806c7b6f712fc6bc99eb3cce2f0580dea2170902d2fcc80880b4acb6bcd55ecf8ffec3f3b605001933ef89cfba421f29ecc5993f6b9dc7fab500b02a0878f3bd1180e83cef837999e2ff53ff50013cc2ecfbe32baeda29fc9b0780dedb02d73ad15fab1bf9329ec8d7f5660a7ff4eb7f016086d99f925f151632cb487ef67cfaeb0160e45eb855cc23cb68f7f6a3f3b5657a96cde03303c06ffbe66f0944979d55d0477fe3eaa7ed1000667c282eb2ae75851f5dc61b09882c6bc97c6f02807d959bb733bb9853f803760a0033834064fdec0882b56cf61640649f0060c41d43ea7715fd2dcf8f3b06809e623eba7e6474405bb6f7357a710b00f86d7715ba3b3e654fd11fb0730058150622db885ef97bebac28e2dba560005f393f7cebd7f038c7fd0701607e1868b711dd4eef957f665b0070b727dc8fe79c282000ac0f03ed76b2dbca7ef10f00dca1fce008c35608007133bf5a77241044b7d98b2001fcb62715c6a787889f4600f8dea880b6cd6f1764fef30078db3985f3560702c0f3c280f51a16aedc01dca96cfefaaf47009867c5b0fec8eb03c02fe11c371901609d999fea07805d50e86f4200b85fcf770000c02fa2d87f1101e0199ef4214000988922ff500480dffdcf437000301385fcc710007e17ff590100aa3f7d160000387ed4ff052d59e1ec7437f6670000000049454e44ae426082"
        writefile("mm2-glass-shadow-512-v27.png",(hex:gsub("..",function(pair) return string.char(tonumber(pair,16)) end)))
        return getcustomasset("mm2-glass-shadow-512-v27.png")
    end)
    if not ok then return end
    local shadow=A.new("ImageLabel",{Name="GlassOuterShadow",BackgroundTransparency=1,
        Image=id,ImageTransparency=0,ScaleType=Enum.ScaleType.Slice,
        SliceCenter=Rect.new(128,128,384,384),SliceScale=0.55,
        BorderSizePixel=0,Active=false,Selectable=false,
        ZIndex=math.max(0,window.ZIndex-1)},window.Parent)
    local function sync()
        if not A.alive or not window.Parent then return end
        shadow.Position=window.Position+UDim2.fromOffset(-28,-16)
        shadow.Size=window.Size+UDim2.fromOffset(56,56)
        shadow.Visible=window.Visible
        shadow.ZIndex=math.max(0,window.ZIndex-1)
    end
    A.connect(window:GetPropertyChangedSignal("Position"),sync)
    A.connect(window:GetPropertyChangedSignal("Size"),sync)
    A.connect(window:GetPropertyChangedSignal("Visible"),sync)
    A.connect(window:GetPropertyChangedSignal("ZIndex"),sync)
    sync()
end
function A.mountUI()
    A.connect(A.uiHost.DescendantAdded,function(obj)
        if obj:IsA("ScrollingFrame") then A.clipGlassStrokes(obj) end
        if obj.Name=="QosPrismWindow" then A.defer(function() if A.alive and obj.Parent then A.attachOuterShadow(obj) end end) end
        if obj.Name=="GlassPanel" or obj.Name=="QosPrismWindow" or obj.Name:match("^GlassButton_") or obj.Name:match("^GlassInput_") or (obj.Name:match("^Nav_") or obj.Name:match("^VisualTab_")) then
            A.defer(function() if A.alive and obj.Parent then A.glassSurface(obj) end end)
        end
    end)
    A.reactRoot=ReactRoblox.createRoot(A.uiHost)
    A.uiMounted=true; A.renderUI()
    A.spawn(function()
        for _,name in ipairs({"Visuals","Collect","Settings"})do
            task.wait(0.3);if not A.alive then return end
            A.readyPages[name]=true;A.dirty()
        end
    end)
end
function A.resize() end



A.label(A.visualPage, "Red murderer, blue sheriff, gold hero, green innocent.", 28)
A.toggle(A.visualPage, "Murderer ESP", "murdererESP")
A.toggle(A.visualPage, "Sheriff ESP", "sheriffESP")
A.toggle(A.visualPage, "Hero ESP", "heroESP")
A.toggle(A.visualPage,"Dropped gun ESP","droppedGunESP")
A.group(A.visualPage,"Tracers")
local tracerHint=A.addNode(A.visualPage,{kind="text",text="Lines for roles with ESP on.",height=28});tracerHint.visualTab="Tracers"
for _,entry in ipairs({{"Murderer","tracerMurderer"},{"Sheriff","tracerSheriff"},{"Hero / gun holder","tracerHero"},{"Innocent","tracerInnocent"}}) do
    local node=A.toggle(A.visualPage,entry[1],entry[2]);node.visualTab="Tracers"
end
A.group(A.visualPage,"Player ESP")
A.toggle(A.visualPage, "Innocent ESP", "innocentESP")
A.label(A.visualPage, "Without round data, a player with a gun is labeled Gun holder.", 32)

-- One movement owner at a time. Gun, fling and knife sweeps pause collection.
function A.acquireMove(owner)
    if A.movement then return false end
    local ch, hum, root = A.body(A.player)
    if not root or not A.finite(root.Position) then return false end
    A.movement = { owner = owner, character = ch, humanoid = hum, root = root,
        cframe = root.CFrame, autoRotate = hum.AutoRotate, platformStand = hum.PlatformStand }
    return true
end
function A.restoreLocalCollision()
    for part, original in pairs(A.localCollision) do
        pcall(function() part.CanCollide = original end)
    end
    A.localCollision = {}
end
function A.flingContactCollision(move,character)
    move.flingCollision=move.flingCollision or {}
    for _,name in ipairs({"HumanoidRootPart","UpperTorso","LowerTorso","Torso"}) do
        local part=character and character:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            if move.flingCollision[part]==nil then move.flingCollision[part]=part.CanCollide end
            part.CanCollide=true
        end
    end
end
function A.restoreFlingContact(move)
    for part,value in pairs(move.flingCollision or {}) do
        pcall(function()if part.Parent then part.CanCollide=value end end)
    end
    move.flingCollision=nil
end

function A.releaseMove(restorePosition)
    local m = A.movement
    A.movement = nil
    A.restoreLocalCollision()
    if not m then return end
    if m.flingCollision then A.restoreFlingContact(m) end
    if m.walking then
        if A.clearWalkRoute then A.clearWalkRoute(m) end
        pcall(function()
            if m.character == A.player.Character and m.humanoid.Parent then
                m.humanoid:Move(Vector3.zero, false)
                m.humanoid.AutoRotate = m.autoRotate
                if m.appliedWalkSpeed and m.humanoid.WalkSpeed == m.appliedWalkSpeed then
                    m.humanoid.WalkSpeed = m.walkSpeed
                end
            end
        end)
        -- Stopping walking never rewrites position or velocity, including unload.
        return
    end
    pcall(function()
        if m.character == A.player.Character and m.root.Parent then
            m.root.AssemblyLinearVelocity = Vector3.zero
            m.root.AssemblyAngularVelocity = Vector3.zero
            m.humanoid.AutoRotate = m.autoRotate
            m.humanoid.PlatformStand = m.platformStand
            if restorePosition and m.humanoid.Health > 0 and A.finite(m.cframe.Position) then
                m.root.CFrame = m.cframe
            end
        end
    end)
end
function A.noclipLocal()
    local m = A.movement
    if not m or m.owner == "fling" or m.walking then return end
    for _, part in ipairs(A.characterParts(m.character)) do
        if part:IsA("BasePart") then
            if A.localCollision[part] == nil then A.localCollision[part] = part.CanCollide end
            part.CanCollide = false
        end
    end
end
function A.restoreCollision()
    for part, value in pairs(A.collision) do pcall(function() part.CanCollide = value end) end
    A.collision = {}
end
function A.antiFlingStep()
    if not A.config.antiFling or (A.movement and A.movement.owner == "fling") then return end
    if os.clock()-(A.lastCollisionScan or 0)>=0.2 then
    A.lastCollisionScan=os.clock()
    for _, p in ipairs(A.playerList) do
        if p ~= A.player and p.Character then
            for _, part in ipairs(A.characterParts(p.Character)) do
                if part:IsA("BasePart") and part.CanCollide then
                    if A.collision[part] == nil then A.collision[part] = part.CanCollide end
                    part.CanCollide = false
                end
            end
        end
    end
    end
    local _, _, root = A.body(A.player)
    if root and not A.movement then
        local lin, ang = root.AssemblyLinearVelocity, root.AssemblyAngularVelocity
        if not A.finite(lin) or not A.finite(ang) or lin.Magnitude > 220 or ang.Magnitude > 180 then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            if A.lastStable and A.finite(A.lastStable.Position) then root.CFrame = A.lastStable end
        else A.lastStable = root.CFrame end
    end
    for part in pairs(A.collision) do if not part.Parent then A.collision[part] = nil end end
end
A.group(A.combatPage,"Protection")
A.toggle(A.combatPage, "Anti-fling", "antiFling")

-- Silent aim preserves the normal shot origin and firing flow.
function A.aimCursor(camera)
    local scripts=A.player:FindFirstChild("PlayerScripts")
    local mouseLock=scripts and scripts:FindFirstChild("MouseLock")
    -- Match WeaponService, including its custom shift-lock controller.
    if mouseLock and mouseLock:GetAttribute("Enabled")==true
        and A.Input.PreferredInput~=Enum.PreferredInput.Gamepad then
        return camera.ViewportSize*0.5
    end
    return A.Input:GetMouseLocation()
end
function A.gunOrigin()
    local character=A.player.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    local attachment=root and root:FindFirstChild("GunRaycastAttachment")
    if attachment and attachment:IsA("Attachment") then return attachment.WorldPosition end
    local gun=A.findTool(A.player,"Gun")
    local handle=gun and gun:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then return handle.Position end
    return root and root.Position
end
function A.weaponVisible(origin,position,character)
    if not origin then return false end
    local now=os.clock()
    if not A.weaponIgnore or A.weaponIgnoreCharacter~=A.player.Character or now-(A.weaponIgnoreAt or 0)>=0.5 then
        A.weaponIgnore={A.player.Character};A.weaponIgnoreCharacter=A.player.Character;A.weaponIgnoreAt=now
        for _,part in ipairs(A.Tags:GetTagged("WeaponPassthrough"))do table.insert(A.weaponIgnore,part)end
    end
    A.aimRayParams=A.aimRayParams or RaycastParams.new()
    A.aimRayParams.FilterType=Enum.RaycastFilterType.Exclude
    -- Server bullets can hit fully transparent, non-collidable pickups.
    -- Only explicitly tagged weapon passthrough objects are excluded.
    A.aimRayParams.FilterDescendantsInstances=A.weaponIgnore
    local hit=workspace:Raycast(origin,position-origin,A.aimRayParams)
    return not hit or hit.Instance:IsDescendantOf(character)
end

function A.refreshShotCallers(gun)
    if A.shotCallerGun==gun then return end
    A.shotCallerGun=gun
    A.shotCallerScripts={}
    for _,obj in ipairs(gun:GetDescendants()) do
        if obj:IsA("LocalScript") then A.shotCallerScripts[obj]=true end
    end
end
function A.isGunShotCaller(caller)
    if type(caller)~="function" then return false end
    local ok,environment=pcall(getfenv,caller)
    if not ok then return false end
    local callingScript=rawget(environment,"script")
    return callingScript~=nil and A.shotCallerScripts~=nil and A.shotCallerScripts[callingScript]==true
end

function A.isAimTarget(player)
    if player==A.player then return false end
    local character,humanoid,root=A.body(player)
    if not character or not character.Parent or not humanoid or not root then return false end
    if character:GetAttribute("Alive")==false or character:GetAttribute("Dead")==true
        or character:GetAttribute("Killed")==true then return false end
    -- Infection can leave the prior survivor death in round data. The current
    -- living zombie character is authoritative for aim eligibility in that case.
    if A.isZombie(player) then return true end
    return A.role(player)=="Murderer"
end

function A.aimStep(shotCursor)
    A.aimBlocked = A.Input:GetFocusedTextBox() ~= nil
    local camera = workspace.CurrentCamera
    if not camera then return end
    -- ScreenGui.IgnoreGuiInset and WorldToViewportPoint use the same origin.
    local cursor = shotCursor or A.aimCursor(camera)
    if A.fovCircle.Visible ~= A.config.showFov then A.fovCircle.Visible = A.config.showFov end
    if A.config.showFov then
        A.fovCircle.Position = UDim2.fromOffset(cursor.X, cursor.Y)
        if A.lastFovRadius ~= A.config.fov then
            A.lastFovRadius=A.config.fov
            A.fovCircle.Size=UDim2.fromOffset(A.config.fov*2,A.config.fov*2)
        end
        A.fovGradient.Rotation=(os.clock()*45)%360
    end
    if (not A.config.cameraAim and not A.config.silentGunAim) or A.aimBlocked then
        A.aimPoint=nil; A.aimPlayer=nil; A.aimSample=nil; A.aimEligible=false; A.aimCandidates={}; A.lastAimScan=nil
        return
    end
    local now=os.clock()
    if A.config.silentGunAim or shotCursor or not A.lastAimScan or now-A.lastAimScan>=1/30 then
    A.lastAimScan=now
    A.aimCandidates={}
    A.aimPoint=nil; A.aimPlayer=nil; A.aimSample=nil; A.aimEligible=false
    local role = A.role(A.player)
    local gun = A.findTool(A.player, "Gun")
    if not gun or gun.Parent ~= A.player.Character
        or (role ~= "Sheriff" and role ~= "Hero" and role ~= "Gun holder") then return end
    A.refreshShotCallers(gun)
    A.aimEligible = true
    local best = A.config.fov
    for _, p in ipairs(A.playerList) do
        if A.isAimTarget(p) then
            local ch, _, root = A.body(p)
            if ch and root then
                local _,humanoid=A.body(p)
                local sample=A.targetSample(ch,humanoid,root,camera,now)
                if sample then
                    local distance=(sample.screen-cursor).Magnitude
                    table.insert(A.aimCandidates,sample)
                    if distance<best then
                        A.aimSample=sample
                        A.aimPoint,best,A.aimAt,A.aimPlayer=sample.position,distance,now,p
                    end
                end
            end
        end
    end
    end -- target selection runs at 30 Hz; camera steering stays per frame
    if A.config.cameraAim and A.aimPoint and not A.window.Visible and not A.Input:GetFocusedTextBox()
        and A.Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        and (A.aimPoint - camera.CFrame.Position).Magnitude > 0.1 then
        camera.CFrame = CFrame.lookAt(camera.CFrame.Position, A.aimPoint)
    end
end
A.fovCircle = A.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1,
    BorderSizePixel = 0, Visible = false, Active = false, Selectable = false }, A.gui)
A.new("UICorner", { CornerRadius = UDim.new(1, 0) }, A.fovCircle)
A.fovStroke=A.new("UIStroke", { Color=Color3.new(1,1,1), Transparency=0.04, Thickness=1 }, A.fovCircle)
local rainbow={}
for i=0,3 do rainbow[i+1]=ColorSequenceKeypoint.new(i/3,Color3.fromHSV(i/3,1,1)) end
A.fovGradient=A.new("UIGradient",{Color=ColorSequence.new(rainbow)},A.fovStroke)
-- Change only WeaponService's target result; never intercept FireServer.
-- Called by the game's weapon thread: consume plain cached values only.
-- Executor-owned UI instances must only be accessed by the render callback.
-- Runs in the render thread; the weapon callback receives values, never UI instances.
-- Runs in the render thread; the weapon callback receives values, never UI instances.
function A.gunAimPoint(part,root,humanoid)
    local velocity=root.AssemblyLinearVelocity
    if not A.finite(velocity)or velocity.Magnitude>100 then velocity=Vector3.zero end
    local airborne=humanoid.FloorMaterial==Enum.Material.Air
    if not airborne then velocity=Vector3.new(velocity.X,0,velocity.Z)end
    local lead=A.config.prediction or 0
    local combat=A.config.farm and A.collectorCombatRole=="Sheriff"
    if combat then
        -- Gunfire is hitscan: cover replication/dispatch delay, not bullet travel.
        local ping=A.player:GetNetworkPing()
        if type(ping)~="number"or ping~=ping or ping<0 or ping>1 then ping=0 end
        lead=math.max(lead,math.min(ping+1/60,0.12))
    end
    local displacement=velocity*lead
    local state=humanoid:GetState()
    local ballistic=combat and airborne and(state==Enum.HumanoidStateType.Jumping or state==Enum.HumanoidStateType.Freefall)
    if ballistic then
        displacement=displacement-Vector3.new(0,workspace.Gravity*lead*lead/2,0)
        -- Stop a descending prediction at the landing surface rather than below it.
        local projected=root.Position+displacement
        if displacement.Y<0 then
            local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances={A.player.Character,root.Parent};params.RespectCanCollide=true
            local floor=workspace:Raycast(Vector3.new(projected.X,root.Position.Y+3,projected.Z),Vector3.new(0,-20,0),params)
            if floor and floor.Normal.Y>=0.6 then
                local leg=root.Parent:FindFirstChild("Left Leg")
                local height=humanoid.HipHeight+root.Size.Y/2
                    +(humanoid.RigType==Enum.HumanoidRigType.R6 and leg and leg.Size.Y or 0)
                local landing=floor.Position.Y+height
                if projected.Y<landing and root.Position.Y>=landing-0.5 then
                    displacement=Vector3.new(displacement.X,landing-root.Position.Y,displacement.Z)
                end
            end
        end
    end
    return part.Position+displacement,velocity,lead,ballistic
end
function A.targetSample(character,humanoid,root,camera,now)
    local origin=A.config.silentGunAim and A.gunOrigin() or camera.CFrame.Position
    if not origin then return end
    local torso=character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or root
    local velocity=root.AssemblyLinearVelocity
    if not A.finite(velocity) or velocity.Magnitude>100 then velocity=Vector3.zero end
    -- Grounded character vertical velocity is commonly contact jitter.
    if humanoid.FloorMaterial~=Enum.Material.Air then velocity=Vector3.new(velocity.X,0,velocity.Z) end
    local lead=A.config.prediction
    local function sample(part)
        if not part or not part:IsA("BasePart") then return end
        local position=A.gunAimPoint(part,root,humanoid)
        if not A.finite(position) or not A.weaponVisible(origin,position,character) then return end
        local screen,onScreen=camera:WorldToViewportPoint(part.Position)
        if not onScreen then return end
        return {position=position,velocity=velocity,screen=Vector2.new(screen.X,screen.Y),at=now,part=part,root=root,character=character,humanoid=humanoid}
    end
    local candidate=sample(torso)
    if not candidate and torso~=root then candidate=sample(root) end
    return candidate
end
function A.redirectGunTarget(original,shotCursor)
    if not A.alive or not A.config.silentGunAim
        or A.aimBlocked~=false or not A.aimEligible then return original end
    local candidate=A.aimSample
    if shotCursor then
        candidate=nil
        local best=A.config.fov
        for _,sample in ipairs(A.aimCandidates or {}) do
            local distance=(sample.screen-shotCursor).Magnitude
            if distance<best then candidate,best=sample,distance end
        end
    end
    if not candidate then return original end
    local age=os.clock()-candidate.at
    if age<0 or age>0.1 then return original end
    local part,root,character,humanoid=candidate.part,candidate.root,candidate.character,candidate.humanoid
    if not part or not root or not character or not humanoid
        or not character.Parent or humanoid.Health<=0
        or not part:IsDescendantOf(character) or not root:IsDescendantOf(character) then return original end
    -- Read replicated world parts at fire time. Do not extrapolate an old velocity
    -- over the sample age: a stop or direction reversal invalidates that estimate.
    local velocity=root.AssemblyLinearVelocity
    if not A.finite(velocity) or velocity.Magnitude>100 then velocity=Vector3.zero end
    if humanoid.FloorMaterial~=Enum.Material.Air then velocity=Vector3.new(velocity.X,0,velocity.Z) end
    local point,velocity,lead,ballistic=A.gunAimPoint(part,root,humanoid)
    if not A.finite(point) or not A.weaponVisible(A.gunOrigin(),point,character) then return original end
    local value
    if typeof(original)=="CFrame" then value=CFrame.new(point)*original.Rotation
    elseif typeof(original)=="Vector3" then value=point
    else return original end
    A.silentRedirects=(A.silentRedirects or 0)+1
    if A.collectorCombatRole=="Sheriff"then
        A.log("combat_gun_motion_aim",{point=point,position=part.Position,velocity=velocity,lead=lead,ballistic=ballistic,state=humanoid:GetState()})
    end
    return value
end

function A.releaseWeaponHooks()
    if A.config.silentGunAim or A.collectorCombatRole then return end
    for _,entry in ipairs(A.weaponAimWrappers or {}) do
        if entry.service[entry.key]==entry.wrapper then entry.service[entry.key]=entry.original end
    end
    A.weaponAimWrappers={}
end
function A.disableSilentAim() A.releaseWeaponHooks() end
function A.ensureWeaponHooks()
    if A.weaponAimWrappers and #A.weaponAimWrappers>0 then return true end
    local services=A.RS:FindFirstChild("ClientServices")
    local module=services and services:FindFirstChild("WeaponService")
    if not module then return false end
    local ok,service=pcall(require,module)
    if not ok or type(service)~="table" then return false end
    A.weaponAimWrappers={}
    local installed,err=pcall(function()
        for _,key in ipairs({"GetMouseTargetCFrame","GetTargetPosition"}) do
            local original=service[key]
            assert(type(original)=="function",key.." unavailable")
            local wrapper=function(...)
                if not A.alive then return original(...) end
                -- Capture the game caller before checking the gun firing script.
                local caller=debug.info(2,"f")
                local results=table.pack(original(...))
                local collectorResolved=false
                if A.collectorCombatRole and A.collectorCombatAim then
                    local value,resolved=A.collectorCombatAim(results[1],caller)
                    results[1]=value;collectorResolved=resolved==true
                end
                if not collectorResolved and A.config.silentGunAim and A.isGunShotCaller(caller) and not A.silentResolving then
                    local cursor
                    if key=="GetTargetPosition" then
                        local args=table.pack(...)
                        local offset=type(args[1])=="number" and 0 or 1
                        if type(args[1+offset])=="number" and type(args[2+offset])=="number" then
                            cursor=Vector2.new(args[1+offset],args[2+offset])
                        end
                    end
                    A.silentResolving=true
                    local success,target=pcall(A.redirectGunTarget,results[1],cursor)
                    A.silentResolving=false
                    if success then results[1]=target else warn("[qos-MM2 aim] "..tostring(target)) end
                end
                return table.unpack(results,1,results.n)
            end
            service[key]=wrapper
            table.insert(A.weaponAimWrappers,{service=service,key=key,original=original,wrapper=wrapper})
        end
    end)
    if not installed then
        for _,entry in ipairs(A.weaponAimWrappers) do
            if entry.service[entry.key]==entry.wrapper then entry.service[entry.key]=entry.original end
        end
        A.weaponAimWrappers={};A.note("Weapon hooks",tostring(err));return false
    end
    return true
end
function A.enableSilentAim() return A.ensureWeaponHooks() end

A.group(A.combatPage,"Aim")
A.toggle(A.combatPage, "Silent aim (visible murderer)", "silentGunAim", A.enableSilentAim)

A.toggle(A.combatPage, "Camera aim assist (hold right mouse)", "cameraAim")
A.toggle(A.combatPage, "Show aim circle", "showFov")
A.number(A.combatPage, "Aim radius (pixels)", "fov", 30, 500)
A.number(A.combatPage, "Prediction (seconds)", "prediction", 0, 0.3)
A.label(A.combatPage, "Uses the gun's line of sight. Typing pauses it.", 32)
function A.killAll()
    if not A.alive or A.role(A.player) ~= "Murderer" then
        A.note("Kill all", "Murderer only"); return false
    end
    local knife = A.findTool(A.player, "Knife")
    if not knife then A.note("Kill all", "No knife"); return false end
    local targets = {}
    for _, player in ipairs(A.playerList) do
        if player ~= A.player and A.role(player) ~= "Dead" and A.body(player) then
            table.insert(targets, player)
        end
    end
    if #targets == 0 then A.note("Kill all", "No living targets"); return false end
    if A.movement and A.movement.owner == "farm" then A.releaseMove(true) end
    if not A.acquireMove("knifeSweep") then
        A.note("Kill all", "Already moving"); return false
    end
    local move = A.movement
    A.note("Kill all", "Sweeping " .. #targets)
    A.spawn(function()
        local attempted = 0
        local function active()
            return A.alive and A.movement == move and move.character == A.player.Character
                and move.humanoid.Health > 0 and A.role(A.player) == "Murderer"
                and knife.Parent ~= nil
        end
        local ok, err = pcall(function()
            if not active() then return end
            move.humanoid:EquipTool(knife)
            task.wait(0.15)
            for _, target in ipairs(targets) do
                if not active() then break end
                local tried = false
                for _ = 1, 3 do
                    if not active() or A.role(target) == "Dead" then break end
                    local targetCharacter, _, targetRoot = A.body(target)
                    if not targetRoot or not A.finite(targetRoot.Position)
                        or targetRoot.Position.Y <= workspace.FallenPartsDestroyHeight + 15 then break end
                    if knife.Parent ~= move.character then move.humanoid:EquipTool(knife) end
                    move.root.AssemblyLinearVelocity = Vector3.zero
                    move.root.AssemblyAngularVelocity = Vector3.zero
                    move.root.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 2)
                    task.wait(0.1)
                    if not active() then break end
                    local freshCharacter, _, freshRoot = A.body(target)
                    if freshCharacter ~= targetCharacter or not freshRoot or A.role(target) == "Dead" then break end
                    knife:Activate()
                    tried = true
                    local handle = knife:FindFirstChild("Handle", true)
                    local hitPart = freshCharacter:FindFirstChild("UpperTorso")
                        or freshCharacter:FindFirstChild("Torso") or freshRoot
                    if handle and handle:IsA("BasePart") and type(firetouchinterest) == "function" then
                        pcall(function()
                            firetouchinterest(handle, hitPart, 0)
                            firetouchinterest(handle, hitPart, 1)
                        end)
                    end
                    task.wait(0.45)
                end
                if tried then attempted = attempted + 1 end
            end
        end)
        if A.movement == move then A.releaseMove(true) end
        if A.alive then
            A.note("Kill all", ok and ("Sweep ended: attacked " .. attempted .. "/" .. #targets
                .. " targets; server-confirmed kills are not guaranteed") or ("Stopped: " .. tostring(err)))
        end
    end)
    return true
end
A.group(A.combatPage,"Knife")
A.button(A.combatPage, "Kill all (murderer)", A.killAll)
A.button(A.combatPage, "Stop kill all", function()
    if A.movement and A.movement.owner == "knifeSweep" then A.releaseMove(true) end
end)
A.label(A.combatPage, "Stops on death, role change, or cancel.", 28)
A.group(A.combatPage,"Players")
A.targetBox = A.input(A.combatPage, "Fling target: exact username or unique prefix", "", function() end)
function A.flingContactPoint(root,elapsed,dt)
    local velocity=root.AssemblyLinearVelocity
    if not A.finite(velocity) or velocity.Magnitude>100 then velocity=Vector3.zero end
    local lead=math.clamp(dt or 1/60,0,0.05)
    local offset=Vector3.new(math.cos(elapsed*45)*0.65,0.15,math.sin(elapsed*45)*0.65)
    return root.Position+velocity*lead+offset,velocity
end

function A.fling()
    local query = A.targetBox.Text:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then A.note("Fling", "Enter a username"); return end
    local matches, target = {}, nil
    for _, p in ipairs(A.playerList) do
        if p ~= A.player then
            if p.Name:lower() == query then target = p; break end
            if p.Name:lower():sub(1, #query) == query then table.insert(matches, p) end
        end
    end
    if not target and #matches == 1 then target = matches[1] end
    if not target then A.note("Fling", "No match"); return end
    if not A.body(target) then A.note("Fling", "Target is dead"); return end
    if A.movement and A.movement.owner == "farm" then A.releaseMove(true) end
    if not A.acquireMove("fling") then A.note("Fling", "Already moving"); return end
    A.restoreCollision()
    A.note("Fling", "Attempting " .. target.Name .. " (3 seconds maximum)")
    A.spawn(function()
        local m = A.movement
        local ok, err = pcall(function()
            local started = os.clock()
            local targetCharacter=target.Character
            m.humanoid.AutoRotate = false
            m.humanoid.PlatformStand = true
            while A.alive and A.movement == m and os.clock() - started < 3 do
                local dt=A.Run.PreSimulation:Wait()
                if not A.alive or A.movement~=m or m.humanoid.Health<=0 or os.clock()-started>=3 then break end
                local _, _, targetRoot = A.body(target)
                if not targetRoot or target.Character~=targetCharacter or m.character ~= A.player.Character then break end
                if not A.finite(targetRoot.Position) or targetRoot.Position.Y < workspace.FallenPartsDestroyHeight + 25 then break end
                A.flingContactCollision(m,m.character)
                A.flingContactCollision(m,targetCharacter)
                local elapsed = os.clock() - started
                local point,velocity=A.flingContactPoint(targetRoot,elapsed,dt)
                if not A.finite(point) then break end
                m.root.CFrame = CFrame.new(point)
                m.root.AssemblyAngularVelocity = Vector3.new(0, 15000, 0)
                m.root.AssemblyLinearVelocity = velocity
            end
        end)
        if A.movement == m then A.releaseMove(true) end
        if A.alive then A.note("Fling", ok and "Fling done" or tostring(err)) end
    end)
end
A.button(A.combatPage, "Fling selected player", A.fling)
A.button(A.combatPage, "Stop movement", function() A.set("farm", false); A.releaseMove(true) end)

-- ESP objects are owned by this script and replaced on respawn.
function A.clearESP(player)
    local e = A.esp[player]
    if e then if e.tracer then e.tracer:Destroy() end; e.highlight:Destroy(); e.billboard:Destroy(); A.esp[player] = nil end
end
function A.espStepUnsafe()
    A.gunESPStep()
    local createdThisTick=0
    if not (A.config.murdererESP or A.config.sheriffESP or A.config.heroESP or A.config.innocentESP) then
        for p in pairs(A.esp) do A.clearESP(p) end
        return
    end
    for _, p in ipairs(A.playerList) do
        if p ~= A.player then
            local role = A.role(p)
            local enabled = (role == "Murderer" and A.config.murdererESP)
                or (role == "Sheriff" and A.config.sheriffESP)
                or (role == "Hero" and A.config.heroESP)
                or (role == "Innocent" and A.config.innocentESP)
                or (role == "Gun holder" and (A.config.heroESP or A.config.sheriffESP))
            local ch, _, root = A.body(p)
            if not enabled or not ch then A.clearESP(p)
            else
                local e = A.esp[p]
                if e and e.character ~= ch then A.clearESP(p); e = nil end
                if not e and createdThisTick>=2 then continue end
                if not e then
                    createdThisTick+=1
                    local h = A.new("Highlight", { Adornee = ch, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                        FillTransparency = 0.7, OutlineTransparency = 0 }, A.worldGui)
                    local bb = A.new("BillboardGui", { Adornee = ch:FindFirstChild("Head") or root,
                        AlwaysOnTop = true, Size = UDim2.fromOffset(220, 40), StudsOffset = Vector3.new(0, 2.5, 0) }, A.worldGui)
                    local text = A.new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
                        Font = Enum.Font.GothamBold, TextSize = 13, TextStrokeTransparency = 0.2 }, bb)
                    e = { character = ch, highlight = h, billboard = bb, text = text }; A.esp[p] = e
                end
                if not e.highlight.Enabled then e.highlight.Enabled=true end
                if not e.billboard.Enabled then e.billboard.Enabled=true end
                local color = role == "Murderer" and A.colors.red or role == "Sheriff" and A.colors.blue
                    or role == "Innocent" and A.colors.green or A.colors.gold
                local displayRole=A.isZombie(p) and "Zombie" or role
                if e.lastRole~=displayRole then
                e.lastRole=displayRole
                e.highlight.FillColor, e.highlight.OutlineColor = color, color
                e.text.TextColor3 = color
                e.text.Text = p.Name .. "  |  " .. displayRole
                end
            end
        end
    end
end

function A.espStep()
    if os.clock()<(A.nextEspRetry or 0)then return end
    local ok,err=pcall(A.espStepUnsafe)
    if not ok then
        A.nextEspRetry=os.clock()+2
        A.log("esp_error",{error=tostring(err)})
        A.note("ESP",tostring(err))
    end
end

-- Collection uses only live map parts. Touch simulation requires executor support.
function A.touch(part)
    local _, _, root = A.body(A.player)
    if not root or not part or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then return false end
    if type(firetouchinterest) ~= "function" then return false end
    local ok = pcall(function() firetouchinterest(root, part, 0); firetouchinterest(root, part, 1) end)
    return ok
end
-- Shared dropped-weapon detection. Tagged equipped tools are explicitly excluded.
function A.dropPart(obj)
    if not obj or not obj:IsDescendantOf(workspace) then return nil end
    for _,p in ipairs(A.playerList) do if p.Character and obj:IsDescendantOf(p.Character) then return nil end end
    local part=obj:IsA("BasePart") and obj or obj:FindFirstChild("Handle",true) or obj:FindFirstChildWhichIsA("BasePart",true)
    return part and part:IsA("BasePart") and part or nil
end
function A.drop()
    if A.cachedDrop and A.dropPart(A.cachedDrop) then return A.dropPart(A.cachedDrop) end
    A.cachedDrop=nil
    for _,tag in ipairs({"GunDrop","DroppedGun","Weapon_Gun"}) do
        for _,obj in ipairs(A.Tags:GetTagged(tag)) do
            local part=A.dropPart(obj)
            if part then A.cachedDrop=obj;return part end
        end
    end
    if os.clock()-(A.lastDropLookup or -10)<0.75 then return nil end
    A.lastDropLookup=os.clock()
    local obj=workspace:FindFirstChild("GunDrop",true) or workspace:FindFirstChild("DroppedGun",true)
    local part=A.dropPart(obj)
    if part then A.cachedDrop=obj end
    return part
end
A.connect(workspace.DescendantAdded,function(obj)
    if obj.Name=="GunDrop" or obj.Name=="DroppedGun" then A.cachedDrop=obj;A.lastDropLookup=0 end
end)
function A.clearGunESP()
    if A.gunESP then A.gunESP.highlight:Destroy();A.gunESP.billboard:Destroy();A.gunESP=nil end
end
function A.gunESPStep()
    local part=A.config.droppedGunESP and A.drop()
    if not part then A.clearGunESP();return end
    if A.gunESP and A.gunESP.part~=part then A.clearGunESP() end
    if not A.gunESP then
        local highlight=A.new("Highlight",{Name="DroppedGunHighlight",Adornee=part,DepthMode=Enum.HighlightDepthMode.AlwaysOnTop,
            FillColor=A.colors.gold,OutlineColor=A.colors.gold,FillTransparency=0.65},A.worldGui)
        local billboard=A.new("BillboardGui",{Name="DroppedGunLabel",Adornee=part,AlwaysOnTop=true,
            Size=UDim2.fromOffset(180,30),StudsOffset=Vector3.new(0,1.5,0)},A.worldGui)
        A.new("TextLabel",{BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Text="Dropped gun",
            Font=Enum.Font.GothamMedium,TextSize=13,TextColor3=A.colors.gold,TextStrokeTransparency=0.3},billboard)
        A.gunESP={part=part,highlight=highlight,billboard=billboard}
    end
end
-- Resolve roles and ESP membership at the ESP cadence, not on the render path.
function A.refreshTracers()
    A.tracers=A.tracers or {};A.tracerTargets={}
    for p,entry in pairs(A.esp) do
        local role=entry.lastRole
        local enabled=(role=="Murderer" and A.config.tracerMurderer)
            or (role=="Sheriff" and A.config.tracerSheriff)
            or ((role=="Hero" or role=="Gun holder") and A.config.tracerHero)
            or (role=="Innocent" and A.config.tracerInnocent)
        local _,hum,root=A.body(p)
        local line=A.tracers[p]
        if enabled and root then
            if not line then
                line=A.new("Frame",{Name="ESPTracer",AnchorPoint=Vector2.new(0.5,0.5),
                    BorderSizePixel=0,BackgroundTransparency=0.4,Active=false,ZIndex=2,Visible=false},A.worldGui)
                A.tracers[p]=line
            end
            line.BackgroundColor3=entry.text.TextColor3
            table.insert(A.tracerTargets,{player=p,root=root,humanoid=hum,line=line,
                footOffset=hum.HipHeight+root.Size.Y*0.5})
        elseif line then line.Visible=false end
    end
    for p,line in pairs(A.tracers) do
        if not A.esp[p] then line:Destroy();A.tracers[p]=nil end
    end
end
function A.tracerStep()
    local camera=workspace.CurrentCamera
    if not camera then return end
    local origin=Vector2.new(camera.ViewportSize.X/2,camera.ViewportSize.Y-12)
    for _,target in ipairs(A.tracerTargets or {}) do
        local line=target.line
        if not line.Parent then continue end
        if not target.root.Parent or target.humanoid.Health<=0 or not A.espAlive(target.player) then
            line.Visible=false
            local entry=A.esp[target.player]
            if entry then entry.highlight.Enabled=false;entry.billboard.Enabled=false end
            continue
        end
        -- Join the lower edge of the highlighted character, not its torso.
        local foot=target.root.Position-Vector3.new(0,target.footOffset,0)
        local screen,visible=camera:WorldToViewportPoint(foot)
        if visible then
            local finish=Vector2.new(screen.X,screen.Y)
            local delta=finish-origin;local mid=(finish+origin)/2
            line.Position=UDim2.fromOffset(mid.X,mid.Y)
            line.Size=UDim2.fromOffset(delta.Magnitude,1.5)
            line.Rotation=math.deg(math.atan2(delta.Y,delta.X))
        end
        line.Visible=visible
    end
end

function A.collectorTeleportBlocked(state)
    if not state or not state.blocked then return false end
    local untilAt=state.blockedUntil or state.nextAt or 0
    if os.clock()<untilAt then return true end
    state.blocked=nil;state.blockedUntil=nil
    A.log("teleport_backoff_finished",{})
    return false
end
function A.collectorPositionReady()
    return not A.collectorPositionTransaction and os.clock()>=(A.collectorPositionSettleUntil or 0)
end
function A.collectorPositionBegin(kind)
    if not A.collectorPositionReady()then return nil end
    local token={kind=kind,at=os.clock()}
    A.collectorPositionTransaction=token
    return token
end
function A.collectorPositionFinish(token)
    if A.collectorPositionTransaction==token then
        A.collectorPositionTransaction=nil
        A.collectorPositionSettleUntil=os.clock()+0.75
    end
end

function A.grabGun()
    if not A.collectorPositionReady()then return end
    if os.clock()<(A.nextGunAttempt or 0) then return end
    local state=getgenv().QOS_MM2_TP_STATE
    if not state then state={};getgenv().QOS_MM2_TP_STATE=state end
    if A.collectorTeleportBlocked(state)then return end
    if A.findTool(A.player,"Gun") then A.note("Gun pickup","Already have a gun");return end
    if A.role(A.player)=="Murderer" then A.note("Gun pickup","Murderer");return end
    if not A.inRound() then A.note("Gun pickup","Not in a round");return end
    local drop=A.drop()
    if not drop then A.note("Gun pickup","No gun on the ground");return end
    if not A.acquireMove("gun") then return end
    local m=A.movement
    local transaction=A.collectorPositionBegin("gun_pickup")
    if not transaction then A.releaseMove(false);return end
    local prompt=drop:FindFirstChildWhichIsA("ProximityPrompt",true)
        or(drop.Parent and drop.Parent:FindFirstChildWhichIsA("ProximityPrompt",true))
    local started=os.clock()
    local contactSeconds
    local ok,err=pcall(function()
        local destination=drop.CFrame+Vector3.new(0,0.5,0)
        A.log("gun_teleport",{origin=m.root.Position,destination=destination.Position,cooldown=A.config.farm and 2 or 0.12})
        local contactAt=os.clock()
        m.root.CFrame=destination
        local touched=A.touch(drop)
        if not touched and prompt and type(fireproximityprompt)=="function"then pcall(fireproximityprompt,prompt)end
        -- Synthetic contact is sent synchronously; await replication only after returning.
        -- Without touch support, allow one physical contact frame, never a replication wait here.
        if not touched and not A.findTool(A.player,"Gun")then A.Run.Heartbeat:Wait()end
        contactSeconds=os.clock()-contactAt
    end)
    if A.movement==m then
        A.releaseMove(true)
        A.log("gun_teleport_return",{position=m.root.Parent and m.root.Position,original=m.cframe.Position,acquired=A.findTool(A.player,"Gun")~=nil,contactSeconds=contactSeconds})
    end
    A.collectorPositionFinish(transaction)
    A.lastGunTripSeconds=os.clock()-started
    -- Gun pickup retries are independent of emergency escape cooldown.
    A.nextGunAttempt=os.clock()+(A.config.farm and 2 or 0.12)
    -- The player is back at the original position throughout confirmation.
    local deadline=os.clock()+0.35
    while ok and A.alive and A.player.Character==m.character and not A.findTool(A.player,"Gun")and os.clock()<deadline do
        A.Run.Heartbeat:Wait()
    end
    A.log("gun_pickup_confirmed",{acquired=A.findTool(A.player,"Gun")~=nil,contactSeconds=contactSeconds,tripSeconds=A.lastGunTripSeconds,confirmationSeconds=os.clock()-started-A.lastGunTripSeconds,ok=ok,error=not ok and tostring(err)})
    if A.alive then A.note("Gun pickup",not ok and tostring(err)
        or (A.findTool(A.player,"Gun") and "Gun acquired" or "Waiting for pickup confirmation")) end
end

function A.coins()
    local container=A.collectContainer
    if not container or not container:IsDescendantOf(workspace) then
        if os.clock()-(A.lastContainerLookup or -10)>=2 then
            A.lastContainerLookup=os.clock()
            container=workspace:FindFirstChild("CoinContainer",true) or workspace:FindFirstChild("CandyContainer",true)
            A.collectContainer=container
        end
    end
    local found, seen = {}, {}
    local function add(part)
        if part and part:IsA("BasePart") and not seen[part] and part:IsDescendantOf(workspace)
            and part:GetAttribute("Collected") ~= true and part:GetAttribute("Collected") ~= "true"
            and (not part.Parent or (part.Parent:GetAttribute("Collected") ~= true and part.Parent:GetAttribute("Collected") ~= "true")) then
            seen[part] = true; table.insert(found, part)
        end
    end
    if container then
        for _, obj in ipairs(container:GetChildren()) do
            if obj:IsA("BasePart") then add(obj)
            else add(obj:FindFirstChild("Coin", true) or obj:FindFirstChild("Candy", true)
                or obj:FindFirstChildWhichIsA("BasePart", true)) end
        end
    end
    for _, tag in ipairs({ "Coin", "Coin_Server", "Candy" }) do
        for _, obj in ipairs(A.Tags:GetTagged(tag)) do
            add(obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true))
        end
    end
    return found
end
A.coinCache, A.coinSkip, A.lastScan = {}, setmetatable({}, { __mode = "k" }), 0
function A.coinActive(part)
    return part and part.Parent and part:IsDescendantOf(workspace)
        and part:GetAttribute("Collected") ~= true and part:GetAttribute("Collected") ~= "true"
        and part.Parent:GetAttribute("Collected") ~= true and part.Parent:GetAttribute("Collected") ~= "true"
end
function A.clearWalkRoute(move,keepMotion)
    if not keepMotion then move.walkDirection=Vector3.zero;move.smoothDirection=Vector3.zero end
    move.routeTarget=nil
    if move.blockedConnection then move.blockedConnection:Disconnect(); move.blockedConnection = nil end
    if move.path then pcall(function() move.path:Destroy() end); move.path = nil end
    move.waypoints, move.pathIndex, move.jumpedIndex = nil, nil, nil
    move.jumpPending,move.jumpRequestedIndex=false,nil
end
function A.collectorTargetCoolingDown(target)
    local untilAt=A.coinSkip[target]or 0
    if untilAt<=os.clock()then return false end
    local failed=A.collectorCombatFailures and A.collectorCombatFailures[target]
    if failed and(target.Position-failed.position).Magnitude>=8 then
        A.coinSkip[target]=nil;A.collectorCombatFailures[target]=nil
        A.log("combat_retry_moved",{target=target,previous=failed.position,position=target.Position})
        return false
    end
    return true
end
function A.skipCollectorTarget(move,target,reason,seconds)
    local player=A.collectorCombatTarget
    if target and player and target.Parent==player.Character and A.collectorCombatRole
        and not A.collectorCollectingCoins()then
        seconds=math.min(seconds or 15,3)
        A.collectorCombatFailures=A.collectorCombatFailures or setmetatable({},{__mode="k"})
        A.collectorCombatFailures[target]={position=target.Position}
    end
    A.log("target_skipped",{target=target,reason=reason,cooldown=seconds,position=move.root.Position})
    if target==A.collectorEscape then
        A.collectorEscapeFailed=true
        A.collectorEscapeAttempt=(A.collectorEscapeAttempt or 0)+1
    elseif target then
        A.coinSkip[target]=os.clock()+(seconds or 15)
    end
    if move.target==target then move.target=nil end
    move.arrivedAt=nil;move.replan=false;move.nextPlanAt=0
    move.stallRecoveries=0;move.lastProgressAt=os.clock();move.lastProgressPosition=move.root.Position
    move.motionWindowPosition=nil;move.recoveryGoal=nil
    local keep=A.collectorCoast(move)
    if not keep then A.clearWalkRoute(move)end
    A.note("Collector",reason)
end

function A.collectorZombieCombat()
    if not A.config.farm then return false end
    local data=A.roundData(A.player)
    if data and(data.Role=="Survivor"or data.Role=="Zombie")then return true end
    if A.isZombie(A.player)or A.collectorShootWhileCollecting then return true end
    for _,player in ipairs(A.playerList)do
        if A.isZombie(player)and A.espAlive(player)then return true end
    end
    return false
end
function A.collectorRestoreZombieCamera()
    local saved=A.collectorZombieSavedCamera
    if saved then
        A.player.CameraMinZoomDistance=saved.min;A.player.CameraMaxZoomDistance=saved.max
        A.player.CameraMode=saved.mode;A.collectorZombieSavedCamera=nil
    end
end
function A.collectorZombieCameraStep(dt)
    local player=A.player
    if not A.collectorZombieCombat()then A.collectorRestoreZombieCamera();return false end
    A.collectorFirstPerson(false)
    if not A.collectorZombieSavedCamera then
        A.collectorZombieSavedCamera={mode=player.CameraMode,min=player.CameraMinZoomDistance,max=player.CameraMaxZoomDistance}
    end
    player.CameraMode=Enum.CameraMode.Classic
    player.CameraMaxZoomDistance=math.max(8,A.collectorZombieSavedCamera.max);player.CameraMinZoomDistance=8
    local gun=A.findTool(player,"Gun")
    local target=A.collectorShootWhileCollecting and A.collectorDefensiveTarget or A.collectorCombatTarget
    local character,h,root;if target then character,h,root=A.body(target)end
    local camera=workspace.CurrentCamera
    local part=character and(character:FindFirstChild("UpperTorso")or character:FindFirstChild("Torso")or root)
    if not A.collectorActiveRound or not gun or gun.Parent~=player.Character or not h or h.Health<=0 or not part or not camera
        or not A.weaponVisible(A.gunOrigin(),part.Position,character)then return true end
    local delta=part.Position-camera.CFrame.Position
    if delta.Magnitude<0.1 then return true end
    camera.CFrame=camera.CFrame:Lerp(CFrame.lookAt(camera.CFrame.Position,part.Position),1-math.exp(-math.clamp(dt or 1/60,0,0.1)*10))
    local screen,onScreen=camera:WorldToViewportPoint(part.Position)
    if onScreen and not A.Input:GetFocusedTextBox()then
        local ok,err=pcall(function()
            game:GetService("VirtualInputManager"):SendMouseMoveEvent(screen.X,screen.Y,game)
        end)
        if not ok and os.clock()>=(A.nextZombieCursorError or 0)then
            A.nextZombieCursorError=os.clock()+10;A.log("third_person_cursor_error",{error=tostring(err)})
        end
    end
    return true
end
function A.collectorFirstPerson(active)
    if active and A.collectorZombieCombat()then active=false end
    if active then
        local entering=not A.collectorSavedCameraMode
        if entering then
            A.collectorSavedCameraMode=A.player.CameraMode
            A.collectorSavedZoom={min=A.player.CameraMinZoomDistance,max=A.player.CameraMaxZoomDistance}
        end
        A.player.CameraMinZoomDistance=0.5;A.player.CameraMaxZoomDistance=0.5
        if A.player.CameraMode~=Enum.CameraMode.LockFirstPerson then A.player.CameraMode=Enum.CameraMode.LockFirstPerson end
        if entering then
            local head=A.player.Character and A.player.Character:FindFirstChild("Head")
            local camera=workspace.CurrentCamera
            if head and camera then camera.CFrame=CFrame.new(head.Position)*camera.CFrame.Rotation end
        end
    elseif A.collectorSavedCameraMode then
        local zoom=A.collectorSavedZoom
        if zoom then A.player.CameraMaxZoomDistance=zoom.max;A.player.CameraMinZoomDistance=zoom.min end
        A.player.CameraMode=A.collectorSavedCameraMode;A.collectorSavedCameraMode=nil;A.collectorSavedZoom=nil
    end
end
function A.collectorCombatCameraReady(camera,point)
    local head=A.player.Character and A.player.Character:FindFirstChild("Head")
    if not camera or not head or A.player.CameraMode~=Enum.CameraMode.LockFirstPerson
        or(camera.CFrame.Position-head.Position).Magnitude>1.5 then return false,"camera_zoom"end
    local direction=point-camera.CFrame.Position
    if direction.Magnitude<=0.01 or camera.CFrame.LookVector:Dot(direction.Unit)<=0.985 then return false,"camera_alignment"end
    return true
end
function A.collectorPathCameraStep(dt)
    -- Walking leaves camera control to the normal Roblox camera.
end
function A.collectorCameraStep(dt)
    if A.collectorZombieCameraStep(dt)then return end
    local target=A.collectorCombatTarget
    if A.collectorShootWhileCollecting then target=A.collectorDefensiveTarget end
    local weapon=A.collectorCombatWeapon
    local character,humanoid,root
    if target then character,humanoid,root=A.body(target)end
    local camera=workspace.CurrentCamera
    local point=character and(character:FindFirstChild("UpperTorso")or character:FindFirstChild("Torso")or root)
    local fighting=A.config.farm and A.collectorCombatRole~=nil and weapon and weapon.Parent==A.player.Character
        and humanoid and humanoid.Health>0 and point and camera
        and A.collectorCombatVisible(A.gunOrigin()or camera.CFrame.Position,point.Position,character)
    A.collectorFirstPerson(fighting and true or false)
    if not fighting then A.collectorPathCameraStep(dt);return end
    if(point.Position-camera.CFrame.Position).Magnitude<0.1 then return end
    local desired=CFrame.lookAt(camera.CFrame.Position,point.Position)
    camera.CFrame=camera.CFrame:Lerp(desired,1-math.exp(-math.clamp(dt or 1/60,0,0.1)*18))
end
function A.collectorStairSupport(part,x,y,z)
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
    params.FilterDescendantsInstances={part}
    local top=part.Position.Y+y/2
    local axis=x<z and Vector3.new(math.max(1,x/2+0.6),0,0)or Vector3.new(0,0,math.max(1,z/2+0.6))
    for _,sign in ipairs({-1,1})do
        local sample=Vector3.new(part.Position.X,top+1,part.Position.Z)+axis*sign
        local hit=workspace:Raycast(sample,Vector3.new(0,-3.5,0),params)
        if hit and hit.Normal.Y>=0.6 and math.abs(hit.Position.Y-top)<=1.3 then return true end
    end
    return false
end

function A.collectorRailingPart(part)
    if not part or not part:IsA("BasePart")or not part.CanCollide or part:IsA("TrussPart")then return false end
    local ancestor=part
    for _=1,3 do
        if not ancestor or ancestor==workspace then break end
        local name=ancestor.Name:lower()
        if name:find("railing",1,true)or name:find("handrail",1,true)or name:find("banister",1,true)
            or name=="rail"or name=="rails"then return true end
        ancestor=ancestor.Parent
    end
    local frame,size=part.CFrame,part.Size
    local x=math.abs(frame.RightVector.X)*size.X+math.abs(frame.UpVector.X)*size.Y+math.abs(frame.LookVector.X)*size.Z
    local y=math.abs(frame.RightVector.Y)*size.X+math.abs(frame.UpVector.Y)*size.Y+math.abs(frame.LookVector.Y)*size.Z
    local z=math.abs(frame.RightVector.Z)*size.X+math.abs(frame.UpVector.Z)*size.Y+math.abs(frame.LookVector.Z)*size.Z
    if math.min(x,z)>1.5 or math.max(x,z)<4 or y>2 then return false end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
    params.FilterDescendantsInstances={part}
    if A.collectorStairSupport(part,x,y,z)then return false end
    local origin=part.Position-Vector3.new(0,y/2+0.15,0)
    local ground=workspace:Raycast(origin,Vector3.new(0,-7,0),params)
    return ground~=nil and origin.Y-ground.Position.Y>1.25
end
function A.collectorMarkRailings()
    if A.collectorRailingScan then return end
    A.collectorRailingScan=true
    local function add(part)
        if A.collectorRailingPart(part)then
            local modifier=Instance.new("PathfindingModifier")
            modifier.Name="QosAvoidRailTop";modifier.Label="CollectorRailing";modifier.PassThrough=false
            modifier.Parent=part;A.resources[modifier]=true
        end
    end
    for _,part in ipairs(workspace:GetDescendants())do add(part)end
    A.connect(workspace.DescendantAdded,function(part)
        if part:IsA("BasePart")then A.delay(0.1,function()if part.Parent then add(part)end end)end
    end)
end

function A.collectorRouteSafe(origin,waypoints,startIndex)
    local previous=origin
    for i=startIndex or 1,#waypoints do
        local point=waypoints[i].Position
        if not A.collectorSegmentSafe(previous,point)then return false end
        if i>(startIndex or 1)then
            local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
            params.FilterDescendantsInstances=A.player.Character and {A.player.Character}or {}
            local support=workspace:Raycast(point+Vector3.new(0,1,0),Vector3.new(0,-4,0),params)
            if support and A.collectorRailingPart(support.Instance)then return false end
        end
        previous=point
    end
    return true
end

function A.collectorPlanOrigin(move)
    local origin=move.root.Position;local feet=A.collectorFeet(move).Y
    if move.humanoid.FloorMaterial==Enum.Material.Air then
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
        local ground=workspace:Raycast(origin,Vector3.new(0,-12,0),params)
        if not ground or ground.Normal.Y<0.6 then return nil end
        feet=ground.Position.Y;origin=Vector3.new(origin.X,feet+3,origin.Z)
    end
    return origin,feet
end
function A.collectorNavigationGoal(move,target)
    local position=target.Position
    if A.collectorCombatRole and not A.collectorCollectingCoins()then
        local humanoid=target.Parent and target.Parent:FindFirstChildOfClass("Humanoid")
        local state=humanoid and humanoid:GetState()
        if state==Enum.HumanoidStateType.Jumping or state==Enum.HumanoidStateType.Freefall then
            local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances={move.character,target.Parent};params.RespectCanCollide=true
            local support=workspace:Raycast(position,Vector3.new(0,-18,0),params)
            if support and support.Normal.Y>=0.65 then
                return Vector3.new(position.X,support.Position.Y+2.5,position.Z)
            end
        end
        return position
    end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local support=workspace:Raycast(position+Vector3.new(0,0.5,0),Vector3.new(0,-5,0),params)
    if support and support.Normal.Y>=0.6 then return Vector3.new(position.X,support.Position.Y,position.Z)end
    return position
end
function A.collectorFiringApproaches(move,target)
    if A.collectorCombatRole~="Sheriff"or A.collectorCollectingCoins()then return {}end
    local character=target.Parent
    local away=move.root.Position-target.Position;away=Vector3.new(away.X,0,away.Z)
    if away.Magnitude<0.1 then away=Vector3.xAxis else away=away.Unit end
    local side=Vector3.new(-away.Z,0,away.X)
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character,character};params.RespectCanCollide=true
    local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Exclude
    overlap.FilterDescendantsInstances=params.FilterDescendantsInstances;overlap.RespectCanCollide=true
    local goals={}
    for i=0,7 do
        local angle=i*math.pi/4
        local direction=away*math.cos(angle)+side*math.sin(angle)
        local probe=target.Position+direction*42+Vector3.new(0,8,0)
        local hit=workspace:Raycast(probe,Vector3.new(0,-32,0),params)
        if hit and hit.Normal.Y>=0.65 then
            local eye=hit.Position+Vector3.new(0,2.5,0)
            local distance=(eye-target.Position).Magnitude
            if distance>=38 and distance<=50 and A.collectorCombatVisible(eye,target.Position,character)
                and #workspace:GetPartBoundsInBox(CFrame.new(eye),Vector3.new(1.8,4.4,1.8),overlap)==0 then
                goals[#goals+1]=hit.Position
            end
        end
    end
    table.sort(goals,function(a,b)return(a-move.root.Position).Magnitude<(b-move.root.Position).Magnitude end)
    return goals
end
function A.collectorCombatRouteGoal(move,target)
    if move.combatApproachGoal and move.combatApproachTarget==target and move.combatApproachTargetPosition
        and(target.Position-move.combatApproachTargetPosition).Magnitude<8 then return move.combatApproachGoal end
    return A.collectorNavigationGoal(move,target)
end
function A.collectorShorterCombatRoute(move,target,origin,goal,path)
    if not path or A.collectorCombatRole~="Sheriff"or A.collectorCollectingCoins()then return path,nil end
    local function cost(points)
        local length,jumps=0,0
        for i,p in ipairs(points)do
            if i>1 then length=length+(p.Position-points[i-1].Position).Magnitude end
            if p.Action==Enum.PathWaypointAction.Jump then jumps=jumps+1 end
        end
        return length+jumps*4,length
    end
    local bestScore,length=cost(path:GetWaypoints())
    local direct=(goal-origin).Magnitude
    if length<=direct*1.35 or length<=direct+12 then return path,nil end
    local initialLength=length
    local goals={{position=goal}}
    for i,p in ipairs(A.collectorFiringApproaches(move,target))do
        if i>2 then break end
        goals[#goals+1]={position=p,approach=p}
    end
    local bestGoal
    for _,candidate in ipairs(goals)do
        if not A.alive or A.movement~=move or not A.config.farm or move.target~=target then break end
        local alternative
        local ok=pcall(function()
            alternative=game:GetService("PathfindingService"):CreatePath({AgentRadius=1.25,AgentHeight=5,
                AgentCanClimb=true,AgentCanJump=true,WaypointSpacing=2,Costs={CollectorRailing=math.huge}})
            A.resources[alternative]=true;alternative:ComputeAsync(origin,candidate.position)
            if alternative.Status~=Enum.PathStatus.Success then return end
            local points=alternative:GetWaypoints();local last=points[#points]
            local offset=last and last.Position-candidate.position
            if not offset or Vector3.new(offset.X,0,offset.Z).Magnitude>=3
                or offset.Y<(candidate.approach and -1.8 or -4)or offset.Y>1.8
                or not points[1]or math.abs(points[1].Position.Y-origin.Y)>3.5
                or not A.collectorRouteSafe(move.root.Position,points,1)then return end
            local score=cost(points)
            if score<bestScore-6 then
                A.resources[path]=nil;path:Destroy()
                path=alternative;alternative=nil;bestScore=score;bestGoal=candidate.approach
            end
        end)
        if alternative then A.resources[alternative]=nil;alternative:Destroy()end
        if not ok then break end
    end
    A.log("combat_route_comparison",{target=target,direct=direct,initialLength=initialLength,
        selectedScore=bestScore,approach=bestGoal})
    return path,bestGoal
end
function A.planWalk(move, target)
    if move.planning or os.clock() < (move.nextPlanAt or 0) then return end
    if (not A.collectorCombatRole or A.collectorCollectingCoins()) and math.abs(target.Position.Y-A.collectorFeet(move).Y)<2 and A.collectorWalkClear(move,target.Position)then
        A.clearWalkRoute(move,true)
        move.waypoints={{Position=target.Position,Action=Enum.PathWaypointAction.Walk,Label="Direct"}}
        move.pathIndex=1;move.routeTarget=target;move.navHeightOffset=0
        return
    end
    local planOrigin,planFeet=A.collectorPlanOrigin(move)
    if not planOrigin then return end
    A.collectorMarkRailings()
    move.planning = true
    move.nextPlanAt = os.clock() + 1.5
    local targetPosition=target.Position
    local goalPosition=A.collectorNavigationGoal(move,target)
    A.log("route_requested",{origin=move.root.Position,target=target,goal=goalPosition,combat=A.collectorCombatRole})
    A.spawn(function()
        local path, waypoints, approachGoal
        local ok, err = pcall(function()
            local prepared=A.collectorCoinChoice
            if prepared and prepared.target==target and prepared.path
                and(move.root.Position-prepared.origin).Magnitude<4
                and A.collectorRouteSafe(move.root.Position,prepared.waypoints,1)then
                path=prepared.path;waypoints=prepared.waypoints;prepared.path=nil
                return
            end
            local raised=goalPosition.Y>A.collectorFeet(move).Y+2
            local modes=raised and {{2,true},{1.25,true},{1,true},{2,false},{1.25,false},{1,false}}or {{2,false},{2,true},{1.25,false},{1.25,true},{1,false},{1,true}}
            for _,mode in ipairs(modes) do
                path=game:GetService("PathfindingService"):CreatePath({AgentRadius=mode[1],
                    AgentHeight=5,AgentCanClimb=true,AgentCanJump=mode[2],WaypointSpacing=2,Costs={CollectorDanger=A.collectorCombatRole and 1 or 50,CollectorRailing=math.huge}})
                A.resources[path]=true
                path:ComputeAsync(planOrigin,goalPosition)
                if path.Status==Enum.PathStatus.Success then
                    local points=path:GetWaypoints()
                    local endpoint=points[#points]
                    local collecting=not A.collectorCombatRole or A.collectorCollectingCoins()
                    -- Combat goals are character roots; navigation endpoints lie at feet.
                    -- A successful navmesh status can still project onto another floor.
                    local offset=endpoint and endpoint.Position-goalPosition
                    local reached=offset and Vector3.new(offset.X,0,offset.Z).Magnitude<3
                        and (collecting and offset.Magnitude<3 and math.abs(offset.Y)<1.8
                            or not collecting and offset.Y>=-4 and offset.Y<=1.8)
                    if reached then break end
                    if not collecting then
                        A.log("combat_route_endpoint_rejected",{target=target,goal=goalPosition,
                            endpoint=endpoint and endpoint.Position,radius=mode[1],jump=mode[2]})
                    end
                end
                A.resources[path]=nil;path:Destroy();path=nil
            end
            path,approachGoal=A.collectorShorterCombatRoute(move,target,planOrigin,goalPosition,path)
            if not path then
                for _,goal in ipairs(A.collectorFiringApproaches(move,target))do
                    path=game:GetService("PathfindingService"):CreatePath({AgentRadius=1,AgentHeight=5,
                        AgentCanClimb=true,AgentCanJump=true,WaypointSpacing=2,Costs={CollectorRailing=math.huge}})
                    A.resources[path]=true;path:ComputeAsync(planOrigin,goal)
                    if path.Status==Enum.PathStatus.Success then
                        local points=path:GetWaypoints();local last=points[#points]
                        if last and(last.Position-goal).Magnitude<3 and math.abs(last.Position.Y-goal.Y)<1.8 then
                            approachGoal=goal;break
                        end
                    end
                    A.resources[path]=nil;path:Destroy();path=nil
                end
            end
            if not path then error("No walking or necessary-jump route") end
            waypoints = path:GetWaypoints()
            if #waypoints == 0 then error("Empty route") end
            if math.abs(waypoints[1].Position.Y-planFeet)>3.5 then
                move.navStartMismatch=true;error("Navigation started below the current surface")
            end
            A.updateCollectorThreats()
            if not A.collectorRouteSafe(move.root.Position,waypoints,1)then error("Planned route intersects murderer danger; selecting another candy")end
        end)
        move.planning = false
        A.log("route_result",{ok=ok,error=err,target=target,waypoints=waypoints})
        if not A.alive or A.movement ~= move or not A.config.farm or move.target ~= target
            or not target.Parent or (target.Position-targetPosition).Magnitude>(A.collectorCombatRole and 20 or 3) then
            if path then pcall(function() path:Destroy() end) end
            return
        end
        if not ok then
            if path then pcall(function() path:Destroy() end) end
            local unsafe=tostring(err):find("murderer danger",1,true)~=nil
            if not unsafe and A.collectorTryOpening(move,target)then return end
            if not unsafe then
                A.collectorFailedOrigins=A.collectorFailedOrigins or setmetatable({},{__mode="k"})
                A.collectorFailedOrigins[target]=move.root.Position
            end
            A.skipCollectorTarget(move,target,unsafe and "Murderer blocks this route; choosing another candy" or "No route through this entrance; retrying other candies",A.collectorCombatRole and 3 or (unsafe and 5 or 45))
            return
        end
        A.clearWalkRoute(move,true)
        move.path, move.waypoints, move.pathIndex,move.routeTarget = path, waypoints, math.min(2,#waypoints),target
        move.combatApproachGoal=approachGoal;move.combatApproachTarget=approachGoal and target or nil
        move.combatApproachTargetPosition=approachGoal and targetPosition or nil
        if approachGoal then A.log("combat_firing_route",{goal=approachGoal,target=target,position=targetPosition})end
        -- The first point is the navmesh projection of our starting position.
        -- Calibrate its height rather than requiring an avatar foot estimate to match.
        move.navStartMismatch=nil
        move.navHeightOffset=math.clamp(waypoints[1].Position.Y-planFeet,-2,2)
        move.lastProgressAt=move.lastProgressAt or os.clock()
        move.lastProgressPosition=move.lastProgressPosition or move.root.Position
        move.routeStartedAt=move.routeStartedAt or os.clock()
        move.blockedConnection = A.connect(path.Blocked,function(index)
            if A.movement == move and move.path == path and index >= (move.pathIndex or 1) then
                move.replan = true; move.walkDirection = Vector3.zero
            end
        end)
        A.note("Collector", A.collectorCombatRole and "Chasing" or "Collecting")
    end)
end
function A.collectorFeet(move)
    local leg=move.character and move.character:FindFirstChild("Left Leg")
    local legHeight=move.humanoid.RigType==Enum.HumanoidRigType.R6 and leg and leg.Size.Y or 0
    return move.root.Position-Vector3.new(0,move.humanoid.HipHeight+move.root.Size.Y/2+legHeight,0)
end
function A.collectorCornerReady(move,waypoint,flat)
    if flat.Magnitude<=0.35 or waypoint.Action==Enum.PathWaypointAction.Jump then return true end
    local nextPoint=move.waypoints and move.waypoints[(move.pathIndex or 1)+1]
    if not nextPoint then return true end
    local delta=nextPoint.Position-move.root.Position
    local direction=Vector3.new(delta.X,0,delta.Z)
    return direction.Magnitude<0.1 or A.collectorBodyClear(move,direction.Unit,math.min(direction.Magnitude,2))
end

function A.collectorWaypointReached(move,waypoint)
    local position=move.root.Position
    local delta=waypoint.Position-position
    local heightError=math.abs(waypoint.Position.Y-(A.collectorFeet(move).Y+(move.navHeightOffset or 0)))
    if heightError>1.8 then return false end
    local flat=Vector3.new(delta.X,0,delta.Z)
    if flat.Magnitude<=1.2 then return A.collectorCornerReady(move,waypoint,flat)end
    if waypoint.Action==Enum.PathWaypointAction.Jump then return false end
    local previous=move.waypoints and move.waypoints[(move.pathIndex or 1)-1]
    if not previous then return false end
    local segment=waypoint.Position-previous.Position
    segment=Vector3.new(segment.X,0,segment.Z)
    if segment.Magnitude<0.1 then return false end
    local along=(-flat):Dot(segment.Unit)
    local cross=((-flat)-segment.Unit*along).Magnitude
    -- Accept a nearby passed waypoint without backtracking around a doorway.
    return along>=0 and along<=2.5 and cross<=1.2 and A.collectorCornerReady(move,waypoint,flat)
end

function A.collectorStairsAhead(move)
    local direction=move.walkDirection or Vector3.zero
    if direction.Magnitude<0.01 then return false end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
    params.FilterDescendantsInstances={move.character}
    local previous;local rising=false
    for _,distance in ipairs({0,0.9,1.8}) do
        local position=move.root.Position+direction.Unit*distance+Vector3.new(0,0.5,0)
        local ground=workspace:Raycast(position,Vector3.new(0,-8,0),params)
        if not ground or ground.Normal.Y<0.6 then return false end
        if previous then
            local rise=ground.Position.Y-previous
            if math.abs(rise)>1.25 then return false end
            if rise>0.1 then rising=true end
        end
        previous=ground.Position.Y
    end
    return rising
end
function A.requestWalkJump(move,index)
    if move.humanoid.FloorMaterial==Enum.Material.Air or os.clock()-(move.landedAt or -10)<0.25 then move.jumpPending=false;return true end
    if move.jumpPending then return true end
    if move.lastJumpPosition and os.clock()-(move.lastJumpAt or 0)<1.2
        and(move.root.Position-move.lastJumpPosition).Magnitude<3 then return true end
    local humanoid=move.humanoid
    local height=humanoid.UseJumpPower and humanoid.JumpPower^2/(2*math.max(workspace.Gravity,1)) or humanoid.JumpHeight
    if height<1 or not humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) then return false end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
    params.FilterDescendantsInstances={move.character}
    local direction=move.walkDirection or Vector3.zero
    local waypoint=move.waypoints and move.waypoints[index]
    local nextPoint=move.waypoints and move.waypoints[index+1]
    local landingY=waypoint and waypoint.Position.Y or A.collectorFeet(move).Y+1
    if nextPoint then landingY=math.max(landingY,nextPoint.Position.Y)end
    -- Path points use the calibrated navmesh height, as waypoint arrival does.
    -- Convert to physical foot height before comparing against jump reach.
    if waypoint then landingY=landingY-(move.navHeightOffset or 0)end
    local rise=landingY-A.collectorFeet(move).Y
    if rise>height+0.3 then
        A.log("jump_landing_too_high",{rise=rise,height=height,position=move.root.Position})
        return false
    end
    local needed=math.clamp(rise+0.5,1.5,height)
    if workspace:Raycast(move.root.Position+Vector3.new(0,move.root.Size.Y/2,0),Vector3.new(0,needed,0),params)then
        A.log("jump_ceiling_blocked",{rise=rise,clearance=needed,position=move.root.Position})
        return false
    end
    if direction.Magnitude>0.01 and workspace:Raycast(A.collectorFeet(move)+Vector3.new(0,height,0),direction.Unit*1.5,params)then return false end
    local landing=move.waypoints and(move.waypoints[index+1]or move.waypoints[index])
    if landing then local d=landing.Position-move.root.Position;local flat=Vector3.new(d.X,0,d.Z);if flat.Magnitude>0.1 then move.airDirection=flat.Unit end end
    move.jumpPending=true;move.jumpRequestedIndex=index
    return true
end

A.collectorThreats={}
A.collectorZones={}
function A.clearCollectorThreats()
    if A.collectorDangerFolder then A.collectorDangerFolder:Destroy() end
    A.collectorDangerFolder=nil;A.collectorEscape=nil;A.collectorThreats={};A.collectorZones={}
    A.collectorThreatScan=nil;A.collectorEscapeFailed=nil;A.collectorEscapeAttempt=0
    A.collectorMapBounds=nil;A.collectorOppositeSide=nil
end
function A.collectorThreatRelevant(point,threat)
    local position=threat.current or threat.position
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
    local ignore={}
    if A.player.Character then table.insert(ignore,A.player.Character)end
    if threat.player and threat.player.Character then table.insert(ignore,threat.player.Character)end
    params.FilterDescendantsInstances=ignore
    -- Solid walls and floors block immediate proximity danger. Open doorways
    -- and exposed points later along the route are checked separately.
    local origin=point+Vector3.new(0,1,0)
    local hit=workspace:Raycast(origin,position-origin,params)
    if not hit then return true end
    -- Doors may block bullets while remaining traversable or openable.
    -- Nearby danger must not disappear just because this ray hits a door.
    local delta=position-point
    if math.abs(delta.Y)<=6 and Vector3.new(delta.X,0,delta.Z).Magnitude<=40 then
        local object=hit.Instance
        while object and object~=workspace do
            if string.find(string.lower(object.Name),"door",1,true)then return true end
            object=object.Parent
        end
    end
    return false
end
function A.collectorThreatDistance(point)
    local distance=math.huge
    for _,threat in ipairs(A.collectorThreats)do
        if A.collectorThreatRelevant(point,threat)then
            distance=math.min(distance,(point-threat.position).Magnitude,(point-(threat.current or threat.position)).Magnitude)
        end
    end
    return distance
end

function A.collectorSegmentSafe(from,to)
    if A.isZombie(A.player)then return true end
    if A.collectorCombatRole and not A.collectorCollectingCoins() then return true end
    local delta=to-from
    for _,threat in ipairs(A.collectorThreats)do
        if A.collectorThreatRelevant(from,threat)or A.collectorThreatRelevant(to,threat)then
            local positions={threat.current or threat.position,threat.position}
            for _,sample in ipairs(threat.future or {})do positions[#positions+1]=sample.position end
            for _,position in ipairs(positions)do
                local start=(from-position).Magnitude
                local finish=(to-position).Magnitude
                local t=delta:Dot(delta)>0.001 and math.clamp((position-from):Dot(delta)/delta:Dot(delta),0,1)or 0
                local closest=(from+delta*t-position).Magnitude
                if start<40 then
                    if finish<start-0.1 or closest<start-0.25 then return false end
                elseif closest<30 then return false end
            end
        end
    end
    return true
end

function A.collectorPredictThreat(root,character)
    local velocity=root.AssemblyLinearVelocity
    if not A.finite(velocity)then velocity=Vector3.zero end
    velocity=Vector3.new(velocity.X,0,velocity.Z)
    if velocity.Magnitude>24 then velocity=velocity.Unit*24 end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
    local ignore={character};if A.player.Character then table.insert(ignore,A.player.Character)end
    params.FilterDescendantsInstances=ignore
    local delta=velocity*1.5
    local wall=delta.Magnitude>0.1 and workspace:Raycast(root.Position,delta,params)
    if wall then delta=delta.Unit*math.max(0,(wall.Position-root.Position).Magnitude-1) end
    local future={}
    for _,time in ipairs({0.5,1,1.5})do
        future[#future+1]={time=time,position=root.Position+delta*(time/1.5)}
    end
    return future
end
function A.collectorProjectedPenalty(from,to)
    local direction=to-from
    local length=direction.Magnitude
    if length<0.01 then return 0 end
    local penalty=0
    for _,threat in ipairs(A.collectorThreats)do
        if A.collectorThreatRelevant(from,threat)then
            for _,sample in ipairs(threat.future or {})do
                local ours=from+direction.Unit*math.min(length,16*sample.time)
                local separation=(ours-sample.position).Magnitude
                penalty=math.max(penalty,math.max(0,28-separation)*3)
            end
        end
    end
    return penalty
end

function A.updateCollectorThreats()
    if A.isZombie(A.player)then
        if #A.collectorThreats>0 or A.collectorDangerFolder then A.clearCollectorThreats()end
        return
    end
    local now=os.clock()
    if now-(A.collectorThreatScan or -10)<0.1 then return end
    A.collectorThreatScan=now
    local threats,seen={},{}
    for _,player in ipairs(A.playerList) do
        local data=A.roundData(player)
        local role=data and data.Role or player:GetAttribute("Role")or(player.Character and player.Character:GetAttribute("Role"))
        if player~=A.player and(A.isAimTarget(player)or role=="Murderer"or A.findTool(player,"Knife")or A.isZombie(player))then
            local _,_,root=A.body(player)
            if root then
                local velocity=root.AssemblyLinearVelocity
                if not A.finite(velocity) or velocity.Magnitude>100 then velocity=Vector3.zero end
                local future=A.collectorPredictThreat(root,player.Character)
                local position=future[1].position
                threats[#threats+1]={player=player,position=position,current=root.Position,future=future};seen[player]=true
                if not A.collectorDangerFolder then
                    A.collectorDangerFolder=A.new("Folder",{Name="qos-MM2-CollectorRoutes"},workspace)
                end
                local zone=A.collectorZones[player]
                if not zone then
                    zone=A.new("Part",{Name="AvoidMurderer",Size=Vector3.new(72,8,72),Anchored=true,
                        Transparency=1,CanCollide=false,CanTouch=false,CanQuery=false},A.collectorDangerFolder)
                    A.new("PathfindingModifier",{Label="CollectorDanger",PassThrough=true},zone)
                    A.collectorZones[player]=zone
                end
                local projected=future[#future].position
                local center=(root.Position+projected)/2
                local travel=projected-root.Position
                zone.Size=Vector3.new(48,8,48+travel.Magnitude)
                zone.CFrame=travel.Magnitude>0.1 and CFrame.lookAt(center,projected)or CFrame.new(center)
            end
        end
    end
    for player,zone in pairs(A.collectorZones) do if not seen[player] then zone:Destroy();A.collectorZones[player]=nil end end
    -- Create space at spawn before roles are replicated to the client.
    if #threats==0 and A.collectorRoundStarted and now-A.collectorRoundStarted<10 then
        local _,_,ownRoot=A.body(A.player)
        for _,player in ipairs(A.playerList) do
            if player~=A.player then
                local _,_,root=A.body(player)
                if ownRoot and root and (root.Position-ownRoot.Position).Magnitude<30 then
                    threats[#threats+1]={player=player,position=root.Position,provisional=true}
                end
            end
        end
    end
    A.collectorThreats=threats
end
function A.collectorMapSide(root)
    local bounds=A.collectorMapBounds
    if not bounds or bounds.container~=A.collectContainer then
        bounds={container=A.collectContainer,minX=math.huge,maxX=-math.huge,minZ=math.huge,maxZ=-math.huge}
        A.collectorMapBounds=bounds
    end
    for _,part in ipairs(A.coinCache) do
        if part.Parent and A.finite(part.Position) and part.Position.Y>workspace.FallenPartsDestroyHeight+12 then
            bounds.minX=math.min(bounds.minX,part.Position.X);bounds.maxX=math.max(bounds.maxX,part.Position.X)
            bounds.minZ=math.min(bounds.minZ,part.Position.Z);bounds.maxZ=math.max(bounds.maxZ,part.Position.Z)
        end
    end
    if bounds.minX==math.huge then return nil end
    local center=Vector3.new((bounds.minX+bounds.maxX)/2,root.Position.Y,(bounds.minZ+bounds.maxZ)/2)
    local nearest,distance=nil,math.huge
    for _,threat in ipairs(A.collectorThreats) do
        local d=(threat.position-root.Position).Magnitude
        if d<distance then nearest,distance=threat,d end
    end
    if not nearest then return nil end
    local away=Vector3.new(center.X-nearest.position.X,0,center.Z-nearest.position.Z)
    if away.Magnitude<3 then away=Vector3.new(root.Position.X-center.X,0,root.Position.Z-center.Z) end
    if away.Magnitude<0.1 then away=Vector3.new(1,0,0) end
    local span=math.max(bounds.maxX-bounds.minX,bounds.maxZ-bounds.minZ)
    return {center=center,away=away.Unit,margin=math.min(12,span*0.12)}
end
function A.collectorSideValue(point)
    local side=A.collectorOppositeSide
    if not side then return math.huge end
    return (point-side.center):Dot(side.away)
end
function A.collectorExitCount(move,position)
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local count=0
    for i=0,7 do
        local direction=Vector3.new(math.cos(i*math.pi/4),0,math.sin(i*math.pi/4))*7
        local destination=position+direction
        if not workspace:Raycast(position,direction,params)
            and A.collectorSegmentSafe(position,destination) then
            local ground=workspace:Raycast(destination,Vector3.new(0,-7,0),params)
            if ground and ground.Normal.Y>=0.6 then count=count+1 end
        end
    end
    return count
end

function A.collectorEscapeGoal(root)
    local marker=A.collectorEscape
    local side=A.collectorOppositeSide
    if marker and not A.collectorEscapeFailed and (root.Position-marker.Position).Magnitude>5
        and A.collectorSideValue(marker.Position)>=(side and side.margin or 0)
        and A.collectorThreatDistance(marker.Position)>=36 then return marker end
    local choices={}
    for _,part in ipairs(A.coinCache) do
        if part.Parent and (A.coinSkip[part] or 0)<=os.clock()
            and part.Position.Y>workspace.FallenPartsDestroyHeight+12
            and A.collectorSideValue(part.Position)>=(side and side.margin or 0) then
            local distance=A.collectorThreatDistance(part.Position)
            if distance>=36 then
                choices[#choices+1]={position=part.Position,score=distance+A.collectorSideValue(part.Position)*0.25}
            end
        end
    end
    table.sort(choices,function(a,b)return a.score>b.score end)
    if #choices==0 then return nil end
    if A.movement then
        for i=1,#choices do
            local exits=A.collectorExitCount(A.movement,choices[i].position+Vector3.new(0,3,0))
            choices[i].score=choices[i].score+(exits==0 and -60 or exits*4)
        end
        table.sort(choices,function(a,b)return a.score>b.score end)
    end
    local choice=choices[((A.collectorEscapeAttempt or 0)%#choices)+1]
    if not marker then
        if not A.collectorDangerFolder then A.collectorDangerFolder=A.new("Folder",{Name="qos-MM2-CollectorRoutes"},workspace) end
        marker=A.new("Part",{Name="OppositeMapGoal",Size=Vector3.one,Anchored=true,Transparency=1,
            CanCollide=false,CanTouch=false,CanQuery=false},A.collectorDangerFolder)
        A.collectorEscape=marker
    end
    if (marker.Position-choice.position).Magnitude>3 and A.movement and A.movement.target==marker then
        A.movement.routeTarget=nil;A.movement.nextPlanAt=0
    end
    marker.Position=choice.position;A.collectorEscapeFailed=false
    return marker
end
function A.collectorRetryMovedRoutes(root)
    for part,position in pairs(A.collectorFailedOrigins or {})do
        if not part.Parent or (root.Position-position).Magnitude>18 then
            A.coinSkip[part]=nil;A.collectorFailedOrigins[part]=nil
        end
    end
end
function A.collectorRouteSeconds(origin,waypoints)
    local seconds=0;local previous=origin
    local speed=math.clamp(A.config.farmWalkSpeed,4,16)
    for _,point in ipairs(waypoints)do
        local delta=point.Position-previous
        local rate=point.Label=="Climb"and math.min(speed,8)or speed
        seconds=seconds+delta.Magnitude/rate
        if point.Action==Enum.PathWaypointAction.Jump then seconds=seconds+0.35 end
        previous=point.Position
    end
    return seconds
end
function A.collectorCandyThreat(origin)
    if A.isZombie(A.player)then return nil end
    local chosen,distance=nil,60
    for _,threat in ipairs(A.collectorThreats or {})do
        local position=threat.current or threat.position
        local d=(origin-position).Magnitude
        if not threat.provisional and math.abs(origin.Y-position.Y)<=6 and d<distance
            and A.collectorThreatRelevant(origin,threat)then chosen,distance=threat,d end
    end
    return chosen,distance
end
function A.collectorCandyScore(origin,points,seconds)
    local threat=A.collectorCandyThreat(origin)
    if not threat or #points==0 then return seconds end
    local position=threat.current or threat.position
    local score=seconds;local previous=origin
    for _,waypoint in ipairs(points)do
        local point=waypoint.Position
        if math.abs(point.Y-position.Y)<=6 then
            local distance=(point-position).Magnitude
            score=score+(point-previous).Magnitude/16*math.max(0,1-distance/60)*3
        end
        previous=point
    end
    if math.abs(previous.Y-position.Y)<=6 then score=score+math.max(0,55-(previous-position).Magnitude)*0.6 end
    return score
end
function A.collectorCandyAlongRoute(move,origin,route)
    if not route or not A.collectorCandyThreat(origin)then return end
    local points=move.target==route.target and move.waypoints or route.waypoints
    if not points then return end
    local best,bestProgress;local previous=origin;local travelled=0
    local feet=A.collectorFeet(move).Y
    for i=move.target==route.target and(move.pathIndex or 1)or 1,#points do
        local goal=points[i].Position;local delta=goal-previous;local length=delta.Magnitude
        if length>0.1 then
            for _,part in ipairs(A.coinCache)do
                if part~=route.target and A.coinActive(part)and(A.coinSkip[part]or 0)<=os.clock()
                    and(part.Position-origin).Magnitude<=12 and math.abs(part.Position.Y-feet)<2 then
                    local t=math.clamp((part.Position-previous):Dot(delta)/(length*length),0,1)
                    local progress=travelled+t*length
                    if progress>0.5 and progress<=12 and(part.Position-(previous+delta*t)).Magnitude<=2.5
                        and(not bestProgress or progress<bestProgress)
                        and A.collectorSegmentSafe(origin,part.Position)and A.collectorWalkClear(move,part.Position)then
                        best,bestProgress=part,progress
                    end
                end
            end
        end
        travelled=travelled+length;previous=goal
        if travelled>12 then break end
    end
    return best
end
function A.collectorCoinRoute(move,part,origin,prefetch)
    local failed=A.coinRouteFailures and A.coinRouteFailures[part]
    if failed and os.clock()<failed.untilAt and(origin-failed.origin).Magnitude<5
        and math.abs(origin.Y-failed.origin.Y)<1.5 then return nil end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local support=workspace:Raycast(part.Position+Vector3.new(0,0.5,0),Vector3.new(0,-5,0),params)
    if not support or support.Normal.Y<0.6 then return nil end
    local goal=Vector3.new(part.Position.X,support.Position.Y,part.Position.Z)
    if not prefetch and math.abs(goal.Y-A.collectorFeet(move).Y)<1.5 and A.collectorWalkClear(move,goal)then
        local points={{Position=goal,Label="Direct",Action=Enum.PathWaypointAction.Walk}}
        local seconds=A.collectorRouteSeconds(origin,points)
        return {target=part,origin=origin,waypoints=points,seconds=seconds,score=A.collectorCandyScore(origin,points,seconds),at=os.clock()}
    end
    -- Compare the six supported agent modes concurrently rather than paying
    -- six sequential ComputeAsync waits for every unreachable pickup.
    local pending=0;local routes={};local started=os.clock()
    local completed=Instance.new("BindableEvent")
    for _,mode in ipairs({{2,false},{2,true},{1.25,false},{1.25,true},{1,false},{1,true}})do
        pending=pending+1
        task.spawn(function()
            local path
            local ok,err=pcall(function()
                path=game:GetService("PathfindingService"):CreatePath({AgentRadius=mode[1],AgentHeight=5,
                    AgentCanClimb=true,AgentCanJump=mode[2],WaypointSpacing=2,
                    Costs={CollectorDanger=50,CollectorRailing=math.huge}})
                A.resources[path]=true
                path:ComputeAsync(origin,goal)
                if not A.alive or A.movement~=move or not A.config.farm then return end
                if path.Status==Enum.PathStatus.Success then
                    local points=path:GetWaypoints();local last=points[#points]
                    local footOffset=move.root.Position.Y-A.collectorFeet(move).Y
                    local startMatches=points[1]and math.abs(points[1].Position.Y-(origin.Y-footOffset))<=3.5
                    if not startMatches and not prefetch then move.navStartMismatch=true end
                    if startMatches and last and (last.Position-goal).Magnitude<3 and math.abs(last.Position.Y-goal.Y)<1.8
                        and A.collectorRouteSafe(origin,points,1)then
                        routes[#routes+1]={target=part,origin=origin,path=path,waypoints=points,
                            seconds=A.collectorRouteSeconds(origin,points),score=A.collectorCandyScore(origin,points,A.collectorRouteSeconds(origin,points)),at=os.clock()}
                        path=nil
                    end
                end
            end)
            if path then A.resources[path]=nil;path:Destroy()end
            if not ok then A.log("coin_route_mode_error",{error=err})end
            pending=pending-1
            if pending==0 then completed:Fire()end
        end)
    end
    if pending>0 then completed.Event:Wait()end
    completed:Destroy()
    local best
    for _,route in ipairs(routes)do
        if not best or route.score<best.score then
            if best then A.resources[best.path]=nil;best.path:Destroy()end
            best=route
        else A.resources[route.path]=nil;route.path:Destroy()end
    end
    A.log("coin_route_batch",{duration=os.clock()-started,accepted=best~=nil,prefetch=prefetch})
    if best then return best end
    A.coinRouteFailures=A.coinRouteFailures or setmetatable({},{__mode="k"})
    A.coinRouteFailures[part]={origin=origin,untilAt=os.clock()+4}
    return nil
end
function A.collectorPrefetchNext(move,arrival)
    if not A.collectorCollectingCoins()or A.collectorPrefetching or A.collectorCandyThreat(move.root.Position)then return end
    A.collectorPrefetching=true
    A.spawn(function()
        local best
        local ok,err=pcall(function()
            local origin=arrival.waypoints[#arrival.waypoints].Position+Vector3.new(0,move.root.Position.Y-A.collectorFeet(move).Y,0)
            local candidates={}
            for _,part in ipairs(A.coinCache)do
                if part~=arrival.target and A.coinActive(part)and(A.coinSkip[part]or 0)<=os.clock()then
                    candidates[#candidates+1]={part=part,bound=(part.Position-origin).Magnitude/16}
                end
            end
            table.sort(candidates,function(a,b)return a.bound<b.bound end)
            for _,candidate in ipairs(candidates)do
                if not A.alive or A.movement~=move or not A.config.farm or not A.collectorCollectingCoins()then break end
                if best and candidate.bound>=best.score then break end
                -- Direct walking tests use the live avatar; prefetch uses navmesh paths.
                local route=A.collectorCoinRoute(move,candidate.part,origin,true)
                if route and(not best or route.score<best.score)then
                    if best and best.path then A.resources[best.path]=nil;best.path:Destroy()end
                    best=route
                elseif route and route.path then A.resources[route.path]=nil;route.path:Destroy()end
            end
        end)
        if not A.alive then if best and best.path then best.path:Destroy()end;return end
        A.collectorPrefetching=false
        if not ok then A.log("coin_prefetch_error",{error=err})end
        if best and A.movement==move and A.config.farm and A.collectorCollectingCoins()then
            local old=A.collectorNextCoinChoice
            if old and old.path then A.resources[old.path]=nil;old.path:Destroy()end
            best.targetPosition=best.target.Position;A.collectorNextCoinChoice=best
        elseif best and best.path then A.resources[best.path]=nil;best.path:Destroy()end
    end)
end
function A.collectorChooseRoute(root)
    local move=A.movement
    if not move or move.owner~="farm"then
        if not A.acquireMove("farm")then return nil end
        move=A.movement
        move.walking=true;move.walkSpeed=move.humanoid.WalkSpeed
        move.walkDirection=Vector3.zero;move.humanoid.AutoRotate=true
    end
    local now=os.clock();local origin=root.Position
    local fleeing=A.collectorCandyThreat(origin)~=nil
    local cached=A.collectorCoinChoice
    local nextChoice=A.collectorNextCoinChoice
    if (not cached or not A.coinActive(cached.target)or(A.coinSkip[cached.target]or 0)>now)
        and nextChoice and A.coinActive(nextChoice.target)and(A.coinSkip[nextChoice.target]or 0)<=now
        and(origin-nextChoice.origin).Magnitude<10 then
        if cached and cached.path then A.resources[cached.path]=nil;cached.path:Destroy()end
        cached=nextChoice;A.collectorCoinChoice=cached;A.collectorNextCoinChoice=nil
    end
    local valid=cached and A.coinActive(cached.target)and(A.coinSkip[cached.target]or 0)<=now
    if valid and (math.abs(origin.Y-cached.origin.Y)>1.8 or(origin-cached.origin).Magnitude>8)then valid=false end
    if valid and (cached.target.Position-(cached.targetPosition or cached.target.Position)).Magnitude>2 then valid=false end
    -- Proven clear nearby pickups can win immediately while longer routes compute.
    local direct,bestDirect=nil,math.huge
    local directScore=math.huge
    for _,part in ipairs(A.coinCache)do
        if A.coinActive(part)and(A.coinSkip[part]or 0)<=now then
            local d=(part.Position-origin).Magnitude
            if d<10 and math.abs(part.Position.Y-A.collectorFeet(move).Y)<2
                and A.collectorWalkClear(move,part.Position)then
                local score=A.collectorCandyScore(origin,{{Position=part.Position}},d/math.clamp(A.config.farmWalkSpeed,4,16))
                if score<directScore then direct,bestDirect,directScore=part,d,score end
            end
        end
    end
    if not A.collectorChoosing and (not valid or now-(cached.at or 0)>(fleeing and 0.25 or 1.5)
        or(origin-cached.origin).Magnitude>8)and now>=(A.nextCoinChoice or 0)then
        A.collectorChoosing=true;A.nextCoinChoice=now
        local candidates={}
        for _,part in ipairs(A.coinCache)do
            if A.coinActive(part)and(A.coinSkip[part]or 0)<=now then
                table.insert(candidates,{part=part,bound=(part.Position-origin).Magnitude/16})
            end
        end
        table.sort(candidates,function(a,b)return a.bound<b.bound end)
        A.spawn(function()
            local winner;local examined=0
            local ok,err=pcall(function()
                for _,candidate in ipairs(candidates)do
                    if not A.alive or not A.config.farm or A.movement~=move or not A.collectorCollectingCoins()then break end
                    if winner and candidate.bound>=winner.score then break end
                    if (root.Position-origin).Magnitude>8 or math.abs(root.Position.Y-origin.Y)>1.8 then break end
                    if not A.coinActive(candidate.part)then continue end
                    local route=A.collectorCoinRoute(move,candidate.part,origin);examined=examined+1
                    if route and(not winner or route.score<winner.score)then
                        if winner and winner.path then A.resources[winner.path]=nil;winner.path:Destroy()end
                        if A.collectorCoinChoice==winner then A.collectorCoinChoice=nil end
                        winner=route
                    elseif route and route.path then A.resources[route.path]=nil;route.path:Destroy()end
                    -- Start a proven route while the remaining candidates compute.
                    local active=A.collectorCoinChoice
                    if winner and A.movement==move and A.config.farm and A.collectorCollectingCoins()
                        and A.coinActive(winner.target)and(root.Position-origin).Magnitude<4
                        and math.abs(root.Position.Y-origin.Y)<=1.8
                        and(not active or not A.coinActive(active.target)
                            or(A.coinSkip[active.target]or 0)>os.clock())then
                        if active and active.path then A.resources[active.path]=nil;active.path:Destroy()end
                        winner.targetPosition=winner.target.Position;A.collectorCoinChoice=winner
                        A.log("coin_route_provisional",{target=winner.target,seconds=winner.seconds,candidates=examined,origin=origin})
                    end
                end
            end)
            if not A.alive then if winner and winner.path then winner.path:Destroy()end;return end
            A.collectorChoosing=false
            if not winner then A.nextCoinChoice=os.clock()+0.5 end
            if not ok then A.log("coin_route_choice_error",{error=err})end
            if winner and A.movement==move and A.config.farm and A.collectorCollectingCoins()and A.coinActive(winner.target)
                and(root.Position-origin).Magnitude<8 and math.abs(root.Position.Y-origin.Y)<=1.8 then
                local old=A.collectorCoinChoice
                if old and old~=winner and old.path then A.resources[old.path]=nil;old.path:Destroy()end
                winner.targetPosition=winner.target.Position;A.collectorCoinChoice=winner
                A.log("coin_route_choice",{target=winner.target,seconds=winner.seconds,candidates=examined,origin=origin})
                -- Prepare the following pickup from the expected arrival point.
                A.collectorPrefetchNext(move,winner)
            else
                if A.collectorCoinChoice==winner then A.collectorCoinChoice=nil end
                if winner and winner.path then A.resources[winner.path]=nil;winner.path:Destroy()end
            end
        end)
    end
    if valid then
        cached.score=A.collectorCandyScore(origin,cached.waypoints,cached.seconds)
        local along=A.collectorCandyAlongRoute(move,origin,cached)
        if along then return along,(along.Position-origin).Magnitude end
    end
    if direct then
        local remaining=valid and cached.score or math.huge
        if valid and move.target==cached.target and move.waypoints then
            local suffix={}
            for i=move.pathIndex or 1,#move.waypoints do suffix[#suffix+1]=move.waypoints[i]end
            remaining=A.collectorCandyScore(origin,suffix,A.collectorRouteSeconds(origin,suffix))
        end
        -- Small hysteresis avoids swapping between two adjacent pickups each frame.
        if not valid or cached.target==direct or directScore+0.06<remaining then return direct,bestDirect end
    end
    if valid and move.target~=cached.target and A.coinActive(move.target)
        and(A.coinSkip[move.target]or 0)<=now and move.waypoints and not move.replan then
        local suffix={};for i=move.pathIndex or 1,#move.waypoints do suffix[#suffix+1]=move.waypoints[i]end
        local remaining=A.collectorCandyScore(origin,suffix,A.collectorRouteSeconds(origin,suffix))
        if cached.score+0.5>=remaining then return move.target,(move.target.Position-origin).Magnitude end
    end
    if valid then return cached.target,(cached.target.Position-origin).Magnitude end
    local current=move.target
    if A.coinActive(current)and(A.coinSkip[current]or 0)<=now and(move.waypoints or move.planning)then
        return current,(current.Position-origin).Magnitude
    end
    return direct,bestDirect
end

function A.collectorSurfaceRecovery(move)
    if not move.navStartMismatch or move.humanoid.FloorMaterial==Enum.Material.Air then return false end
    local origin=move.root.Position;local feet=A.collectorFeet(move)
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local best,score=nil,-math.huge
    for _,length in ipairs({2.5,4.5,6.5})do
        for i=0,11 do
            local direction=Vector3.new(math.cos(i*math.pi/6),0,math.sin(i*math.pi/6))
            local goal=origin+direction*length
            if A.collectorBodyClear(move,direction,length)and A.collectorSegmentSafe(origin,goal)then
                local hit=workspace:Raycast(goal,Vector3.new(0,-14,0),params)
                local drop=hit and feet.Y-hit.Position.Y or math.huge
                if hit and hit.Normal.Y>0.65 and drop>1.5 and drop<=10 then
                    local value=-drop-length*0.2
                    if value>score then best,score=goal,value end
                end
            end
        end
        if best then break end
    end
    if not best then return false end
    A.clearWalkRoute(move,true);move.navStartMismatch=nil
    move.recoveryGoal=best;move.recoveryUntil=os.clock()+(best-origin).Magnitude/16+0.25
    local direction=best-origin;move.walkDirection=Vector3.new(direction.X,0,direction.Z).Unit
    move.airDirection=move.walkDirection;move.humanoid:Move(move.walkDirection,false)
    A.log("surface_exit",{origin=origin,goal=best})
    return true
end

function A.collectorCollectingCoins()
    return A.collectorFullLife~=A.player.Character
end
function A.collectorGoal(root,current)
    if A.collectorGunTarget and A.collectorGunTarget.Parent then
        local part=A.collectorGunTarget
        if (A.coinSkip[part]or 0)<=os.clock()then return part,(part.Position-root.Position).Magnitude end
        return nil
    end
    if A.collectorFullLife==A.player.Character and (not A.collectorCombatRole or A.collectorCollectingCoins()) then return nil end
    if A.collectorCombatRole and not A.collectorCollectingCoins() then
        local player=A.collectorCombatTarget
        local enemy
        if player then local _,_,part=A.body(player);enemy=part end
        if enemy then return enemy,(enemy.Position-root.Position).Magnitude end
        return nil
    end
    A.updateCollectorThreats()
    A.collectorRetryMovedRoutes(root)
    return A.collectorChooseRoute(root)
end

function A.closestCollectible(root,current)
    local closest,distance=nil,math.huge
    if A.coinActive(current) and (A.coinSkip[current] or 0)<=os.clock() and current.Position.Y>workspace.FallenPartsDestroyHeight+12 then
        closest,distance=current,(current.Position-root.Position).Magnitude
    end
    for _,part in ipairs(A.coinCache) do
        if A.coinActive(part) and (A.coinSkip[part] or 0)<=os.clock() and part.Position.Y>workspace.FallenPartsDestroyHeight+12 then
            local d=(part.Position-root.Position).Magnitude
            if d<distance then closest,distance=part,d end
        end
    end
    return closest,distance
end
function A.smoothWalkDirection(previous,desired,dt)
    if desired.Magnitude<0.01 then return Vector3.zero end
    local alpha=1-math.exp(-math.clamp(dt or 1/60,0,0.1)/0.035)
    local direction=(previous or Vector3.zero):Lerp(desired,alpha)
    return direction.Magnitude>0.001 and direction.Unit or desired.Unit
end

function A.collectorRecoveryGoal(move)
    local forward=move.walkDirection or Vector3.zero
    if forward.Magnitude<0.01 then forward=move.root.CFrame.LookVector end
    forward=Vector3.new(forward.X,0,forward.Z).Unit
    local side=Vector3.new(-forward.Z,0,forward.X)
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local best,bestDrop=nil,-math.huge
    for _,direction in ipairs({-forward,side,-side,(-forward+side).Unit,(-forward-side).Unit,forward}) do
        local goal=move.root.Position+direction*6
        local blocked=false
        for _,offset in ipairs({Vector3.zero,side*0.8,-side*0.8,Vector3.new(0,-1,0)}) do
            if workspace:Raycast(move.root.Position+offset,direction*6,params) then blocked=true;break end
        end
        local depth=math.clamp(goal.Y-workspace.FallenPartsDestroyHeight-3,7,15000)
        local ground=workspace:Raycast(goal,Vector3.new(0,-depth,0),params)
        if not blocked and ground and ground.Normal.Y>=0.6
            and ground.Position.Y>workspace.FallenPartsDestroyHeight+3 and A.collectorRecoveryClear(move,goal)
            and A.collectorSegmentSafe(move.root.Position,goal) then
            local drop=A.collectorFeet(move).Y-ground.Position.Y
            if drop>bestDrop then best,bestDrop=goal,drop end
        end
    end
    return best
end
function A.collectorMotionStalled(move,position,now)
    if not move.motionWindowPosition then
        move.motionWindowPosition=position;move.motionWindowAt=now;return false
    end
    if now-move.motionWindowAt<1.2 then return false end
    local delta=position-move.motionWindowPosition
    move.motionWindowPosition=position;move.motionWindowAt=now
    return Vector3.new(delta.X,0,delta.Z).Magnitude<1.25 and math.abs(delta.Y)<2
end

function A.collectorCoast(move)
    local direction=move.walkDirection or Vector3.zero
    if direction.Magnitude<0.01 then direction=move.smoothDirection or Vector3.zero end
    if direction.Magnitude<0.01 then return false end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local step=direction.Unit*2
    if workspace:Raycast(move.root.Position,step,params) then return false end
    local ground=workspace:Raycast(move.root.Position+step,Vector3.new(0,-5,0),params)
    if not ground or ground.Normal.Y<0.6 or not A.collectorSegmentSafe(move.root.Position,move.root.Position+step) then return false end
    A.clearWalkRoute(move,true)
    move.walkDirection=direction.Unit;move.coastUntil=os.clock()+0.8
    return true
end

function A.collectorRaisedPickupStep(move)
    local target=move.target
    if(A.collectorCombatRole and not A.collectorCollectingCoins())or not A.coinActive(target)then return false end
    local now=os.clock();local delta=target.Position-A.collectorFeet(move)
    local flat=Vector3.new(delta.X,0,delta.Z)
    local h=move.humanoid
    local height=h.UseJumpPower and h.JumpPower^2/(2*math.max(workspace.Gravity,1))or h.JumpHeight
    if delta.Y<2 or delta.Y>height-0.2 or flat.Magnitude>4.5 then return false end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local support=workspace:Raycast(target.Position+Vector3.new(0,2,0),Vector3.new(0,-4,0),params)
    if not support or support.Normal.Y<0.65 or support.Position.Y<A.collectorFeet(move).Y+1 then return false end
    if not A.collectorSegmentSafe(move.root.Position,target.Position)then return false end
    if workspace:Raycast(move.root.Position+Vector3.new(0,move.root.Size.Y/2,0),Vector3.new(0,height,0),params)then return false end
    if h.FloorMaterial~=Enum.Material.Air then
        if now<(move.nextRaisedJump or 0)then return false end
        if not h:GetStateEnabled(Enum.HumanoidStateType.Jumping)then return false end
        move.raisedAttempts=move.raisedAttempts or setmetatable({},{__mode="k"})
        if now<(move.raisedAttempts[target]or 0)then return false end
        move.raisedAttempts[target]=now+3
        move.nextRaisedJump=now+2;move.raisedUntil=now+1
        local direction=flat.Magnitude>0.1 and flat.Unit or Vector3.zero
        move.obstacleJump={direction=direction,goal=target.Position,untilAt=now+1.2}
        move.airDirection=direction;move.walkDirection=direction;move.recoveryGoal=nil
        h.Jump=true;h:ChangeState(Enum.HumanoidStateType.Jumping)
        A.log("raised_coin_jump",{target=target,height=delta.Y,position=move.root.Position})
    elseif now>(move.raisedUntil or 0)then return false end
    move.walkDirection=flat.Magnitude>0.1 and flat.Unit or Vector3.zero
    h:Move(move.walkDirection,false)
    move.lastProgressAt=now;move.lastProgressPosition=move.root.Position
    A.collectorWatch={position=move.root.Position,at=now}
    return true
end

function A.collectorLadderShape(object)
    if object:IsA("TrussPart")then return nil end
    local named=object.Name:lower():find("ladder",1,true)~=nil
    local parts={}
    if object:IsA("Model")then
        for _,v in ipairs(object:GetDescendants())do
            if v:IsA("TrussPart")then return nil end
            if v:IsA("BasePart")and v.CanCollide then parts[#parts+1]=v end
        end
    elseif object:IsA("BasePart")and object.CanCollide and named then parts={object}
    else return nil end
    if #parts==0 or #parts>40 then return nil end
    local cf,size
    if object:IsA("Model")then cf,size=object:GetBoundingBox()else cf,size=object.CFrame,object.Size end
    if math.abs(cf.UpVector.Y)<0.95 or size.Y<6 or size.Y>80 then return nil end
    local width=math.max(size.X,size.Z);local depth=math.min(size.X,size.Z)
    if width<1 or width>6 or depth>3 then return nil end
    if named then return cf,size,"named"end
    local rails,rungs=0,{}
    for _,part in ipairs(parts)do
        local localCF=cf:ToObjectSpace(part.CFrame)
        if math.abs(localCF.UpVector.Y)>0.95 then
            if part.Size.Y>=size.Y*0.7 and math.min(part.Size.X,part.Size.Z)<=0.6 then rails=rails+1 end
            if part.Size.Y<=0.45 and math.max(part.Size.X,part.Size.Z)>=width*0.5
                and math.min(part.Size.X,part.Size.Z)<=0.8 then rungs[#rungs+1]=localCF.Position.Y end
        end
    end
    if rails<2 or #rungs<4 then return nil end
    table.sort(rungs)
    for i=2,#rungs do local gap=rungs[i]-rungs[i-1];if gap<0.35 or gap>2.1 then return nil end end
    if rungs[#rungs]-rungs[1]<4 then return nil end
    return cf,size,"rung geometry"
end
function A.collectorEnsureLadders()
    local now=os.clock();if now<(A.nextAutoLadderScan or 0)then return end
    A.nextAutoLadderScan=now+2
    local map=A.collectContainer;while map and map.Parent~=workspace do map=map.Parent end
    if not map then return end
    if A.autoLadderMap~=map then
        if A.autoLadderFolder then A.resources[A.autoLadderFolder]=nil;A.autoLadderFolder:Destroy()end
        A.autoLadderMap=map;A.autoLadderSources=setmetatable({},{__mode="k"})
        A.autoLadderFolder=Instance.new("Folder");A.autoLadderFolder.Name="QOS_AutoLadders"
        A.autoLadderFolder.Parent=workspace;A.resources[A.autoLadderFolder]=true
    end
    for source,truss in pairs(A.autoLadderSources)do
        if not source:IsDescendantOf(map)then truss:Destroy();A.autoLadderSources[source]=nil end
    end
    for _,object in ipairs(map:GetDescendants())do
        if (object:IsA("Model")or(object:IsA("BasePart")and object.Name:lower():find("ladder",1,true)))
            and not A.autoLadderSources[object]then
            local nested=false;local parent=object.Parent
            while parent and parent~=map do if A.autoLadderSources[parent]then nested=true;break end;parent=parent.Parent end
            if not nested then
                local cf,size,kind=A.collectorLadderShape(object)
                if cf then
                    local truss=Instance.new("TrussPart");truss.Name="DetectedLadder"
                    truss.Size=Vector3.new(2,size.Y,2);truss.CFrame=cf
                    truss.Anchored=true;truss.Transparency=1;truss.CanCollide=true
                    truss.Parent=A.autoLadderFolder;A.autoLadderSources[object]=truss
                    A.nextTrussScan=0;A.nextEscapeLadderScan=0
                    A.log("ladder_detected",{source=object,kind=kind,position=cf.Position,size=size})
                end
            end
        end
    end
end

function A.collectorTrussSize(part)
    local c=part.CFrame;local s=part.Size
    local r,u,l=c.RightVector,c.UpVector,c.LookVector
    return Vector3.new(math.abs(r.X)*s.X+math.abs(u.X)*s.Y+math.abs(l.X)*s.Z,
        math.abs(r.Y)*s.X+math.abs(u.Y)*s.Y+math.abs(l.Y)*s.Z,
        math.abs(r.Z)*s.X+math.abs(u.Z)*s.Y+math.abs(l.Z)*s.Z)
end
function A.collectorNearbyTruss(move,waypoint)
    local now=os.clock()
    if now>=(A.nextTrussScan or 0)then
        A.nextTrussScan=now+1;A.collectorTrusses={}
        for _,part in ipairs(workspace:GetDescendants())do
            if part:IsA("TrussPart")then table.insert(A.collectorTrusses,part)end
        end
    end
    local best,score=nil,math.huge
    for _,part in ipairs(A.collectorTrusses or {})do
        if part.Parent then
            local localPoint=move.root.Position-part.Position
            local size=A.collectorTrussSize(part)
            local dx=math.max(0,math.abs(localPoint.X)-size.X/2)
            local dz=math.max(0,math.abs(localPoint.Z)-size.Z/2)
            local distance=Vector3.new(dx,0,dz).Magnitude
            local withinHeight=math.abs(localPoint.Y)<=size.Y/2+3
            local rising=waypoint and waypoint.Position.Y>A.collectorFeet(move).Y+2
            if distance<4 and withinHeight and (rising or move.humanoid:GetState()==Enum.HumanoidStateType.Climbing)and distance<score then
                best,score=part,distance
            end
        end
    end
    return best
end
function A.collectorClimbExitGoal(move,truss)
    local top=truss.Position.Y+A.collectorTrussSize(truss).Y/2
    local height=move.root.Position.Y-A.collectorFeet(move).Y
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Exclude
    overlap.FilterDescendantsInstances={move.character};overlap.RespectCanCollide=true
    local best,score
    for _,radius in ipairs({3,4.5,6})do
        for i=0,15 do
            local angle=i*math.pi/8
            local probe=Vector3.new(truss.Position.X+math.cos(angle)*radius,top+5,truss.Position.Z+math.sin(angle)*radius)
            local hit=workspace:Raycast(probe,Vector3.new(0,-7,0),params)
            if hit and hit.Normal.Y>=0.7 and not hit.Instance:IsA("TrussPart")and math.abs(hit.Position.Y-top)<=1.5 then
                local goal=hit.Position+Vector3.new(0,height,0)
                local occupied=workspace:GetPartBoundsInBox(CFrame.new(goal),Vector3.new(1.8,4.4,1.8),overlap)
                if #occupied==0 then
                    local value=(goal-move.root.Position).Magnitude
                    if not score or value<score then best,score=goal,value end
                end
            end
        end
    end
    return best
end
function A.collectorOrphanClimbStep(root)
    local move=A.movement
    if move and(move.owner~="farm"or(not move.orphanClimbExit and move.waypoints and move.waypoints[move.pathIndex or 1]))then return false end
    local character,humanoid=A.body(A.player)
    if not humanoid or humanoid.Health<=0 then return false end
    local exit=move and move.orphanClimbExit
    if not exit and humanoid:GetState()~=Enum.HumanoidStateType.Climbing then return false end
    if not move then
        if not A.acquireMove("farm")then return false end
        move=A.movement;move.walking=true;move.walkSpeed=humanoid.WalkSpeed
        move.walkDirection=Vector3.zero
    end
    local now=os.clock()
    if not exit then
        local truss=A.collectorNearbyTruss(move,nil)
        local goal=truss and A.collectorClimbExitGoal(move,truss)
        if not goal then return false end
        exit={goal=goal,truss=truss,started=now,progressAt=now,position=root.Position}
        move.orphanClimbExit=exit
        A.log("orphan_ladder_recovery",{position=root.Position,goal=goal,ladder=truss})
    end
    if not exit.truss.Parent or now-exit.started>5 then
        move.orphanClimbExit=nil;move.replan=true;move.nextPlanAt=0
        humanoid.Jump=false
        if exit.truss.Parent and move.target then A.skipCollectorTarget(move,move.target,"Ladder exit failed; trying a different route",8)end
        A.log("ladder_exit_failed",{position=root.Position,goal=exit.goal})
        return false
    end
    if not exit.progressAt or not exit.position or root.Position.Y>exit.position.Y+0.2 then
        exit.progressAt=now;exit.position=root.Position
    end
    local feet=A.collectorFeet(move).Y
    local goalFeet=exit.goal.Y-(root.Position.Y-feet)
    local delta=exit.goal-root.Position
    local flat=Vector3.new(delta.X,0,delta.Z)
    if humanoid:GetState()~=Enum.HumanoidStateType.Climbing and humanoid.FloorMaterial~=Enum.Material.Air
        and feet>=goalFeet-0.5 and flat.Magnitude<1.5 then
        move.orphanClimbExit=nil;A.clearWalkRoute(move,true);move.replan=true;move.nextPlanAt=0
        humanoid.Jump=false
        A.log("orphan_ladder_recovered",{position=root.Position,seconds=now-exit.started})
        return false
    end
    move.recoveryGoal=nil;move.coastUntil=nil;move.jumpPending=false;move.obstacleJump=nil
    local direction
    humanoid.Jump=false
    if feet<goalFeet-0.35 then
        -- Continue upward instead of kicking away before the feet clear the lip.
        local toward=exit.truss.Position-root.Position;toward=Vector3.new(toward.X,0,toward.Z)
        direction=(toward.Magnitude>0.1 and toward.Unit or Vector3.zero)+Vector3.new(0,1,0)
        if not exit.hopAt and now-exit.progressAt>=0.65 and root.Position.Y>=goalFeet-0.75
            and A.collectorJumpClearance(move,goalFeet-feet+0.75)then
            exit.hopAt=now;humanoid.Jump=true;humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            A.log("ladder_lip_hop",{position=root.Position,goal=exit.goal})
        end
    else
        exit.dismountAt=exit.dismountAt or now
        direction=flat.Magnitude>0.1 and flat.Unit or Vector3.zero
        move.airDirection=direction
    end
    move.walkDirection=Vector3.new(direction.X,0,direction.Z)
    humanoid:Move(direction,false)
    move.lastProgressAt=now;move.lastProgressPosition=root.Position
    A.collectorWatch={position=root.Position,at=now}
    return true
end
function A.collectorBeginLadderExit(move,truss)
    if not truss or move.root.Position.Y<truss.Position.Y+A.collectorTrussSize(truss).Y/2-0.75 then return false end
    local goal=A.collectorClimbExitGoal(move,truss)
    if not goal then return false end
    move.orphanClimbExit={goal=goal,truss=truss,started=os.clock(),position=move.root.Position}
    A.log("ladder_dismount_started",{position=move.root.Position,goal=goal,ladder=truss})
    return A.collectorOrphanClimbStep(move.root)
end
function A.collectorClimbStep(move)
    local waypoint=move.waypoints and move.waypoints[move.pathIndex or 1]
    if not waypoint then return false end
    local climbing=move.humanoid:GetState()==Enum.HumanoidStateType.Climbing
    local truss=A.collectorNearbyTruss(move,waypoint)
    if not climbing and waypoint.Label~="Climb" and not truss then
        move.climbProgressPosition=nil;move.climbGoal=nil;return false
    end
    local descending=waypoint.Position.Y<A.collectorFeet(move).Y-2
    if climbing and truss and not descending and A.collectorBeginLadderExit(move,truss)then return true end
    local now=os.clock()
    if not move.climbProgressPosition or (move.root.Position-move.climbProgressPosition).Magnitude>0.5 then
        move.climbProgressPosition=move.root.Position;move.climbProgressAt=now
    elseif now-(move.climbProgressAt or now)>4 then
        move.climbProgressPosition=nil;move.climbGoal=nil
        A.skipCollectorTarget(move,move.target,"Ladder route blocked; trying another candy",15)
        move.humanoid:Move(Vector3.zero,false)
        return true
    end
    while waypoint do
        local delta=waypoint.Position-A.collectorFeet(move)
        if Vector3.new(delta.X,0,delta.Z).Magnitude>1.5 or math.abs(delta.Y)>2 then break end
        move.pathIndex=move.pathIndex+1;waypoint=move.waypoints[move.pathIndex]
    end
    if not waypoint then move.replan=true;return true end
    move.recoveryGoal=nil;move.jumpPending=false;move.coastUntil=nil
    if truss then
        local top=truss.Position.Y+A.collectorTrussSize(truss).Y/2
        local rising=waypoint.Position.Y>A.collectorFeet(move).Y+1
        if climbing and descending then
            local toward=truss.Position-move.root.Position;toward=Vector3.new(toward.X,0,toward.Z)
            move.humanoid.Jump=false
            move.humanoid:Move((toward.Magnitude>0.1 and toward.Unit or Vector3.zero)+Vector3.new(0,-1,0),false)
            move.lastProgressAt=now;A.collectorWatch={position=move.root.Position,at=now}
            return true
        end
        if rising and A.collectorFeet(move).Y<top then
            local offset=truss.Position-move.root.Position
            local flat=Vector3.new(offset.X,0,offset.Z)
            local toward=flat.Magnitude>0.1 and flat.Unit or Vector3.zero
            move.humanoid.Jump=false
            move.humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing,true)
            move.humanoid:Move(toward+Vector3.new(0,1,0),false)
            move.lastProgressPosition=move.root.Position;move.lastProgressAt=now
            move.motionWindowPosition=nil;A.collectorWatch={position=move.root.Position,at=now}
            if now>=(move.nextClimbLog or 0)then
                move.nextClimbLog=now+1;A.log("ladder_climb",{ladder=truss,position=move.root.Position,goal=waypoint.Position,state=move.humanoid:GetState()})
            end
            return true
        end
    end
    move.lastProgressPosition=move.root.Position;move.lastProgressAt=now
    move.motionWindowPosition=nil;A.collectorWatch={position=move.root.Position,at=now}
    if move.climbGoal~=waypoint.Position or now-(move.climbCommandAt or 0)>0.5 then
        move.climbGoal=waypoint.Position;move.climbCommandAt=now
        move.humanoid:MoveTo(waypoint.Position)
    end
    return true
end

function A.collectorRecoveryClear(move,goal)
    local delta=goal-move.root.Position
    local flat=Vector3.new(delta.X,0,delta.Z)
    if flat.Magnitude<0.1 then return false end
    local side=Vector3.new(-flat.Z,0,flat.X).Unit*0.9
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
    params.FilterDescendantsInstances={move.character}
    for _,offset in ipairs({Vector3.zero,side,-side,Vector3.new(0,-1,0)})do
        if workspace:Raycast(move.root.Position+offset,flat,params)then return false end
    end
    return true
end
function A.collectorParallelPenalty(from,to)
    local direction=to-from
    direction=Vector3.new(direction.X,0,direction.Z)
    if direction.Magnitude<0.1 then return 0 end
    for _,threat in ipairs(A.collectorThreats)do
        if threat.future and A.collectorThreatRelevant(from,threat)then
            local current=threat.current or threat.position
            local distance=(from-current).Magnitude
            local travel=threat.future[#threat.future].position-current
            travel=Vector3.new(travel.X,0,travel.Z)
            if distance<48 and travel.Magnitude>2 and direction.Unit:Dot(travel.Unit)>0.5
                and (to-current).Magnitude<distance+8 then return 24 end
        end
    end
    return 0
end

function A.collectorDoorwayDirection(move,desired)
    if desired.Magnitude<0.1 or move.humanoid:GetState()==Enum.HumanoidStateType.Climbing then return desired end
    local forward=desired.Unit;local side=Vector3.new(-forward.Z,0,forward.X)
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local center,width
    for _,ahead in ipairs({0,1})do
        local origin=move.root.Position+forward*ahead
        local left=workspace:Raycast(origin,-side*3,params)
        local right=workspace:Raycast(origin,side*3,params)
        if left and right and math.abs(left.Normal.Y)<0.25 and math.abs(right.Normal.Y)<0.25 then
            local span=left.Distance+right.Distance
            if span>=1.8 and span<4.5 and(not width or span<width)then
                center=(right.Distance-left.Distance)*0.5;width=span
            end
        end
    end
    if not center or math.abs(center)<0.25 then return desired end
    local correction=side*math.clamp(center*1.5,-0.75,0.75)
    local direction=(forward+correction).Unit
    if workspace:Raycast(move.root.Position,direction*1.2,params)then return desired end
    if os.clock()>=(move.nextDoorwayLog or 0)then
        move.nextDoorwayLog=os.clock()+1;A.log("doorway_centering",{position=move.root.Position,width=width,offset=center})
    end
    return direction
end

function A.collectorOscillationStep(move,desired)
    local now=os.clock()
    local state=move.turnWatch
    if not state or now-state.at>1.2 or (move.root.Position-state.position).Magnitude>3 then
        state={at=now,position=move.root.Position,turns=0};move.turnWatch=state
    end
    if desired.Magnitude>0.1 and state.direction and state.direction:Dot(desired)<-0.25 then state.turns=state.turns+1 end
    if desired.Magnitude>0.1 then state.direction=desired.Unit end
    if state.turns<3 or move.humanoid.FloorMaterial==Enum.Material.Air then return false end
    local goal=A.collectorRecoveryGoal(move)
    A.log("oscillation_recovery",{position=move.root.Position,target=move.target,goal=goal,turns=state.turns})
    A.skipCollectorTarget(move,move.target,"Route oscillated at an obstacle; taking a clear exit",8)
    move.turnWatch=nil
    if goal then
        move.recoveryGoal=goal;move.recoveryUntil=now+1
        local delta=goal-move.root.Position;local flat=Vector3.new(delta.X,0,delta.Z)
        move.humanoid:Move(flat.Magnitude>0.1 and flat.Unit or Vector3.zero,false)
    else move.humanoid:Move(Vector3.zero,false)end
    return true
end

function A.collectorEscapePressure(root)
    if A.isZombie(A.player)then return {}end
    local now=os.clock();local threats={}
    A.approachSamples=A.approachSamples or setmetatable({},{__mode="k"})
    for _,threat in ipairs(A.collectorThreats)do
        if not threat.provisional and A.collectorThreatRelevant(root.Position,threat)then
            local enemy=threat.current or threat.position
            local delta=root.Position-enemy;local flat=Vector3.new(delta.X,0,delta.Z)
            local distance=flat.Magnitude
            local closing=0
            local h,r; if threat.player then local _,hum,part=A.body(threat.player);h=hum;r=part end
            if r and distance>0.1 then
                local v=r.AssemblyLinearVelocity
                if v.Magnitude<1 and h then v=h.MoveDirection*h.WalkSpeed end
                closing=math.max(v:Dot(flat.Unit),(v-root.AssemblyLinearVelocity):Dot(flat.Unit))
            end
            local sample=threat.player and A.approachSamples[threat.player]
            if sample and now-sample.at>=0.08 and now-sample.at<1 then
                closing=math.max(closing,(sample.distance-distance)/(now-sample.at))
            end
            if threat.player and(not sample or now-sample.at>=0.08)then
                A.approachSamples[threat.player]={distance=distance,at=now}
            end
            if math.abs(delta.Y)<=6 and(distance<18 or(distance<38 and closing>0.75))then
                threats[#threats+1]=threat
            end
        end
    end
    return threats
end
function A.collectorSupportedStairs(move,direction)
    if not move.waypoints or direction.Magnitude<0.1 then return false end
    local point=move.waypoints[move.pathIndex or 1]
    if not point or point.Action==Enum.PathWaypointAction.Jump or point.Label=="Climb"then return false end
    local now=os.clock();local cache=move.stairProbe
    if cache and now-cache.at<0.12 and cache.direction:Dot(direction.Unit)>0.9 then return cache.value end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    -- Smooth ramps can be steeper than the former fixed 53-degree cutoff.
    -- Honor a lower humanoid limit, and keep near-vertical rock faces excluded.
    local minNormal=math.cos(math.rad(math.clamp(move.humanoid.MaxSlopeAngle,0,60)))
    local previous;local changed=false;local supported=true
    for _,distance in ipairs({0,0.6,1.2,1.8})do
        local at=move.root.Position+direction.Unit*distance+Vector3.new(0,1,0)
        local hit=workspace:Raycast(at,Vector3.new(0,-8,0),params)
        if not hit or hit.Normal.Y<minNormal then supported=false;break end
        if previous then
            local rise=hit.Position.Y-previous
            if math.abs(rise)>1.1 then supported=false;break end
            if math.abs(rise)>0.08 then changed=true end
        end
        previous=hit.Position.Y
    end
    if supported and changed then
        -- Probe above the stair treads; real walls still block the corridor.
        for _,side in ipairs({0,-0.7,0.7})do
            local offset=Vector3.new(-direction.Z,0,direction.X).Unit*side
            if workspace:Raycast(move.root.Position+Vector3.new(0,2,0)+offset,direction.Unit*1.8,params)then supported=false;break end
        end
    end
    local value=supported and changed
    move.stairProbe={at=now,direction=direction.Unit,value=value}
    return value
end

function A.collectorObstacleLoop(move)
    local now=os.clock()
    local loop=move.obstacleLoop
    if not loop or loop.target~=move.target or now-loop.at>5 or (move.root.Position-loop.position).Magnitude>4 then
        loop={at=now,position=move.root.Position,target=move.target,count=0};move.obstacleLoop=loop
    end
    if now-(loop.last or -10)<0.7 then return false end
    loop.last=now;loop.count=loop.count+1
    if loop.count<4 then return false end
    move.obstacleLoop=nil
    A.log("obstacle_loop_abandoned",{position=move.root.Position,target=move.target,recoveries=loop.count})
    A.skipCollectorTarget(move,move.target,"Repeated obstacle recovery; choosing a different route",8)
    return true
end

function A.collectorCornerDetour(move,desired)
    if not move.waypoints or desired.Magnitude<0.1 then return nil end
    local point=move.waypoints[move.pathIndex or 1]
    if not point or point.Label=="Climb"or point.Action==Enum.PathWaypointAction.Jump then return nil end
    local origin=move.root.Position;local feet=A.collectorFeet(move)
    local forward=desired.Unit;local side=Vector3.new(-forward.Z,0,forward.X)
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local size=Vector3.new(math.max(1,move.root.Size.X),3.4,math.max(0.8,move.root.Size.Z))
    local function clear(from,to)
        local delta=Vector3.new(to.X-from.X,0,to.Z-from.Z)
        if delta.Magnitude<0.1 then return false end
        if workspace:Blockcast(CFrame.lookAt(from,from+delta),size,delta,params)then return false end
        local steps=math.ceil(delta.Magnitude)
        for i=1,steps do
            local hit=workspace:Raycast(from+delta*(i/steps),Vector3.new(0,-5,0),params)
            if not hit or hit.Normal.Y<0.65 or math.abs(hit.Position.Y-feet.Y)>1.25 then return false end
        end
        return A.collectorSegmentSafe(from,to)
    end
    -- Select a short route with both legs clear, rather than taking a blind
    -- side-step that immediately turns back into the same corner.
    for index=move.pathIndex or 1,math.min(#move.waypoints,(move.pathIndex or 1)+4)do
        local waypoint=move.waypoints[index]
        if waypoint.Label=="Climb"or waypoint.Action==Enum.PathWaypointAction.Jump
            or math.abs(waypoint.Position.Y-(feet.Y+(move.navHeightOffset or 0)))>1.8 then break end
        local goal=Vector3.new(waypoint.Position.X,origin.Y,waypoint.Position.Z)
        local approach=goal-origin
        if approach.Magnitude>8 then goal=origin+approach.Unit*8 end
        if (goal-origin).Magnitude>=2 then
            for _,distance in ipairs({1.5,2.5,3.5})do
                for _,sign in ipairs({1,-1})do
                    local corner=origin+side*(distance*sign)
                    if clear(origin,corner)and clear(corner,goal)then return corner end
                end
            end
        end
    end
    return nil
end
function A.collectorObstacleStep(move,desired)
    local state=move.humanoid:GetState()
    if state==Enum.HumanoidStateType.Jumping or state==Enum.HumanoidStateType.Freefall then return false end
    if desired.Magnitude<0.1 or move.humanoid.FloorMaterial==Enum.Material.Air
        or move.jumpPending or move.humanoid:GetState()==Enum.HumanoidStateType.Climbing then return false end
    if A.collectorSupportedStairs(move,desired)then return false end
    if A.collectorBodyClear(move,desired.Unit,1.1)then return false end
    local corner=A.collectorCornerDetour(move,desired)
    if corner then
        local direction=(corner-move.root.Position).Unit
        A.clearWalkRoute(move,true)
        move.recoveryGoal=corner;move.recoveryUntil=os.clock()+(corner-move.root.Position).Magnitude/16+0.4
        move.walkDirection=direction;move.airDirection=direction;move.smoothDirection=direction
        move.humanoid:Move(direction,false)
        A.log("corner_detour",{position=move.root.Position,goal=corner,target=move.target})
        return true
    end
    if A.collectorObstacleLoop(move)then
        local goal=A.collectorRecoveryGoal(move)
        if goal and A.collectorRecoveryClear(move,goal)and A.collectorSegmentSafe(move.root.Position,goal)then
            local delta=goal-move.root.Position
            local direction=Vector3.new(delta.X,0,delta.Z)
            if direction.Magnitude>0.1 then
                move.recoveryGoal=goal;move.recoveryUntil=os.clock()+direction.Magnitude/16+0.3
                move.walkDirection=direction.Unit;move.airDirection=direction.Unit
                move.humanoid:Move(direction.Unit,false)
                A.log("obstacle_loop_retreat",{position=move.root.Position,goal=goal})
                return true
            end
        end
    end
    local now=os.clock();move.replan=true;move.nextPlanAt=0
    local side=Vector3.new(-desired.Z,0,desired.X).Unit*(move.obstacleSide or 1)
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    for _,direction in ipairs({side,-side,-desired.Unit})do
        local goal=move.root.Position+direction*2
        if A.collectorBodyClear(move,direction,2)and A.collectorSegmentSafe(move.root.Position,goal)then
            local hit=workspace:Raycast(goal,Vector3.new(0,-5,0),params)
            if hit and hit.Normal.Y>0.6 and math.abs(hit.Position.Y-A.collectorFeet(move).Y)<1.5 then
                move.recoveryGoal=goal;move.recoveryUntil=now+0.4
                move.humanoid:Move(direction,false)
                if now>=(move.nextObstacleLog or 0)then
                    move.nextObstacleLog=now+1;A.log("body_obstacle_recovery",{position=move.root.Position,goal=goal})
                end
                return true
            end
        end
    end
    move.humanoid:Move(Vector3.zero,false)
    return true
end

function A.collectorBodyClear(move,direction,length)
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local feet=A.collectorFeet(move)
    local center=Vector3.new(move.root.Position.X,feet.Y+3,move.root.Position.Z)
    local forward=Vector3.new(direction.X,0,direction.Z)
    if forward.Magnitude<0.01 then return true end
    local footprint=move.root.Size
    local size=Vector3.new(math.max(1,footprint.X),3.4,math.max(0.8,footprint.Z))
    return workspace:Blockcast(CFrame.lookAt(center,center+forward),size,forward.Unit*length,params)==nil
end
function A.collectorEscapeExits(move,point)
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local exits=0
    for i=0,7 do
        local d=Vector3.new(math.cos(i*math.pi/4),0,math.sin(i*math.pi/4))*5
        if not workspace:Blockcast(CFrame.new(point+Vector3.new(0,3,0)),Vector3.new(2,3.4,2),d,params)then
            local support=workspace:Raycast(point+d+Vector3.new(0,3,0),Vector3.new(0,-6,0),params)
            if support and support.Normal.Y>0.6 then exits=exits+1 end
        end
    end
    return exits
end
function A.collectorJumpClearance(move,needed)
    local h=move.humanoid
    if not h:GetStateEnabled(Enum.HumanoidStateType.Jumping)then return false end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local top=move.root.Position+Vector3.new(0,move.root.Size.Y/2+0.25,0)
    return workspace:Raycast(top,Vector3.new(0,math.max(2,needed or 3),0),params)==nil
end
function A.collectorLadderExitCandidates(move,params,candidates)
    local now=os.clock()
    if now>=(A.nextEscapeLadderScan or 0)then
        A.nextEscapeLadderScan=now+2;A.escapeLadders={}
        for _,part in ipairs(workspace:GetDescendants())do if part:IsA("TrussPart")then A.escapeLadders[#A.escapeLadders+1]=part end end
    end
    local feet=A.collectorFeet(move)
    for _,ladder in ipairs(A.escapeLadders or {})do
        if ladder.Parent and(ladder.Position-move.root.Position).Magnitude<50 then
            local size=A.collectorTrussSize(ladder)
            local top=ladder.Position.Y+size.Y/2
            if top>feet.Y+4 and feet.Y>=ladder.Position.Y-size.Y/2-4 then
                for i=0,3 do
                    local d=Vector3.new(math.cos(i*math.pi/2),0,math.sin(i*math.pi/2))*3
                    local point=Vector3.new(ladder.Position.X,top,ladder.Position.Z)+d
                    local hit=workspace:Raycast(point+Vector3.new(0,3,0),Vector3.new(0,-6,0),params)
                    if hit and hit.Normal.Y>0.6 and math.abs(hit.Position.Y-top)<3
                        and A.collectorEscapeExits(move,hit.Position)>=2 then
                        candidates[#candidates+1]={point=hit.Position,score=40-(move.root.Position-ladder.Position).Magnitude*0.2,ladder=ladder}
                    end
                end
            end
        end
    end
end

function A.collectorPlanEscape(move,nearby)
    local now=os.clock()
    local active=move.escapeRoute
    if active and move.humanoid:GetState()==Enum.HumanoidStateType.Climbing then return end
    if move.escapePlanning or now<(move.nextEscapePlan or 0)then return end
    move.escapePlanning=true;move.nextEscapePlan=now+0.65
    local origin=move.root.Position;local feet=A.collectorFeet(move)
    A.spawn(function()
        local chosen
        local ok,err=pcall(function()
            local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
            local candidates={}
            for i=0,11 do
                local d=Vector3.new(math.cos(i*math.pi/6),0,math.sin(i*math.pi/6))*18
                local hit=workspace:Raycast(feet+d+Vector3.new(0,4,0),Vector3.new(0,-10,0),params)
                if hit and hit.Normal.Y>0.6 and math.abs(hit.Position.Y-feet.Y)<5 then
                    local gain=math.huge
                    for _,threat in ipairs(nearby)do
                        local enemy=threat.current or threat.position
                        gain=math.min(gain,(hit.Position-enemy).Magnitude-(feet-enemy).Magnitude)
                    end
                    if gain>4 then
                        local exits=A.collectorEscapeExits(move,hit.Position)
                        if exits>=3 then candidates[#candidates+1]={point=hit.Position,score=gain+exits}end
                    end
                end
            end
            A.collectorLadderExitCandidates(move,params,candidates)
            table.sort(candidates,function(a,b)return a.score>b.score end)
            for i=1,math.min(5,#candidates)do
                if not A.alive or A.movement~=move then break end
                local path=game:GetService("PathfindingService"):CreatePath({AgentRadius=1.25,AgentHeight=5,
                    AgentCanJump=true,AgentCanClimb=true,WaypointSpacing=2,Costs={CollectorDanger=1,CollectorRailing=math.huge}})
                A.resources[path]=true
                local success=pcall(function()path:ComputeAsync(origin,candidates[i].point)end)
                if success and path.Status==Enum.PathStatus.Success then
                    local points=path:GetWaypoints();local safe=#points>1
                    for _,point in ipairs(points)do
                        for _,threat in ipairs(nearby)do
                            local enemy=threat.current or threat.position
                            if(point.Position-enemy).Magnitude<(feet-enemy).Magnitude-1 then safe=false;break end
                        end
                        if not safe then break end
                    end
                    if safe then chosen={points=points,index=2,at=os.clock(),origin=origin,ladder=candidates[i].ladder};end
                end
                A.resources[path]=nil;path:Destroy()
                if chosen then break end
            end
        end)
        if not A.alive then return end
        move.escapePlanning=false
        if not ok then A.log("escape_route_error",{error=err})end
        if chosen and A.movement==move and(move.root.Position-origin).Magnitude<10 then
            move.escapeRoute=chosen
            A.log("escape_route_ready",{origin=origin,goal=chosen.points[#chosen.points].Position,waypoints=#chosen.points})
        end
    end)
end
function A.collectorEscapeProgress(move)
    local now=os.clock();local position=move.root.Position
    if move.humanoid.FloorMaterial==Enum.Material.Air or move.humanoid:GetState()==Enum.HumanoidStateType.Climbing then move.escapeMotionSample=nil;return end
    local sample=move.escapeMotionSample
    if not sample then move.escapeMotionSample={at=now,position=position};return end
    if now-sample.at<0.45 then return end
    move.escapeMotionSample={at=now,position=position}
    local delta=position-sample.position
    if Vector3.new(delta.X,0,delta.Z).Magnitude<0.4
        and move.escapeDirection and move.escapeDirection.Magnitude>0.1 then
        move.escapeBlockedDirection=move.escapeDirection;move.escapeBlockedUntil=now+1.2
        move.escapeRoute=nil;move.localEscapeStep=nil;move.nextEscapePlan=0
        A.log("escape_motion_blocked",{position=position,direction=move.escapeDirection})
    end
end
function A.collectorEscapeDirectionBlocked(move,direction)
    return (move.escapeBlockedUntil or 0)>os.clock()and move.escapeBlockedDirection
        and direction:Dot(move.escapeBlockedDirection)>0.8
end
function A.collectorFollowEscape(move,nearby)
    local route=move.escapeRoute
    if not route then return false end
    if os.clock()-route.at>7 then move.escapeRoute=nil;return false end
    local point=route.points[route.index]
    while point do
        local d=point.Position-A.collectorFeet(move)
        if Vector3.new(d.X,0,d.Z).Magnitude>1.2 or math.abs(d.Y)>2 then break end
        route.index=route.index+1;point=route.points[route.index]
    end
    if not point then move.escapeRoute=nil;return false end
    local delta=point.Position-move.root.Position;local flat=Vector3.new(delta.X,0,delta.Z)
    if flat.Magnitude<0.05 then return false end
    local direction=flat.Unit
    if A.collectorEscapeDirectionBlocked(move,direction)then move.escapeRoute=nil;return false end
    for _,threat in ipairs(nearby)do
        local enemy=threat.current or threat.position
        if(point.Position-enemy).Magnitude<(A.collectorFeet(move)-enemy).Magnitude-1 then move.escapeRoute=nil;return false end
    end
    local climbing=move.humanoid:GetState()==Enum.HumanoidStateType.Climbing
    local truss=A.collectorNearbyTruss(move,point)
    if climbing or point.Label=="Climb"or(truss and point.Position.Y>A.collectorFeet(move).Y+2)then
        local ladder=truss or route.ladder
        local descending=point.Position.Y<A.collectorFeet(move).Y-2
        if climbing and not descending and A.collectorBeginLadderExit(move,ladder)then return true end
        local toward=ladder and ladder.Position-move.root.Position or flat
        toward=Vector3.new(toward.X,0,toward.Z)
        move.humanoid.Jump=false
        move.humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing,true)
        move.humanoid:Move((toward.Magnitude>0.1 and toward.Unit or direction)+Vector3.new(0,descending and -1 or 1,0),false)
        move.lastProgressAt=os.clock();A.collectorWatch={position=move.root.Position,at=os.clock()}
        return true
    end
    if point.Action==Enum.PathWaypointAction.Jump and move.humanoid.FloorMaterial~=Enum.Material.Air then
        if not A.collectorJumpClearance(move,math.max(2,point.Position.Y-A.collectorFeet(move).Y+1))then
            move.escapeRoute=nil;move.nextEscapePlan=os.clock()+1
            A.log("escape_jump_blocked_ceiling",{position=move.root.Position,goal=point.Position})
            return false
        end
        if os.clock()>(move.nextEscapeJump or 0)then
            move.nextEscapeJump=os.clock()+1.3;move.airDirection=direction
            move.humanoid.Jump=true;move.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    elseif A.collectorSmallObstacleStep(move,direction)then return true
    elseif not A.collectorBodyClear(move,direction,math.min(flat.Magnitude,1.8))then
        move.escapeRoute=nil;move.nextEscapePlan=0;return false
    end
    move.escapeDirection=direction;move.walkDirection=direction;move.smoothDirection=direction
    move.humanoid:Move(direction,false)
    move.lastProgressAt=os.clock();A.collectorWatch={position=move.root.Position,at=os.clock()}
    return true
end
function A.collectorTrappedJump(move,nearby)
    local now=os.clock()
    if now<(move.nextTrappedJump or 0)or move.humanoid.FloorMaterial==Enum.Material.Air then return false end
    local threat=nearby[1];if not threat then return false end
    local delta=(threat.current or threat.position)-move.root.Position
    local flat=Vector3.new(delta.X,0,delta.Z)
    if flat.Magnitude>9 or flat.Magnitude<0.5 then return false end
    local h=move.humanoid;local gravity=math.max(workspace.Gravity,1)
    local power=h.UseJumpPower and h.JumpPower or math.sqrt(2*gravity*h.JumpHeight)
    if power^2/(2*gravity)<4 or not h:GetStateEnabled(Enum.HumanoidStateType.Jumping)then return false end
    local speed=math.min(h.WalkSpeed,16);local flight=2*power/gravity
    local length=speed*flight
    if length<flat.Magnitude+2 then return false end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local feet=A.collectorFeet(move);local direction=flat.Unit;local landing=feet+direction*length
    local ground=workspace:Raycast(landing+Vector3.new(0,3,0),Vector3.new(0,-6,0),params)
    if not ground or ground.Normal.Y<0.65 or math.abs(ground.Position.Y-feet.Y)>1.5 then return false end
    local previous=feet+Vector3.new(0,3,0)
    for i=1,8 do
        local t=flight*i/8
        local point=feet+direction*(speed*t)+Vector3.new(0,3+power*t-gravity*t*t/2,0)
        if workspace:Blockcast(CFrame.new(previous),Vector3.new(2,3.4,2),point-previous,params)then return false end
        previous=point
    end
    move.nextTrappedJump=now+2.5;move.airDirection=direction;move.trappedJumpUntil=now+flight
    move.humanoid.Jump=true;move.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    move.humanoid:Move(direction,false)
    A.log("trapped_jump_escape",{origin=move.root.Position,landing=ground.Position,threat=threat.player and threat.player.Name})
    return true
end

function A.collectorDefensiveShot(move,nearby)
    if not A.findTool(A.player,"Gun")or A.role(A.player)=="Murderer"then return false end
    local chosen,score=nil,0
    for _,threat in ipairs(nearby)do
        if threat.player and not threat.provisional then
            local enemy=threat.current or threat.position
            local delta=move.root.Position-enemy;local distance=delta.Magnitude
            local _,_,root=A.body(threat.player)
            local closing=root and distance>0.1 and root.AssemblyLinearVelocity:Dot(delta.Unit)or 0
            -- This is a danger threshold, not a calibrated death probability.
            local risk=0.4+math.clamp((18-distance)/18,0,0.45)+(closing>3 and 0.2 or 0)
            if risk>=0.8 and risk>score then chosen,score=threat.player,risk end
        end
    end
    if not chosen then return false end
    A.collectorDefensiveTarget=chosen;A.collectorDefensiveUntil=os.clock()+1
    if os.clock()>=(A.nextDefenseLog or 0)then
        A.nextDefenseLog=os.clock()+1;A.log("trapped_defensive_shot",{target=chosen.Name,dangerScore=score})
    end
    return true
end
function A.collectorAutoGunStep()
    if not A.config.autoGun or A.collectorGunPickupBusy then return end
    local state=getgenv().QOS_MM2_TP_STATE
    if A.collectorTeleportBlocked(state)then return end
    if A.config.farm then
        if not A.inRound()or A.role(A.player)=="Murderer"or A.findTool(A.player,"Gun")
            or not A.drop()or os.clock()<(A.nextGunAttempt or 0)then return end
        if A.movement and A.movement.owner~="farm"then return end
        if A.movement then A.releaseMove(false)end
    end
    A.collectorGunPickupBusy=true
    local ok,err=pcall(A.grabGun)
    A.collectorGunPickupBusy=false
    if not ok then error(err)end
end

function A.collectorPlanningEscape(move)
    if A.collectorRecoveryActive(move)then return false end
    if A.collectorFullCombatPriority()then return false end
    if A.role(A.player)=="Murderer"then return false end
    local origin=move.root.Position;local nearby=A.collectorEscapePressure(move.root)
    if (move.trappedJumpUntil or 0)>os.clock()then
        move.humanoid:Move(move.airDirection or Vector3.zero,false);return true
    end
    if #nearby==0 then move.planningEscape=nil;move.escapeRoute=nil;move.escapeMotionSample=nil;return false end
    A.collectorEscapeProgress(move)
    A.collectorPlanEscape(move,nearby)
    if A.collectorFollowEscape(move,nearby)then return true end
    local step=move.localEscapeStep
    if step and os.clock()<step.untilAt then
        local d=step.goal-origin;local flat=Vector3.new(d.X,0,d.Z)
        if flat.Magnitude>0.6 and A.collectorBodyClear(move,flat.Unit,math.min(flat.Magnitude,1.5))then
            local safe=true
            for _,threat in ipairs(nearby)do
                local enemy=threat.current or threat.position
                if(step.goal-enemy).Magnitude<(origin-enemy).Magnitude-0.1 then safe=false;break end
            end
            if safe then move.humanoid:Move(flat.Unit,false);return true end
        end
    end
    -- Danger overrides route waiting, recovery and a stationary sheriff attack.
    move.recoveryGoal=nil;move.jumpPending=false
    local now=os.clock();local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local best,bestScore=nil,-math.huge
    for _,length in ipairs({5,2.5,1.25})do
        for i=0,15 do
            local angle=i*math.pi/8;local direction=Vector3.new(math.cos(angle),0,math.sin(angle))
            local side=Vector3.new(-direction.Z,0,direction.X)*0.65
            local goal=origin+direction*length;local clear=not A.collectorEscapeDirectionBlocked(move,direction)
            for _,offset in ipairs({Vector3.zero,side,-side,Vector3.new(0,-1,0)})do
                if workspace:Raycast(origin+offset,direction*length,params)then clear=false;break end
            end
            if clear and not A.collectorBodyClear(move,direction,length)then clear=false end
            if clear then
                local y=A.collectorFeet(move).Y
                for j=1,math.ceil(length)do
                    local point=origin+direction*(length*j/math.ceil(length))
                    local hit=workspace:Raycast(point,Vector3.new(0,-6,0),params)
                    if not hit or hit.Normal.Y<0.6 or math.abs(hit.Position.Y-y)>1.5 then clear=false;break end
                    y=hit.Position.Y
                end
            end
            if clear then
                local score=math.huge
                for _,threat in ipairs(nearby)do
                    local enemy=threat.current or threat.position
                    local gain=(goal-enemy).Magnitude-(origin-enemy).Magnitude
                    if gain<-0.1 then clear=false;break end
                    score=math.min(score,(goal-(threat.position or enemy)).Magnitude+gain*2)
                end
                if clear then
                    if move.escapeDirection then score=score+direction:Dot(move.escapeDirection)*0.3 end
                    if score>bestScore then best,bestScore=goal,score end
                end
            end
        end
        if best then break end
    end
    if not best then
        A.collectorDefensiveShot(move,nearby)
        if A.collectorTrappedJump(move,nearby)then return true end
        if now>=(move.nextEscapeBlockedLog or 0)then move.nextEscapeBlockedLog=now+1;A.log("escape_no_clear_step",{position=origin})end
        return false
    end
    move.localEscapeStep={goal=best,untilAt=now+0.18}
    local delta=best-origin;move.escapeDirection=Vector3.new(delta.X,0,delta.Z).Unit
    move.walkDirection=move.escapeDirection;move.smoothDirection=move.escapeDirection
    move.humanoid:Move(move.escapeDirection,false)
    move.lastProgressAt=now;A.collectorWatch={position=origin,at=now}
    if now>=(move.nextPlanningEscapeLog or 0)then
        move.nextPlanningEscapeLog=now+1;A.log("approaching_murderer_escape",{origin=origin,goal=best,combat=A.collectorCombatRole})
    end
    return true
end
function A.collectorObstacleAirDirection(jump,position)
    if jump.landingReached then return Vector3.zero end
    local remaining=jump.landingGoal-position
    local flat=Vector3.new(remaining.X,0,remaining.Z)
    -- Stop at the checked landing plane; never reverse in midair after passing it.
    if flat:Dot(jump.direction)<=0.65 then
        jump.landingReached=true
        A.log("obstacle_hop_landing_reached",{position=position,goal=jump.landingGoal})
        return Vector3.zero
    end
    return jump.direction
end
function A.collectorAirStep(move)
    local state=move.humanoid:GetState()
    -- Humanoid state changes before FloorMaterial on takeoff. Preserve air steering
    -- during that transition, especially when jumping past a nearby threat.
    local airborne=state==Enum.HumanoidStateType.Jumping or state==Enum.HumanoidStateType.Freefall
    if not airborne then
        if move.airStarted then
            move.landedAt=os.clock();move.jumpPending=false;move.humanoid.Jump=false
            if move.obstacleJump then
                move.walkDirection=move.obstacleJump.direction;move.smoothDirection=move.walkDirection
                move.obstacleJump=nil;A.clearWalkRoute(move,true);move.replan=true;move.nextPlanAt=0
            end
            if os.clock()-move.airStarted>0.8 then move.replan=true;move.nextPlanAt=0 end
        end
        move.airStarted=nil
        if move.walkDirection and move.walkDirection.Magnitude>0.1 then move.airDirection=move.walkDirection.Unit end
        return false
    end
    local now=os.clock();move.airStarted=move.airStarted or now
    move.jumpPending=false;move.humanoid.Jump=false

    local direction=move.airDirection or move.walkDirection or Vector3.zero
    local index=move.pathIndex or 1
    local recovering=A.collectorRecoveryActive(move)
    if recovering then
        local delta=move.recoveryGoal-move.root.Position
        direction=Vector3.new(delta.X,0,delta.Z).Unit
    end
    local hopping=move.obstacleJump and now<move.obstacleJump.untilAt
    if hopping and not recovering then
        local jump=move.obstacleJump
        direction=jump.direction
        if jump.landingGoal then
            direction=A.collectorObstacleAirDirection(jump,move.root.Position)
        elseif jump.goal then
            local offset=jump.goal-move.root.Position
            local flat=Vector3.new(offset.X,0,offset.Z)
            direction=flat.Magnitude>0.65 and flat.Unit or Vector3.zero
        end
    end
    local points=not hopping and not recovering and not((move.trappedJumpUntil or 0)>now)and move.waypoints
    local point=points and points[index]
    if point and point.Action==Enum.PathWaypointAction.Jump and points[index+1]then index+=1;point=points[index] end
    while point and points[index+1]do
        local offset=point.Position-move.root.Position
        if Vector3.new(offset.X,0,offset.Z).Magnitude>0.8 then break end
        index+=1;point=points[index]
        move.pathIndex=index
    end
    if point then
        local delta=point.Position-move.root.Position;local flat=Vector3.new(delta.X,0,delta.Z)
        if flat.Magnitude>0.8 then direction=flat.Unit
        else direction=Vector3.zero end
    end
    if direction.Magnitude<0.1 then move.humanoid:Move(Vector3.zero,false);return true end
    move.airDirection=A.collectorDodgeDirection(move,direction.Unit)
    move.humanoid:Move(move.airDirection,false)
    move.lastProgressAt=now;move.lastProgressPosition=move.root.Position
    A.collectorWatch={position=move.root.Position,at=now}
    return true
end


function A.walkInput(dt)
    local move=A.movement
    if A.alive and A.config.farm and move and move.walking and move.character==A.player.Character
        and move.humanoid.Health>0 then
        A.updateCollectorThreats()
        if A.collectorOrphanClimbStep(move.root)then return end
        if A.collectorAirStep(move)then return end
        if A.collectorCombatRole then A.collectorCombatJump(move.humanoid)
        elseif A.collectorKnifeEscape(move.root) or A.collectorEmergencyTeleport(move.root) then return end
        if A.collectorRangedStep(move)then return end
        if A.collectorMuzzleEscapeStep(move)then return end
        if A.collectorPlanningEscape(move)then return end
        if A.collectorAirStep(move)then return end
        if A.collectorRaisedPickupStep(move) or A.collectorClimbStep(move) then return end
        local humanoid=move.humanoid
        if move.recoveryGoal then
            local delta=move.recoveryGoal-move.root.Position
            local flat=Vector3.new(delta.X,0,delta.Z)
            if flat.Magnitude<0.7 or os.clock()>move.recoveryUntil then
                move.recoveryGoal=nil;move.replan=true;move.nextPlanAt=0
                move.motionWindowPosition=nil;move.lastProgressAt=os.clock()
                move.walkDirection=Vector3.zero;move.smoothDirection=Vector3.zero
                humanoid:Move(Vector3.zero,false)
            elseif A.collectorRecoveryClear(move,move.recoveryGoal) and A.collectorSegmentSafe(move.root.Position,move.recoveryGoal) then humanoid:Move(flat.Unit,false)
            else
                move.recoveryGoal=nil;move.nextEvadeAt=0;move.replan=true
                move.walkDirection=Vector3.zero;move.smoothDirection=Vector3.zero
                humanoid:Move(Vector3.zero,false)
            end
            return
        end
        if move.coastUntil and not move.waypoints then
            if os.clock()>move.coastUntil then move.walkDirection=Vector3.zero;move.coastUntil=nil
            else
                local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
                local step=(move.walkDirection or Vector3.zero)*2
                local ground=workspace:Raycast(move.root.Position+step,Vector3.new(0,-5,0),params)
                if workspace:Raycast(move.root.Position,step,params) or not ground
                    or ground.Normal.Y<0.6 or not A.collectorSegmentSafe(move.root.Position,move.root.Position+step) then
                    move.walkDirection=Vector3.zero;move.coastUntil=nil
                end
            end
        end
        local desired=move.walkDirection or Vector3.zero
        local waypoint=move.waypoints and move.waypoints[move.pathIndex or 1]
        if desired.Magnitude>0.01 and move.waypoints then
            -- Advance passed waypoints every frame rather than waiting for the
            -- slower route-management tick, avoiding backtracking at corners.
            while waypoint do
                local delta=waypoint.Position-move.root.Position
                if not A.collectorWaypointReached(move,waypoint) then break end
                if waypoint.Action==Enum.PathWaypointAction.Jump and move.jumpedIndex~=move.pathIndex then break end
                move.pathIndex=(move.pathIndex or 1)+1
                waypoint=move.waypoints[move.pathIndex]
            end
            if waypoint then
                local delta=waypoint.Position-move.root.Position
                local flat=Vector3.new(delta.X,0,delta.Z)
                if A.collectorSegmentSafe(move.root.Position,waypoint.Position) then
                    desired=flat.Magnitude>0.01 and flat.Unit or Vector3.zero
                else desired=Vector3.zero;move.walkDirection=Vector3.zero;move.replan=true end
            else
                A.collectorCoast(move)
                desired=move.walkDirection or Vector3.zero
            end
        end
        if A.collectorDirectCandyHop(move)then return end
        if A.collectorSmallObstacleStep(move,desired)then return end
        desired=A.collectorDoorwayDirection(move,desired)
        desired=A.collectorStableDirection(move,desired)
        if A.collectorObstacleStep(move,desired)then return end
        if A.collectorOscillationStep(move,desired)then return end
        -- Follow sharp path corners precisely; smoothing must not cut across walls.
        local previous=move.smoothDirection or Vector3.zero
        if desired.Magnitude>0.01 and previous.Magnitude>0.01 and previous:Dot(desired)<0.7 then
            move.smoothDirection=desired
        else
            move.smoothDirection=A.smoothWalkDirection(previous,desired,dt)
        end
        if move.smoothDirection.Magnitude>0.01 and not A.collectorSegmentSafe(move.root.Position,move.root.Position+move.smoothDirection*2)then
            move.smoothDirection=Vector3.zero;move.walkDirection=Vector3.zero;move.replan=true;move.nextEvadeAt=0
        end
        local applied=A.collectorDodgeDirection(move,move.smoothDirection)
        humanoid:Move(applied,false)
        if move.jumpPending and humanoid.FloorMaterial~=Enum.Material.Air
            and os.clock()-(move.lastJumpAt or -10)>=0.6
            and humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
            move.lastJumpAt=os.clock()
            move.lastJumpPosition=move.root.Position
            humanoid.Jump=true
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            if humanoid:GetState()==Enum.HumanoidStateType.Jumping then
                if move.jumpRequestedIndex~=nil then move.jumpedIndex=move.jumpRequestedIndex end
                move.jumpPending=false
            end
        end
    end
end
function A.collectorEvadeGoal(move)
    local root=move.root
    local current=A.collectorThreatDistance(root.Position)
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local best,score=nil,-math.huge
    for i=0,15 do
        local angle=i*math.pi/8
        local direction=Vector3.new(math.cos(angle),0,math.sin(angle))
        local side=Vector3.new(-direction.Z,0,direction.X)*0.8
        local goal=root.Position+direction*6
        local blocked=false
        for _,offset in ipairs({Vector3.zero,side,-side,Vector3.new(0,-1,0)}) do
            if workspace:Raycast(root.Position+offset,direction*6,params)then blocked=true;break end
        end
        local ground=not blocked and workspace:Raycast(goal,Vector3.new(0,-7,0),params)
        if ground and ground.Normal.Y>=0.6 and A.collectorSegmentSafe(root.Position,goal) then
            local distance=A.collectorThreatDistance(goal)
            if distance>current+1 then
                local exits=A.collectorExitCount(move,goal)
                local candidateScore=distance+(exits==0 and -40 or exits*2)
                if candidateScore>score then best,score=goal,candidateScore end
            end
        end
    end
    return best
end

function A.collectorWalkClear(move,point)
    if math.abs(point.Y-(A.collectorFeet(move).Y+(move.navHeightOffset or 0)))>1.5 then return false end
    local flat=Vector3.new(point.X-move.root.Position.X,0,point.Z-move.root.Position.Z)
    if flat.Magnitude<0.1 or flat.Magnitude>10 then return false end
    -- Shortcut clearance must cover the same body volume as walking.
    -- Thin rays alone miss low edges and overhangs between sample heights.
    if not A.collectorBodyClear(move,flat.Unit,flat.Magnitude)then return false end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local side=Vector3.new(-flat.Z,0,flat.X).Unit*0.9
    for _,offset in ipairs({Vector3.zero,side,-side,Vector3.new(0,-1,0)}) do
        if workspace:Raycast(move.root.Position+offset,flat,params) then return false end
    end
    local previous
    for i=0,math.ceil(flat.Magnitude/2) do
        local sample=move.root.Position+flat*(i/math.ceil(flat.Magnitude/2))
        local hit=workspace:Raycast(sample,Vector3.new(0,-5,0),params)
        if not hit or hit.Normal.Y<0.6 or (previous and math.abs(hit.Position.Y-previous)>1.25) then return false end
        previous=hit.Position.Y
    end
    return A.collectorSegmentSafe(move.root.Position,point)
end
function A.collectorDoorClosed(object)
    local ancestor=object.Parent
    for _=1,5 do
        if not ancestor or ancestor==workspace then break end
        local moving=ancestor:FindFirstChild("DoorMain")
        local frame=ancestor:FindFirstChild("Main")
        local leaf=moving and moving:FindFirstChild("Door")
        if leaf and leaf:IsA("BasePart")and frame and frame:IsA("BasePart")then
            local leafAxis=leaf.Size.X>=leaf.Size.Z and leaf.CFrame.RightVector or leaf.CFrame.LookVector
            local frameAxis=frame.Size.X>=frame.Size.Z and frame.CFrame.RightVector or frame.CFrame.LookVector
            return math.abs(leafAxis:Dot(frameAxis))>0.9
        end
        ancestor=ancestor.Parent
    end
    return nil
end
function A.collectorDoorBlocksRoute(object,root)
    local move=A.movement
    if not move or move.owner~="farm"or move.root~=root or not move.waypoints then return false end
    local scope=object.Parent
    for _=1,5 do
        if not scope or scope==workspace then return false end
        if scope.Name:lower():find("door",1,true)then break end
        scope=scope.Parent
    end
    if not scope or scope==workspace or not scope.Name:lower():find("door",1,true)then return false end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local start=root.Position;local remaining=10
    local height=root.Position.Y-A.collectorFeet(move).Y-(move.navHeightOffset or 0)
    for i=move.pathIndex or 1,math.min(#move.waypoints,(move.pathIndex or 1)+4)do
        local finish=move.waypoints[i].Position+Vector3.new(0,height,0)
        local delta=finish-start
        if delta.Magnitude>0.1 then
            local length=math.min(delta.Magnitude,remaining)
            local flat=Vector3.new(delta.X,0,delta.Z)
            local side=flat.Magnitude>0.1 and Vector3.new(-flat.Z,0,flat.X).Unit*0.65 or Vector3.zero
            for _,offset in ipairs({Vector3.zero,side,-side})do
                local hit=workspace:Raycast(start+offset,delta.Unit*length,params)
                if hit and(hit.Instance==scope or hit.Instance:IsDescendantOf(scope))then return true end
            end
            remaining=remaining-length
            if remaining<=0.1 then break end
        end
        start=finish
    end
    return false
end
function A.collectorCustomDoorStep(root)
    local gui=A.player.PlayerGui:FindFirstChild("InteractGUI")
    local box=gui and gui.Enabled and gui.Adornee
    if not box or not box:IsA("BasePart")or (box.Position-root.Position).Magnitude>6 then return false end
    local door=false;local ancestor=box.Parent
    for _=1,4 do
        if not ancestor or ancestor==workspace then break end
        if ancestor.Name:lower():find("door",1,true)then door=true;break end
        ancestor=ancestor.Parent
    end
    if not door or not A.collectorDoorBlocksRoute(box,root)then return false end
    local useName=box:FindFirstChild("UseName")
    local name=useName and tostring(useName.Value):lower()or ""
    if name:find("close",1,true)then return false end
    if A.collectorDoorClosed(box)==false then return false end
    local remote=box:FindFirstChild("Interact")
    if not remote or not remote:IsA("RemoteEvent")then return false end
    A.customDoorNext=A.customDoorNext or setmetatable({},{__mode="k"})
    A.customDoorAttempts=A.customDoorAttempts or setmetatable({},{__mode="k"})
    local attempt=A.customDoorAttempts[box]
    if attempt and(root.Position-attempt.origin).Magnitude<8 then return false end
    if os.clock()<(A.customDoorNext[box]or 0)then return false end
    local disabled=box:FindFirstChild("IsDisabled");local used=box:FindFirstChild("InUse")
    if(disabled and disabled.Value)or(used and used.Value)then return false end
    local required=box:FindFirstChild("KeyRequired")
    if required then
        local kind=required:FindFirstChild("KeyType");local color=required:FindFirstChild("KeyColor")
        local key=kind and A.player.Character:FindFirstChild(kind.Value)
        if not key and kind then
            local backpack=A.player:FindFirstChildOfClass("Backpack")
            key=backpack and backpack:FindFirstChild(kind.Value)
            local _,humanoid=A.body(A.player)
            if key and humanoid and key:IsA("Tool")then humanoid:EquipTool(key)end
        end
        local keyColor=key and key:FindFirstChild("KeyColor")
        if not keyColor or not color or keyColor.Value~=color.Value then
            A.customDoorNext[box]=os.clock()+5
            A.log("door_locked",{door=box,key=kind and kind.Value,color=color and color.Value})
            local move=A.movement
            if move and move.target then A.skipCollectorTarget(move,move.target,"Door needs a key; choosing another route",8)end
            return true
        end
    end
    A.customDoorNext[box]=os.clock()+3
    A.customDoorAttempts[box]={origin=root.Position,at=os.clock()}
    local ok,err=pcall(function()
        remote:FireServer()
        local client=box:FindFirstChild("InteractClient")
        if client and client:IsA("BindableEvent")then client:Fire()end
    end)
    A.log("custom_door_interaction",{door=box,key="F",action=name,ok=ok,error=err})
    if ok then
        local move=A.movement
        if move and move.owner=="farm"then
            A.clearWalkRoute(move);move.recoveryGoal=nil;move.coastUntil=nil
            move.doorWaitingUntil=os.clock()+0.6;move.replan=true;move.nextPlanAt=0
            move.humanoid:Move(Vector3.zero,false)
        end
        A.note("Collector","Opening the door")
    end
    return ok
end

function A.collectorDoorStep(root)
    if A.collectorCustomDoorStep(root)then return end
    if not A.collectorPrompts then
        A.collectorPrompts={};A.collectorDoorCooldown=setmetatable({},{__mode="k"})
        for _,obj in ipairs(workspace:GetDescendants())do
            if obj:IsA("ProximityPrompt")then table.insert(A.collectorPrompts,obj)end
        end
        A.connect(workspace.DescendantAdded,function(obj)
            if obj:IsA("ProximityPrompt")then table.insert(A.collectorPrompts,obj)end
        end)
    end
    if os.clock()<(A.nextDoorCheck or 0)then return end
    A.nextDoorCheck=os.clock()+0.2
    for i=#A.collectorPrompts,1,-1 do
        local prompt=A.collectorPrompts[i]
        if not prompt.Parent then table.remove(A.collectorPrompts,i)
        elseif prompt.Enabled and prompt.KeyboardKeyCode==Enum.KeyCode.F
            and (A.collectorDoorCooldown[prompt] or 0)<os.clock() then
            local name=(prompt.ObjectText.." "..prompt.ActionText):lower()
            local parent=prompt.Parent
            local ancestor=parent
            for _=1,4 do if not ancestor then break end;name=name.." "..ancestor.Name:lower();ancestor=ancestor.Parent end
            local action=prompt.ActionText:lower()
            if name:find("door",1,true) and A.collectorDoorClosed(prompt)~=false and action:find("open",1,true) and not action:find("close",1,true)
                and not action:find("lock",1,true) then
                local position=parent:IsA("Attachment") and parent.WorldPosition
                    or parent:IsA("BasePart") and parent.Position
                    or parent:IsA("Model") and parent:GetPivot().Position
                if position and (position-root.Position).Magnitude<=math.min(prompt.MaxActivationDistance,10)
                    and A.collectorDoorBlocksRoute(prompt,root)then
                    A.collectorDoorCooldown[prompt]=os.clock()+3
                    A.log("door_interaction",{prompt=prompt,key="F",hold=prompt.HoldDuration})
                    local ok=pcall(function()prompt:InputHoldBegin()end)
                    if ok then
                        A.delay(math.max(0.05,prompt.HoldDuration+0.05),function()
                            pcall(function()prompt:InputHoldEnd()end)
                            if A.movement and A.movement.owner=="farm"then A.movement.replan=true;A.movement.nextPlanAt=0 end
                        end)
                    end
                    return
                end
            end
        end
    end
end

function A.collectorStableDirection(move,direction)
    local now=os.clock();local old=move.stableHeading
    if old and old.target==move.target and old.index==move.pathIndex and now-old.at<0.3
        and direction.Magnitude>0.1 and old.direction:Dot(direction)<-0.25
        and A.collectorBodyClear(move,old.direction,1.2)
        and A.collectorSegmentSafe(move.root.Position,move.root.Position+old.direction*2)then return old.direction end
    if direction.Magnitude>0.1 then move.stableHeading={direction=direction.Unit,at=now,target=move.target,index=move.pathIndex}end
    return direction
end
function A.collectorTryOpening(move,target)
    if not target or not target.Parent then return false end
    local delta=target.Position-move.root.Position;local flat=Vector3.new(delta.X,0,delta.Z)
    if flat.Magnitude<1 then return false end
    if not A.collectorSmallObstacleStep(move,flat.Unit)then return false end
    local direction=move.airDirection
    A.clearWalkRoute(move,true)
    move.airDirection=direction;move.walkDirection=direction;move.jumpPending=true
    move.replan=true;move.nextPlanAt=os.clock()+0.8
    A.log("opening_jump_fallback",{position=move.root.Position,target=target})
    return true
end
function A.collectorStopAtRoundEnd()
    A.collectorRoundEnded=true;A.collectorEndedMap=A.collectContainer
    A.collectorActiveRound=false
    A.stopCollectorCombat();A.clearCollectorThreats()
    if A.movement and A.movement.owner=="farm"then A.releaseMove(false)end
    local _,h=A.body(A.player)
    if h then h.Jump=false;h:Move(Vector3.zero,false)end
    A.log("round_end_movement_stopped",{})
end
function A.collectorInstallRoundStop()
    if A.collectorRoundStopInstalled then return end
    local remotes=A.RS:FindFirstChild("Remotes")
    local gameplay=remotes and remotes:FindFirstChild("Gameplay")
    if not gameplay then return end
    A.collectorRoundStopInstalled=true
    for _,name in ipairs({"VictoryScreen","RoundEndFade"})do
        local event=gameplay:FindFirstChild(name)
        if event and event:IsA("RemoteEvent")then A.connect(event.OnClientEvent,function()A.collectorStopAtRoundEnd()end)end
    end
    local start=gameplay:FindFirstChild("RoundStart")
    if start and start:IsA("RemoteEvent")then A.connect(start.OnClientEvent,function()
        A.collectorRoundEnded=false;A.collectorEndedMap=nil
    end)end
end
function A.collectorMapReady()
    if A.collectorRoundEnded then return false end
    local _,humanoid,root=A.body(A.player)
    if not humanoid or humanoid.Health<=0 or not root then return false end
    -- Round role records can remain alive after returning to the lobby.
    -- Countdown role records may still say dead from the previous round.
    -- Use the active map's bounds, never the lobby or stale role data.
    A.coins()
    local map=A.collectContainer
    while map and map.Parent~=workspace do map=map.Parent end
    if not map or not map:IsA("Model") or map.Name:lower():find("lobby",1,true) then return false end
    local bounds=A.collectorMapBounds
    if not bounds or bounds.map~=map or os.clock()-bounds.at>0.5 then
        local ok,frame,size=pcall(function()return map:GetBoundingBox()end)
        if not ok then return false end
        bounds={map=map,frame=frame,size=size,at=os.clock()};A.collectorMapBounds=bounds
    end
    local frame,size=bounds.frame,bounds.size
    local localPosition=frame:PointToObjectSpace(root.Position)
    return math.abs(localPosition.X)<=size.X/2+5 and math.abs(localPosition.Y)<=size.Y/2+5
        and math.abs(localPosition.Z)<=size.Z/2+5
end

function A.collectorEncounterReady(player,near,now)
    local latch=A.collectorTeleportEncounters and A.collectorTeleportEncounters[player]
    if not latch then return true end
    if near then latch.outsideAt=nil;return false end
    latch.outsideAt=latch.outsideAt or now
    if now-latch.outsideAt>=1.5 then A.collectorTeleportEncounters[player]=nil;return true end
    return false
end

function A.collectorDangerDistance()
    return 20
end
function A.collectorEmergencyThreat(root)
    if A.isZombie(A.player)then return nil end
    for _,threat in ipairs(A.collectorThreats)do
        if not threat.provisional and threat.player then
            local _,_,enemy=A.body(threat.player)
            if enemy then
                local offset=root.Position-enemy.Position
                local flat=Vector3.new(offset.X,0,offset.Z)
                if flat.Magnitude<=A.collectorDangerDistance() and math.abs(offset.Y)<=10
                    and A.collectorThreatRelevant(root.Position,threat)then
                    A.lastEmergencyDistance=flat.Magnitude
                    return threat
                end
            end
        end
    end
end
function A.collectorEmergencyTeleport(root)
    if os.clock()<(A.nextCollectorTeleport or 0)then return false end
    A.updateCollectorThreats()
    local threat=A.collectorEmergencyThreat(root)
    if not threat then return false end
    return A.collectorTeleportToFarCandy(root,threat)
end
function A.collectorTeleportRouteDistance(origin,goal)
    local path=game:GetService("PathfindingService"):CreatePath({AgentRadius=1.25,AgentHeight=5,
        AgentCanJump=true,AgentCanClimb=true,WaypointSpacing=4})
    A.resources[path]=true
    local distance
    pcall(function()
        path:ComputeAsync(origin,goal)
        if path.Status~=Enum.PathStatus.Success then return end
        local points=path:GetWaypoints();local last=points[#points]
        if not last or(last.Position-goal).Magnitude>3 or math.abs(last.Position.Y-goal.Y)>1.8 then return end
        if not points[1]or math.abs(points[1].Position.Y-(origin.Y-3))>4 then return end
        distance=0
        for i=2,#points do distance=distance+(points[i].Position-points[i-1].Position).Magnitude end
    end)
    A.resources[path]=nil;path:Destroy()
    return distance
end
function A.collectorRefreshTeleportRoutes(supplied)
    if not A.collectorMapReady()then return end
    local character=A.player.Character
    local now=os.clock()
    if A.teleportRoutesPlanning or now<(A.nextTeleportRouteRefresh or 0)then return end
    if A.isZombie(A.player)or A.role(A.player)=="Murderer"then return end
    A.updateCollectorThreats()
    local threat=supplied
    if not threat then for _,t in ipairs(A.collectorThreats)do if not t.provisional then threat=t;break end end end
    if not threat then return end
    local origin=threat.current or threat.position
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
    local ignore={A.player.Character}
    if threat.player and threat.player.Character then ignore[#ignore+1]=threat.player.Character end
    params.FilterDescendantsInstances=ignore
    local ground=workspace:Raycast(origin+Vector3.new(0,2,0),Vector3.new(0,-64,0),params)
    local navOrigin=ground and ground.Normal.Y>0.6 and Vector3.new(origin.X,ground.Position.Y+3,origin.Z)or origin
    local map=A.collectContainer;while map and map.Parent~=workspace do map=map.Parent end
    local cache={origin=origin,map=map,player=threat.player,at=now,scores={}}
    local candidates={}
    for _,part in ipairs(A.coinCache)do if A.coinActive(part)and A.finite(part.Position)then candidates[#candidates+1]=part end end
    if #candidates==0 then return end
    A.teleportRoutesPlanning=true;A.nextTeleportRouteRefresh=now+0.75
    A.teleportRouteBuilding=cache
    A.spawn(function()
        local index=0;local pending=0
        for _=1,math.min(6,#candidates)do
            pending=pending+1
            task.spawn(function()
                local ok,err=pcall(function()
                    while A.alive and A.config.farm and A.teleportRouteBuilding==cache
                        and A.player.Character==character and A.collectorMapReady()do
                        index=index+1;local part=candidates[index];if not part then break end
                        if A.coinActive(part)then
                            local distance=A.collectorTeleportRouteDistance(navOrigin,part.Position)
                            if distance then cache.scores[part]=distance end
                        end
                    end
                end)
                if not ok then A.log("teleport_route_error",{error=tostring(err)})end
                pending=pending-1
            end)
        end
        while pending>0 do task.wait()end
        if A.player.Character~=character or not A.collectorMapReady()then
            A.teleportRoutesPlanning=false
            if A.teleportRouteBuilding==cache then A.teleportRouteBuilding=nil end
            A.log("teleport_routes_cancelled",{reason="round_character_inactive"})
            return
        end
        local count=0;for _ in pairs(cache.scores)do count=count+1 end
        cache.complete=true
        if count>0 then A.teleportRouteCache=cache end
        A.teleportRoutesPlanning=false
        A.log("teleport_routes_ready",{candidates=#candidates,reachable=count,duration=os.clock()-now,origin=origin})
    end)
end
function A.collectorTeleportLanding(candy,humanoid,root)
    if not candy or not candy.Parent or not humanoid or not root then return nil end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={A.player.Character,candy};params.RespectCanCollide=true
    local floor=workspace:Raycast(candy.Position+Vector3.new(0,3,0),Vector3.new(0,-9,0),params)
    if not floor or floor.Normal.Y<0.65 or floor.Position.Y<=workspace.FallenPartsDestroyHeight+3 then return nil end
    local height=humanoid.HipHeight+root.Size.Y/2
    if humanoid.RigType==Enum.HumanoidRigType.R6 then
        local leg=root.Parent and(root.Parent:FindFirstChild("Left Leg")or root.Parent:FindFirstChild("Right Leg"))
        if leg and leg:IsA("BasePart")then height=height+leg.Size.Y end
    end
    local destination=Vector3.new(candy.Position.X,floor.Position.Y+height+0.1,candy.Position.Z)
    if not A.finite(destination)then return nil end
    return destination
end
function A.collectorTeleportRouteChoice(threat,map)
    local cache=A.teleportRouteCache
    if not cache or not cache.complete or cache.map~=map or cache.player~=threat.player or os.clock()-cache.at>4
        or(cache.origin-(threat.current or threat.position)).Magnitude>48 then return nil end
    local _,humanoid,root=A.body(A.player)
    local best,distance,destination=nil,-1,nil
    for part,routeDistance in pairs(cache.scores)do
        if A.coinActive(part)and routeDistance>distance then
            local landing=A.collectorTeleportLanding(part,humanoid,root)
            if landing then best,distance,destination=part,routeDistance,landing end
        end
    end
    return best,distance,destination
end

function A.collectorTeleportToFarCandy(root,threat)
    if A.collectorFullCombatPriority()then return false end
    if not A.collectorPositionReady()or(A.movement and A.movement.owner~="farm")then return false end
    local state=getgenv().QOS_MM2_TP_STATE
    if not state then state={};getgenv().QOS_MM2_TP_STATE=state end
    local map=A.collectContainer
    while map and map.Parent~=workspace do map=map.Parent end
    if A.collectorTeleportBlocked(state)or os.clock()<(state.nextAt or 0)then
        if os.clock()>=(A.nextTeleportBlockLog or 0)then
            A.nextTeleportBlockLog=os.clock()+2
            A.log("teleport_blocked",{reason=state.blocked and "server correction"or "cooldown"})
        end
        return false
    end
    if os.clock()<(A.nextCollectorTeleport or 0)then return false end
    A.collectorRefreshTeleportRoutes(threat)
    local candy,routeDistance,destination=A.collectorTeleportRouteChoice(threat,map)
    if not candy then return false end
    local _,humanoid=A.body(A.player)
    if not humanoid then return false end
    if not destination then return false end
    local transaction=A.collectorPositionBegin("escape")
    if not transaction then return false end
    local move=A.movement
    if move and move.owner=="farm"then
        A.clearWalkRoute(move);move.target=nil;move.recoveryGoal=nil;move.coastUntil=nil
        move.nextPlanAt=0;move.lastProgressPosition=destination;move.lastProgressAt=os.clock()
    end
    -- Latch before the single position assignment.
    if threat.player then
        A.collectorTeleportEncounters=A.collectorTeleportEncounters or setmetatable({},{__mode="k"})
        A.collectorTeleportEncounters[threat.player]={}
    end
    state.nextAt=os.clock()+60;state.usedMap=map
    A.nextCollectorTeleport=state.nextAt
    A.log("teleport",{origin=root.Position,destination=destination,threat=threat.player and threat.player.Name,cooldown=60,routeDistance=routeDistance,metric="murderer path length",triggerDistance=A.lastEmergencyDistance})
    root.CFrame=CFrame.new(destination)*root.CFrame.Rotation
    root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero
    A.collectorDefensiveUntil=nil;A.collectorDefensiveTarget=nil
    if A.collectorCollectingCoins()and not A.collectorShootWhileCollecting then
        A.collectorCombatRole=nil;A.collectorCombatTarget=nil;A.collectorCombatWeapon=nil
        A.collectorFirstPerson(false)
    end
    A.collectorPositionFinish(transaction)
    A.nextCollectorTeleport=state.nextAt;A.lastCollectorTeleport=os.clock();A.collectorWatch=nil
    A.delay(0.5,function()
        if root.Parent and root:IsDescendantOf(workspace)and A.player.Character==root.Parent and humanoid.Health>0
            and A.collectorMapReady()and(root.Position-destination).Magnitude>25 then
            state.blocked=true;state.blockedUntil=os.clock()+60
            state.nextAt=math.max(state.nextAt or 0,state.blockedUntil)
            A.log("teleport_server_correction",{requested=destination,actual=root.Position})
            A.note("Collector","Teleport blocked")
        end
    end)
    A.note("Collector","Teleporting away")
    return true
end

function A.collectorKnifeImpact(position,velocity,rootPosition,rootVelocity)
    if Vector3.new(velocity.X,0,velocity.Z).Magnitude<25 then return false end
    local relative=position-rootPosition
    local travel=velocity-rootVelocity
    if travel.Magnitude<25 then return false end
    local time=-relative:Dot(travel)/travel:Dot(travel)
    return time>=0 and time<=1 and (relative+travel*time).Magnitude<=5.5,time
end
function A.collectorCharacterPart(part)
    local ancestor=part
    while ancestor and ancestor~=workspace do
        if ancestor:IsA("Model")and(ancestor:FindFirstChildOfClass("Humanoid")
            or ancestor:FindFirstChild("HumanoidRootPart"))then return true end
        ancestor=ancestor.Parent
    end
    return false
end
function A.collectorDodgeKnife(root,velocity,timeToImpact,projectilePosition)
    local move=A.movement
    if not move or move.owner~="farm"then
        if not A.acquireMove("farm")then return false end
        move=A.movement;move.walking=true;move.walkSpeed=move.humanoid.WalkSpeed
    end
    local now=os.clock()
    if now<(move.knifeDodgeUntil or 0)and move.recoveryGoal then
        local delta=move.recoveryGoal-root.Position
        local direction=Vector3.new(delta.X,0,delta.Z)
        if direction.Magnitude>0.1 and A.collectorRecoveryClear(move,move.recoveryGoal)
            and A.collectorSegmentSafe(root.Position,move.recoveryGoal)then
            move.walkDirection=direction.Unit;move.airDirection=direction.Unit
            move.humanoid:Move(direction.Unit,false)
            return true
        end
    end
    local flat=Vector3.new(velocity.X,0,velocity.Z)
    if flat.Magnitude<1 then return false end
    local side=Vector3.new(-flat.Z,0,flat.X).Unit
    if projectilePosition and(root.Position-projectilePosition):Dot(side)<0 then side=-side end
    local distance=math.clamp(16*timeToImpact,3,6)
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    for _,direction in ipairs({side,-side})do
        local goal=root.Position+direction*distance
        if A.collectorBodyClear(move,direction,distance)and A.collectorRecoveryClear(move,goal)
            and A.collectorSegmentSafe(root.Position,goal)then
            local depth=math.clamp(goal.Y-workspace.FallenPartsDestroyHeight-3,7,15000)
            local floor=workspace:Raycast(goal,Vector3.new(0,-depth,0),params)
            if floor and floor.Normal.Y>=0.65 and floor.Position.Y>workspace.FallenPartsDestroyHeight+3 then
                A.clearWalkRoute(move,true)
                move.recoveryGoal=goal;move.recoveryUntil=now+distance/16+0.15
                move.knifeDodgeUntil=move.recoveryUntil
                move.walkDirection=direction;move.airDirection=direction
                move.humanoid:Move(direction,false)
                A.log("knife_dodge",{origin=root.Position,goal=goal,timeToImpact=timeToImpact})
                return true
            end
        end
    end
    return false
end

function A.collectorKnifeEscape(root)
    if A.isZombie(A.player)then return false end
    if not A.collectorKnives then
        A.collectorKnives={}
        A.collectorEscapedKnives=setmetatable({},{__mode="k"})
        local function add(part)
            if not part:IsA("BasePart")or A.collectorKnives[part]or A.collectorCharacterPart(part)then return end
            local ancestor=part;local knife=false
            for _=1,5 do
                if not ancestor or ancestor==workspace then break end
                local name=ancestor.Name:lower()
                if name:find("display",1,true)or name:find("decoration",1,true)or name=="lobby"or name:find("coin",1,true)or name:find("candy",1,true)or ancestor:IsA("Tool")then return end
                if name:find("knife",1,true)then knife=true end
                ancestor=ancestor.Parent
            end
            local generic=false
            if not knife and part.Size.Magnitude<=12 then
                local held=false
                for _,player in ipairs(A.playerList)do
                    if player.Character and part:IsDescendantOf(player.Character)then held=true;break end
                end
                if not held then
                    for _,threat in ipairs(A.collectorThreats)do
                        if not threat.provisional and (part.Position-(threat.current or threat.position)).Magnitude<=18 then generic=true;break end
                    end
                end
            end
            if knife or generic then
                A.collectorKnives[part]={position=part.Position,at=os.clock(),bornAt=os.clock(),generic=generic}
                A.log("projectile_tracked",{part=part,position=part.Position,generic=generic})
            end
        end
        for _,part in ipairs(workspace:GetDescendants())do add(part)end
        A.connect(workspace.DescendantAdded,function(part)
            add(part)
            if part:IsA("BasePart")then A.delay(0.05,function()if part.Parent then add(part)end end)end
        end)
    end
    for part,sample in pairs(A.collectorKnives)do
        if not part.Parent or A.collectorCharacterPart(part)or (sample.generic and os.clock()-sample.bornAt>4)then A.collectorKnives[part]=nil
        else
            local now=os.clock();local elapsed=now-sample.at
            local velocity=part.AssemblyLinearVelocity
            if elapsed>0.005 then
                local measured=(part.Position-sample.position)/elapsed
                if measured.Magnitude>velocity.Magnitude then velocity=measured end
                sample.position=part.Position;sample.at=now
            end
            local held=false
            for _,player in ipairs(A.playerList)do if player.Character and part:IsDescendantOf(player.Character)then held=true;break end end
            if not held and not A.collectorEscapedKnives[part] and A.finite(velocity) and velocity.Magnitude<600 then
                local impact,time=A.collectorKnifeImpact(part.Position,velocity,root.Position,root.AssemblyLinearVelocity)
                if impact then
                    if not sample.loggedImpact then sample.loggedImpact=true;A.log("incoming_knife",{part=part,position=part.Position,velocity=velocity,timeToImpact=time})end
                    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
                    params.FilterDescendantsInstances={A.player.Character,part}
                    if not workspace:Raycast(part.Position,velocity*time,params)then
                        local nearest,distance=nil,math.huge
                        for _,threat in ipairs(A.collectorThreats)do
                            local d=(part.Position-(threat.current or threat.position)).Magnitude
                            if d<distance then nearest,distance=threat,d end
                        end
                        if nearest and nearest.player and not nearest.provisional then
                            A.collectorIncomingAttacker=nearest.player;A.collectorIncomingUntil=os.clock()+2.5
                        end
                        if A.collectorTeleportToFarCandy(root,nearest or {position=part.Position,current=part.Position})then
                            A.collectorEscapedKnives[part]=true
                            A.note("Collector","Dodged a knife")
                            return true
                        elseif A.collectorDodgeKnife(root,velocity,time,part.Position)then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

function A.collectorBagFull()
    local gui=A.player:FindFirstChildOfClass("PlayerGui")
    local bags=gui and gui:FindFirstChild("CoinBags",true)
    local container=bags and bags:FindFirstChild("Container")
    if not container then return false end
    for _,bag in ipairs(container:GetChildren())do
        if bag:IsA("GuiObject")and bag.Visible then
            local full=bag:FindFirstChild("Full")
            local icon=bag:FindFirstChild("FullBagIcon")
            if (full and full:IsA("GuiObject")and full.Visible)or(icon and icon:IsA("GuiObject")and icon.Visible)then return true end
        end
    end
    return false
end
function A.collectorFullCombatPriority()
    local character=A.player.Character
    if not character or not A.config.farm or not A.collectorActiveRound then return false end
    if A.collectorFullLife~=character then
        if not A.collectorBagFull()then return false end
        A.collectorFullLife=character
        A.log("bag_full",{role=A.role(A.player),priority="combat_when_armed"})
        A.set("autoGun",true)
    end
    -- A full unarmed bag still needs avoidance while waiting for a gun.
    return A.findTool(A.player,"Gun")~=nil or(A.role(A.player)=="Murderer"and A.findTool(A.player,"Knife")~=nil)
end
function A.stopCollectorCombat()
    if A.collectorCombatRole then A.log("combat_stop",{role=A.collectorCombatRole})end
    A.collectorFirstPerson(false)
    A.collectorCombatRole=nil;A.collectorCombatTarget=nil;A.collectorCombatWeapon=nil
    A.gunReadySince=nil;A.gunReadyCharacter=nil
    A.collectorDefensiveTarget=nil;A.collectorDefensiveUntil=nil;A.collectorShootWhileCollecting=false
    if not(A.config.farm and A.collectorActiveRound and A.collectorFullLife==A.player.Character)then A.collectorFullLife=nil end
    A.collectorCombatPoint=nil
    if not A.config.silentGunAim then A.releaseWeaponHooks()end
end
function A.collectorCombatVisible(origin,point,character)
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
    params.FilterDescendantsInstances={A.player.Character}
    local hit=workspace:Raycast(origin,point-origin,params)
    return not hit or hit.Instance:IsDescendantOf(character)
end
function A.collectorCombatAim(original,caller)
    -- Gun shots use the existing silent-aim path in ensureWeaponHooks.
    if A.collectorCombatRole=="Sheriff"then return original,false end
    local target=A.collectorCombatTarget;local weapon=A.collectorCombatWeapon
    if not A.config.farm or not A.collectorCombatRole or not target or not weapon then return original end
    if type(caller)~="function"then return original end
    local ok,environment=pcall(getfenv,caller)
    local calling=ok and rawget(environment,"script")
    if not calling or not calling:IsDescendantOf(weapon)then
        if os.clock()>=(A.nextAimCallerLog or 0)then
            A.nextAimCallerLog=os.clock()+1;A.log("combat_aim_caller_rejected",{caller=calling,weapon=weapon})
        end
        return original
    end
    local character,humanoid,root=A.body(target)
    if not root then return original end
    local part=character:FindFirstChild("UpperTorso")or character:FindFirstChild("Torso")or root
    local velocity=root.AssemblyLinearVelocity
    if not A.finite(velocity)or velocity.Magnitude>100 then velocity=Vector3.zero end
    local point=part.Position+velocity*math.clamp(A.config.prediction or 0,0,0.2)
    local handle=weapon:FindFirstChild("Handle")
    local _,_,own=A.body(A.player)
    local origin=handle and handle:IsA("BasePart")and handle.Position or own and own.Position
    if A.collectorCombatRole=="Sheriff"then origin=A.gunOrigin()or origin end
    if not origin or not A.collectorCombatVisible(origin,point,character)then return original end
    if os.clock()>=(A.nextCombatAimLog or 0)then
        A.nextCombatAimLog=os.clock()+0.2
        A.log("combat_aim_applied",{target=target.Name,origin=origin,point=point,velocity=velocity,prediction=A.config.prediction,type=typeof(original)})
    end
    if typeof(original)=="CFrame"then return CFrame.new(point)*original.Rotation,true end
    if typeof(original)=="Vector3"then return point,true end
    return original
end
function A.collectorGunWatching()
    local ownCharacter,_,own=A.body(A.player)
    if not own then A.collectorWatchMemory=nil;return false end
    local now=os.clock()
    local memory=A.collectorWatchMemory
    if not memory or memory.character~=ownCharacter then memory={character=ownCharacter,players={}};A.collectorWatchMemory=memory end
    local watched=false
    for _,player in ipairs(A.playerList)do
        if player~=A.player and A.espAlive(player)and A.findTool(player,"Gun")then
            local character,_,root=A.body(player)
            local head=character and character:FindFirstChild("Head")
            local eye=head or root
            if eye then
                local delta=own.Position-eye.Position
                local aiming=delta.Magnitude>0.1 and delta.Magnitude<=100 and
                    (eye.CFrame.LookVector:Dot(delta.Unit)>=0.7 or root and root.CFrame.LookVector:Dot(delta.Unit)>=0.7)
                if aiming then
                    local ownHead=ownCharacter:FindFirstChild("Head")
                    local side=own.CFrame.RightVector*0.8
                    local points={own.Position,ownHead and ownHead.Position or own.Position+Vector3.new(0,1.5,0),own.Position+side,own.Position-side}
                    local visible=false
                    for _,point in ipairs(points)do
                        if A.collectorCombatVisible(eye.Position,point,ownCharacter)then visible=true;break end
                    end
                    local previous=memory.players[player]
                    if visible then memory.players[player]={character=character,time=now} end
                    if visible or previous and previous.character==character and now-previous.time<=0.6 then watched=true end
                else memory.players[player]=nil end
            else memory.players[player]=nil end
        else memory.players[player]=nil end
    end
    if memory.watched~=watched then
        memory.watched=watched
        A.log("gun_watch_changed",{watching=watched,role=A.role(A.player),full=A.collectorFullLife==ownCharacter})
    end
    return watched
end
function A.collectorHoldJump()
    return A.config.farm and A.collectorActiveRound and
        (not A.isZombie(A.player) and A.role(A.player)=="Murderer" and A.collectorCombatRole=="Murderer"and A.collectorFullLife==A.player.Character and A.collectorGunWatching())
end
function A.collectorCombatJump(humanoid)
    if A.collectorHoldJump()then
        humanoid.Jump=true
        A.collectorJumpHeld=humanoid
        local move=A.movement
        if move and move.owner=="farm"and move.root then
            local direction=move.walkDirection
            if not direction or direction.Magnitude<0.1 then direction=move.airDirection end
            if not direction or direction.Magnitude<0.1 then direction=move.root.CFrame.LookVector end
            direction=Vector3.new(direction.X,0,direction.Z)
            if direction.Magnitude>0.1 then
                local dodge=A.collectorDodgeDirection(move,direction.Unit)
                move.airDirection=dodge
                humanoid:Move(dodge,false)
            end
        end
    elseif A.collectorJumpHeld then
        A.collectorJumpHeld.Jump=false;A.collectorJumpHeld=nil
    end
end

function A.collectorGunClearance(weapon,character,point,origin)
    origin=A.gunOrigin()or origin
    if not origin then return false end
    local delta=point-origin
    if delta.Magnitude<0.01 then return false end
    local ignore={A.player.Character,character}
    local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Exclude
    overlap.FilterDescendantsInstances=ignore;overlap.RespectCanCollide=true
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances=ignore;params.RespectCanCollide=true
    local _,_,root=A.body(A.player)
    local head=A.player.Character and A.player.Character:FindFirstChild("Head")
    local positions={origin}
    for _,position in ipairs(positions)do
        local touching=workspace:GetPartBoundsInRadius(position,0.45,overlap)
        local rootHit=root and workspace:Raycast(root.Position,position-root.Position,params)
        local headHit=head and workspace:Raycast(head.Position,position-head.Position,params)
        local forwardHit=workspace:Raycast(position,delta.Unit*1.5,params)
        if #touching>0
            or rootHit
            or headHit
            or forwardHit then
            if os.clock()>=(A.nextMuzzleBlockedLog or 0)then
                A.nextMuzzleBlockedLog=os.clock()+1
                A.log("gun_muzzle_obstructed",{position=position,origin=origin,overlap=touching[1],rootHit=rootHit and rootHit.Instance,headHit=headHit and headHit.Instance,forwardHit=forwardHit and forwardHit.Instance})
            end
            return false
        end
    end
    return true
end
function A.collectorSilentLockReady(character)
    local sample=A.aimSample
    if not A.config.silentGunAim or A.aimBlocked~=false or not A.aimEligible or not sample
        or sample.character~=character or not sample.part or not sample.root or not sample.humanoid then return false end
    local age=os.clock()-sample.at
    return age>=0 and age<=0.1 and sample.humanoid.Health>0 and sample.part:IsDescendantOf(character)
end
function A.collectorGunShotReady(weapon,character,point,origin,clearance)
    if clearance==nil then clearance=A.collectorGunClearance(weapon,character,point,origin)end
    local now=os.clock()
    local defensive=(A.collectorDefensiveUntil or 0)>now
    local silent=A.config.silentGunAim
    local locked=A.collectorSilentLockReady(character)
    local reason
    if not clearance then reason="muzzle_obstructed"
    elseif weapon.Parent~=A.player.Character then reason="not_equipped"
    elseif not weapon.Enabled then reason="weapon_disabled"
    elseif now-(A.combatEquippedAt or -10)<=((defensive or locked)and 0.1 or 0.45)then reason="equip_delay"
    elseif character:FindFirstChildOfClass("ForceField")then reason="target_forcefield"end
    local camera=workspace.CurrentCamera
    if not reason and silent and not locked then reason="silent_aim_not_ready"end
    if not reason and not silent then
        local aligned,blocked=A.collectorCombatCameraReady(camera,point)
        if not aligned then reason=blocked end
    end
    if not reason and locked then
        if not A.weaponVisible(origin,A.aimSample.position,character)then reason="line_of_fire"end
    elseif not reason then
        for _,offset in ipairs({Vector3.zero,Vector3.new(0.35,0,0),Vector3.new(-0.35,0,0)})do
            if not A.collectorCombatVisible(origin,point+offset,character)then reason="line_of_fire";break end
        end
    end
    if reason or A.gunReadyCharacter~=character or not A.gunReadySince then
        A.gunReadyCharacter=character;A.gunReadySince=not reason and now or nil
    end
    local ready=not reason and now-(A.gunReadySince or now)>=(locked and 0 or(defensive and 0.06 or 0.25))
    A.gunShotBlockReason=reason or(not ready and "settling"or nil)
    if not ready and now>=(A.nextGunReadinessLog or 0)then
        A.nextGunReadinessLog=now+0.5
        A.log("gun_not_ready",{reason=A.gunShotBlockReason,target=character,defensive=defensive,aimTarget=A.aimPlayer and A.aimPlayer.Name,aimAge=A.aimSample and now-A.aimSample.at,aimBlocked=A.aimBlocked,aimEligible=A.aimEligible})
    end
    return ready
end
function A.collectorZombieNearbyAttack(root)
    if not A.isZombie(A.player)or os.clock()<(A.nextZombieNearbyAttack or 0)then return end
    local weapon=A.findTool(A.player,"Knife")
    if not weapon then return end
    for _,player in ipairs(A.playerList)do
        if player~=A.player and not A.isZombie(player)and A.espAlive(player)then
            local character,_,enemy=A.body(player)
            if enemy and(enemy.Position-root.Position).Magnitude<=5
                and A.collectorCombatVisible(root.Position,enemy.Position,character)then
                local _,h=A.body(A.player)
                if h and weapon.Parent~=A.player.Character then h:EquipTool(weapon)end
                A.nextZombieNearbyAttack=os.clock()+0.45
                local ok,err=pcall(function()weapon:Activate()end)
                A.log("zombie_nearby_attack",{target=player.Name,ok=ok,error=err})
                return
            end
        end
    end
end
function A.collectorMuzzleEscapeGoal(root,character,point,origin)
    local away=root.Position-point;away=Vector3.new(away.X,0,away.Z)
    if away.Magnitude<0.1 then return end
    away=away.Unit;local side=Vector3.new(-away.Z,0,away.X)
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={A.player.Character,character};params.RespectCanCollide=true
    local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Exclude
    overlap.FilterDescendantsInstances=params.FilterDescendantsInstances;overlap.RespectCanCollide=true
    local best,bestScore
    for _,distance in ipairs({2,3.5})do
        for _,direction in ipairs({away,side,-side,(away+side).Unit,(away-side).Unit})do
            local offset=direction*distance;local goal=root.Position+offset;local muzzle=origin+offset
            local ground=workspace:Raycast(goal,Vector3.new(0,-7,0),params)
            local delta=point-muzzle
            if ground and ground.Normal.Y>=0.65 and ground.Position.Y<goal.Y-1
                and not workspace:Blockcast(CFrame.new(root.Position),Vector3.new(1.8,3.4,1.8),offset,params)
                and #workspace:GetPartBoundsInRadius(muzzle,0.45,overlap)==0
                and not workspace:Raycast(goal,muzzle-goal,params)
                and delta.Magnitude>0.01 and not workspace:Raycast(muzzle,delta.Unit*1.5,params)then
                local score=(goal-point).Magnitude-distance*0.1
                if not bestScore or score>bestScore then best,bestScore=goal,score end
            end
        end
    end
    return best
end
function A.collectorMuzzleEscapeStep(move)
    if A.collectorRecoveryActive(move)then A.collectorMuzzleEscape=nil;return false end
    local escape=A.collectorMuzzleEscape
    if not escape then return false end
    if A.collectorCombatRole~="Sheriff"or os.clock()>escape.untilAt then A.collectorMuzzleEscape=nil;return false end
    local delta=escape.goal-move.root.Position;local flat=Vector3.new(delta.X,0,delta.Z)
    if flat.Magnitude<0.5 then A.collectorMuzzleEscape=nil;return false end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local direction=flat.Unit
    if A.collectorSmallObstacleStep(move,direction)then return true end
    if workspace:Blockcast(CFrame.new(move.root.Position),Vector3.new(1.8,3.4,1.8),direction*math.min(flat.Magnitude,0.8),params)then
        A.collectorMuzzleEscape=nil;return false
    end
    move.walkDirection=direction;move.humanoid:Move(direction,false)
    return true
end
function A.collectorRangedGoal(root,enemy,character,origin)
    local delta=root.Position-enemy.Position
    local away=Vector3.new(delta.X,0,delta.Z)
    if away.Magnitude<0.1 then away=Vector3.new(1,0,0)end
    away=away.Unit
    local side=Vector3.new(-away.Z,0,away.X)
    local distance=delta.Magnitude
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={A.player.Character,character};params.RespectCanCollide=true
    local point=(character:FindFirstChild('UpperTorso')or character:FindFirstChild('Torso')or enemy).Position
    local velocity=enemy.AssemblyLinearVelocity
    if not A.finite(velocity)or velocity.Magnitude>100 then velocity=Vector3.zero end
    local predicted=enemy.Position+Vector3.new(velocity.X,0,velocity.Z)*0.35
    local best,bestScore
    local previous=A.collectorRangedDirection
    for _,direction in ipairs({Vector3.zero,away,(away+side).Unit,(away-side).Unit,side,-side,(side-away).Unit,(-side-away).Unit,-away})do
        local offset=direction*6
        local goal=root.Position+offset
        local near=math.huge
        for _,t in ipairs({0,0.5,1})do near=math.min(near,(root.Position+offset*t-predicted).Magnitude)end
        local safe=near>=math.min((root.Position-predicted).Magnitude-0.5,38)
        if safe and not workspace:Blockcast(CFrame.new(root.Position),Vector3.new(1.8,3.4,1.8),offset,params)then
            local supported=true
            for _,t in ipairs({0.5,1})do
                local floor=workspace:Raycast(root.Position+offset*t,Vector3.new(0,-5,0),params)
                if not floor or floor.Normal.Y<0.65 then supported=false;break end
            end
            if supported then
                local los=A.collectorCombatVisible(origin+offset,point,character)
                local endDistance=(goal-predicted).Magnitude
                -- Safety outweighs visibility; only approach toward the preferred band.
                local score=-math.max(0,40-endDistance)*25-math.max(0,endDistance-46)*0.7+(los and 8 or 0)
                if previous and direction.Magnitude>0 then score=score+direction:Dot(previous)*1.5 end
                if direction.Magnitude==0 then score=score+0.5 end
                -- Hidden local spacing must not consume the route around a wall.
                -- Permit a hidden move only when it creates urgently needed distance.
                local useful=los or(distance<38 and endDistance>distance+0.5)
                if useful and(not bestScore or score>bestScore)then best,bestScore=goal,score end
            end
        end
    end
    return best
end
function A.collectorRecoveryActive(move)
    if not move or not move.recoveryGoal or os.clock()>=(move.recoveryUntil or 0)then return false end
    local delta=move.recoveryGoal-move.root.Position
    if Vector3.new(delta.X,0,delta.Z).Magnitude<0.7 then return false end
    return A.collectorSegmentSafe(move.root.Position,move.recoveryGoal)
end
function A.collectorRangedStep(move)
    if A.collectorRecoveryActive(move)then return false end
    if not A.config.farm or A.collectorCombatRole~='Sheriff' or A.isZombie(A.player)then return false end
    local weapon=A.collectorCombatWeapon
    if not weapon or weapon.Parent~=A.player.Character then return false end
    if not A.collectorCombatTarget then return false end
    local character,_,enemy=A.body(A.collectorCombatTarget)
    if not enemy then return false end
    local distance=(move.root.Position-enemy.Position).Magnitude
    -- Local firing spacing must not replace navigation across rooms or floors.
    if distance>56 or math.abs(move.root.Position.Y-enemy.Position.Y)>8 then return false end
    -- Do not interrupt ordinary coin gathering while the target is safely distant.
    if A.collectorCollectingCoins()and distance>36 then return false end
    local now=os.clock()
    local cache=A.collectorRangedCache
    if not cache or cache.target~=enemy or now>=cache.untilAt then
        local goal=A.collectorRangedGoal(move.root,enemy,character,A.gunOrigin()or move.root.Position)
        cache={target=enemy,goal=goal,untilAt=now+0.1};A.collectorRangedCache=cache
        if now>=(A.nextRangedLog or 0)then
            A.nextRangedLog=now+0.5;A.log('ranged_spacing',{distance=distance,goal=goal,target=A.collectorCombatTarget.Name})
        end
    end
    if not cache.goal then return false end
    local delta=cache.goal-move.root.Position;local flat=Vector3.new(delta.X,0,delta.Z)
    local direction=flat.Magnitude>0.5 and flat.Unit or Vector3.zero
    if direction.Magnitude==0 then
        local point=(character:FindFirstChild('UpperTorso')or character:FindFirstChild('Torso')or enemy).Position
        if not A.collectorCombatVisible(A.gunOrigin()or move.root.Position,point,character)then
            -- A stationary hidden firing position is not a completed engagement.
            -- Retain the route so the global planner can navigate around the obstruction.
            return false
        end
    end
    direction=A.collectorStableDirection(move,direction)
    if direction.Magnitude>0 then
        if A.collectorSmallObstacleStep(move,direction)then return true end
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
        if workspace:Blockcast(CFrame.new(move.root.Position),Vector3.new(1.8,3.4,1.8),direction*0.8,params)then A.collectorRangedCache=nil;return false end
        A.collectorRangedDirection=direction
    end
    A.clearWalkRoute(move,true);move.recoveryGoal=nil
    move.walkDirection=direction;move.smoothDirection=direction
    move.humanoid:Move(direction,false)
    return true
end
function A.collectorKnifeCanThrow(weapon,root,enemy,now)
    local delta=enemy.Position-root.Position
    if delta.Magnitude<=12 or now-(A.lastCollectorStab or -10)<0.9 then return false end
    local charge=weapon:GetAttribute("ThrowSpeed");charge=type(charge)=="number"and charge or 1
    local closing=math.max(0,(root.AssemblyLinearVelocity-enemy.AssemblyLinearVelocity):Dot(delta.Unit))
    return delta.Magnitude-closing*math.max(0.9,charge*2)>7
end
function A.collectorDodgeDirection(move,forward)
    if forward.Magnitude<0.1 or not A.collectorHoldJump()then move.dodgeState=nil;return forward end
    local target=A.collectorCombatTarget
    local _,_,enemy;if target then _,_,enemy=A.body(target)end
    if enemy and(enemy.Position-move.root.Position).Magnitude<=7 then return forward end
    forward=Vector3.new(forward.X,0,forward.Z).Unit
    local now=os.clock();local dodge=move.dodgeState
    if not dodge or now>=dodge.untilAt then
        dodge={side=dodge and -dodge.side or 1,untilAt=now+0.7+math.random()*0.35};move.dodgeState=dodge
    end
    local side=Vector3.new(-forward.Z,0,forward.X)
    for _,sign in ipairs({dodge.side,-dodge.side})do
        local direction=(forward+side*sign*0.65).Unit
        if A.collectorBodyClear(move,direction,2.5)
            and A.collectorSegmentSafe(move.root.Position,move.root.Position+direction*3)then
            local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
            local support=workspace:Raycast(move.root.Position+direction*3,Vector3.new(0,-14,0),params)
            if support and support.Normal.Y>0.65 and support.Position.Y>workspace.FallenPartsDestroyHeight+3 then
                dodge.side=sign;return direction
            end
        end
    end
    return forward
end
function A.collectorNativeThrow(weapon,action)
    assert(action and typeof(getconnections)=='function','Throw input unavailable')
    for _,connection in ipairs(getconnections(action.Pressed))do
        local callback=connection.Function
        if type(callback)=='function' and connection.Enabled~=false then
            local ok,env=pcall(getfenv,callback)
            local owner=ok and rawget(env,'script')
            if owner and owner:IsDescendantOf(weapon)then
                task.spawn(function()
                    local success,failure=pcall(callback)
                    A.log('throw_charge_callback_finished',{ok=success,error=not success and tostring(failure),weapon=weapon})
                end)
                return
            end
        end
    end
    error('Current equipped knife Throw listener unavailable')
end


function A.collectorRoleStep(root)
    local role=A.role(A.player)
    local zombie=A.isZombie(A.player)
    local defensive=(A.collectorDefensiveUntil or 0)>os.clock()and A.findTool(A.player,"Gun")
    if defensive then role="Gun holder"end
    if zombie then role="Murderer"end
    if A.collectorBagFull()and A.collectorFullLife~=A.player.Character then
        A.collectorFullLife=A.player.Character;A.log("bag_full",{role=role})
        A.set("autoGun",true)
    end
    A.collectorGunTarget=nil
    if A.collectorFullLife==A.player.Character and role~="Murderer"then
        if A.findTool(A.player,"Gun")then role="Gun holder"
        elseif A.config.autoGun then
            local drop=A.drop()
            A.note("Collector",drop and "Bag full. Getting the gun." or "Bag full. No gun yet.")
            if drop and not A.collectorGunPickupBusy and os.clock()>=(A.nextGunAttempt or 0)then
                if A.movement and A.movement.owner=="farm"then A.releaseMove(false)end
                A.collectorGunPickupBusy=true
                A.log("full_bag_gun_pickup",{drop=drop,position=root.Position})
                A.spawn(function()
                    local ok,err=pcall(A.grabGun)
                    A.collectorGunPickupBusy=false
                    if not ok then A.log("gun_pickup_error",{error=err});A.nextGunAttempt=os.clock()+2 end
                end)
            end
            return true
        end
    end
    if role~="Murderer"and role~="Sheriff"and role~="Hero"and role~="Gun holder"then
        if A.collectorCombatRole then A.stopCollectorCombat()end
        return false
    end
    if A.collectorBagFull()and not A.collectorFullLife then
        A.collectorFullLife=A.player.Character;A.log("bag_full",{role=role})
    end
    if A.collectorFullLife~=A.player.Character and not defensive then
        if zombie then A.collectorZombieNearbyAttack(root)end
        if A.collectorCombatRole then A.stopCollectorCombat()end
        return false
    end
    local mode=role=="Murderer"and "Murderer"or "Sheriff"
    if A.collectorCombatRole~=mode then A.log("combat_start",{role=mode});A.collectorCombatRole=mode end
    local _,humanoid=A.body(A.player)
    if not humanoid then return true end
    local chosen,distance,rank=nil,math.huge,math.huge
    local chosenArmed=false
    for _,player in ipairs(A.playerList)do
        if player~=A.player and(not A.collectorShootWhileCollecting or player==A.collectorDefensiveTarget)and(mode=="Murderer"or A.isAimTarget(player)or(defensive and player==A.collectorDefensiveTarget))
            and(not zombie or not A.isZombie(player))and(A.espAlive(player)or(defensive and player==A.collectorDefensiveTarget))then
            local _,_,enemy=A.body(player)
            if enemy and not A.collectorTargetCoolingDown(enemy)then
                local d=(enemy.Position-root.Position).Magnitude
                if zombie and d>12 then continue end
                local gun=A.findTool(player,"Gun")
                local targetRole=A.role(player)
                local armed=gun~=nil or targetRole=="Sheriff"or targetRole=="Hero"or targetRole=="Gun holder"or(player==A.collectorCombatTarget and A.collectorCombatTargetArmed==true)
                local priority=mode=="Murderer"and d*(armed and 0.8 or 1)or 1
                if mode=="Murderer"and player==A.collectorCombatTarget then priority=priority*0.9 end
                local locked=player==A.collectorCombatTarget
                local chosenLocked=chosen==A.collectorCombatTarget
                if priority<rank or(priority==rank and (locked or(not chosenLocked and d<distance)))then chosen,distance,rank=player,d,priority;chosenArmed=armed end
            end
        end
    end
    if A.collectorCombatTarget~=chosen then A.log("combat_target",{player=chosen and chosen.Name,distance=distance});A.collectorCombatTarget=chosen end
    A.collectorCombatTargetRank=chosen and rank or nil
    A.collectorCombatTargetArmed=chosen and chosenArmed or false
    A.collectorCombatJump(humanoid)
    if not chosen then
        if defensive then return false end
        if A.movement and A.movement.owner=="farm"then A.clearWalkRoute(A.movement)end
        A.note("Collector","No target");return true
    end
    local weapon=A.findTool(A.player,mode=="Murderer"and "Knife"or "Gun")
    if not weapon and zombie then A.collectorCombatWeapon=nil;A.note("Collector","Chasing");return false end
    if not weapon then A.note("Collector","No weapon");return true end
    A.collectorCombatWeapon=weapon
    if weapon.Parent~=A.player.Character then
        humanoid:EquipTool(weapon);A.combatEquippedAt=os.clock()
        A.log("weapon_equip",{weapon=weapon.Name})
    end
    if mode=="Sheriff"and not A.config.silentGunAim then A.set("silentGunAim",true)end
    A.ensureWeaponHooks()
    local character,_,enemy=A.body(chosen)
    if not enemy then return false end
    local point=(character:FindFirstChild("UpperTorso")or character:FindFirstChild("Torso")or enemy).Position
    local handle=weapon:FindFirstChild("Handle")
    local origin=handle and handle:IsA("BasePart")and handle.Position or root.Position
    if mode=="Sheriff"then origin=A.gunOrigin()or origin end
    if mode=="Sheriff"and A.config.silentGunAim then
        A.aimStep()
        if A.collectorSilentLockReady(character)then point=A.aimSample.position end
    end
    local visible
    if mode=="Sheriff"and A.collectorSilentLockReady(character)then visible=A.weaponVisible(origin,point,character)
    else visible=A.collectorCombatVisible(origin,point,character)end
    local now=os.clock()
    if not visible then A.gunReadySince=nil end
    local muzzleClear=mode~="Sheriff"or A.collectorGunClearance(weapon,character,point,origin)
    if mode=="Sheriff"and not muzzleClear and not A.collectorMuzzleEscape and not A.collectorRecoveryActive(A.movement)then
        local goal=A.collectorMuzzleEscapeGoal(root,character,point,origin)
        if goal then
            A.collectorMuzzleEscape={goal=goal,untilAt=now+0.5}
            A.log("gun_muzzle_step_clear",{goal=goal,origin=root.Position,target=chosen.Name})
        end
    elseif mode=="Sheriff"and muzzleClear then A.collectorMuzzleEscape=nil end
    if mode=="Sheriff"and visible and muzzleClear then A.collectorFirstPerson(true)end
    local shotReady=mode~="Sheriff"or(visible and A.collectorGunShotReady(weapon,character,point,origin,muzzleClear))
    if now-(A.combatEquippedAt or -10)>(defensive and 0.1 or 0.2)and weapon.Enabled and visible and muzzleClear then
        if mode=="Murderer"then
            if distance<=7 and now>=(A.nextCombatAttack or 0)then
                A.nextCombatAttack=now+0.86;A.lastCollectorStab=now
                local ok,err=pcall(function()weapon:Activate()end)
                A.log("stab_attempt",{player=chosen.Name,distance=distance,ok=ok,error=err})
            elseif not zombie and A.collectorKnifeCanThrow(weapon,root,enemy,now)and now>=(A.nextCombatThrow or 0)then
                local charge=weapon:GetAttribute("ThrowSpeed")
                A.nextCombatThrow=now+math.max(0.1,type(charge)=="number"and charge*2+0.05 or 2.05)
                local input=A.player.PlayerGui:FindFirstChild("InputContext")
                local context=input and input:FindFirstChild("GameplayContext")
                local action=context and context:FindFirstChild("Throw")
                local ok,err=pcall(function()
                    assert(weapon:GetAttribute("Disabled")~=true,"Knife disabled")
                    A.collectorNativeThrow(weapon,action)
                end)
                A.log("throw_attempt",{player=chosen.Name,distance=distance,visible=visible,ok=ok,error=err,path="GameplayContext.Throw.Pressed",charge=charge})
            end
        elseif now>=(A.nextCombatAttack or 0)and shotReady then
            A.nextCombatAttack=now+1.2
            local redirects=A.silentRedirects or 0
            local ok,err=pcall(function()weapon:Activate()end)
            A.log("gun_attempt",{player=chosen.Name,distance=distance,visible=visible,ok=ok,error=err,silentRedirected=(A.silentRedirects or 0)>redirects,silentTarget=A.aimPlayer and A.aimPlayer.Name})
        end
    elseif(not visible or not muzzleClear)and now>=(A.nextCombatBlockedLog or 0)then
        A.gunReadySince=nil
        A.nextCombatBlockedLog=now+1
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
        params.FilterDescendantsInstances={A.player.Character}
        local hit=workspace:Raycast(origin,point-origin,params)
        A.log("attack_blocked_by_wall",{player=chosen.Name,role=mode,visible=visible,muzzleClear=muzzleClear,origin=origin,point=point,blocker=hit and hit.Instance})
    end
    if mode=="Sheriff"then
        if not A.movement then A.acquireMove("farm")end
        local move=A.movement
        if move and move.owner=="farm"then
            if not move.walking then move.walking=true;move.walkSpeed=humanoid.WalkSpeed end
            if A.collectorRangedStep(move)then return true end
        end
    end
    return false
end

function A.collectorInfectionShotStep(root)
    A.collectorShootWhileCollecting=false
    if A.isZombie(A.player)or not A.findTool(A.player,"Gun")then return false end
    local origin=A.gunOrigin()or root.Position
    local chosen,distance=nil,math.huge
    for _,player in ipairs(A.playerList)do
        if player~=A.player and A.isZombie(player)and A.espAlive(player)then
            local character,_,enemy=A.body(player)
            if enemy then
                local point=(character:FindFirstChild("UpperTorso")or character:FindFirstChild("Torso")or enemy).Position
                local d=(enemy.Position-root.Position).Magnitude
                if d<distance and A.collectorCombatVisible(origin,point,character)then chosen,distance=player,d end
            end
        end
    end
    if not chosen then return false end
    A.collectorShootWhileCollecting=true
    A.collectorDefensiveTarget=chosen;A.collectorDefensiveUntil=os.clock()+0.8
    if os.clock()>=(A.nextCollectionShotLog or 0)then
        A.nextCollectionShotLog=os.clock()+1;A.log("collecting_zombie_target",{target=chosen.Name,distance=distance})
    end
    return true
end
function A.collectorDirectCandyHop(move)
    local now=os.clock()
    if now<(move.nextDirectHopProbe or 0)then return false end
    move.nextDirectHopProbe=now+0.15
    local target=move.target
    if not A.collectorCollectingCoins()or not A.collectContainer or not target or not target.Parent
        or not target:IsDescendantOf(A.collectContainer)or not A.coinActive(target)
        or move.recoveryGoal or move.jumpPending then return false end
    local delta=target.Position-move.root.Position
    local flat=Vector3.new(delta.X,0,delta.Z)
    local rise=target.Position.Y-A.collectorFeet(move).Y
    if flat.Magnitude<2 or flat.Magnitude>12 or rise>4.5 or rise< -3 then return false end
    if not A.collectorSegmentSafe(move.root.Position,target.Position)then return false end
    if not A.collectorSmallObstacleStep(move,flat.Unit)then return false end
    move.walkDirection=flat.Unit;move.smoothDirection=flat.Unit
    A.log("direct_candy_hop",{position=move.root.Position,target=target,targetPosition=target.Position})
    return true
end
function A.collectorSmallObstacleStep(move,desired)
    if A.collectorSupportedStairs(move,desired)then return false end
    local now=os.clock()
    if now<(move.nextSmallStepJump or 0)or move.humanoid.FloorMaterial==Enum.Material.Air
        or move.jumpPending or desired.Magnitude<0.1 then return false end
    local direction=desired.Unit;local feet=A.collectorFeet(move)
    local h=move.humanoid
    local apex=h.UseJumpPower and h.JumpPower*h.JumpPower/(2*math.max(workspace.Gravity,1))or h.JumpHeight
    local maxRise=math.min(4.5,apex-0.75)
    if maxRise<0.25 then return false end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local low=workspace:Raycast(feet+Vector3.new(0,0.35,0),direction*1.8,params)
    -- Benches can have an open space underneath; a foot ray alone misses them.
    local center=Vector3.new(move.root.Position.X,feet.Y+3,move.root.Position.Z)
    if not low then
        low=workspace:Blockcast(CFrame.new(center),Vector3.new(2,3.4,2),direction*1.8,params)
    end
    if not low or low.Normal.Y>0.65 then return false end
    local top=workspace:Raycast(Vector3.new(low.Position.X,feet.Y+maxRise+1,low.Position.Z)+direction*0.15,Vector3.new(0,-maxRise-2,0),params)
    local rise=top and top.Position.Y-feet.Y or math.huge
    if rise<0.25 or rise>maxRise
        or not A.collectorJumpClearance(move,rise+1)then return false end
    -- Test the jumping body above the tread, rather than rejecting the tread itself.
    local lift=rise+0.35
    if workspace:Blockcast(CFrame.new(center),Vector3.new(2,3.4,2),Vector3.new(0,lift,0),params)
        or workspace:Blockcast(CFrame.new(center+Vector3.new(0,lift,0)),Vector3.new(2,3.4,2),direction*3,params)then return false end
    local landingOrigin=feet+direction*3+Vector3.new(0,maxRise+1,0)
    -- A small obstacle hop needs nearby support on this surface.
    -- Deep drops belong to the planned route, not this three-stud shortcut.
    local landingDepth=maxRise+1+4
    local landing=workspace:Raycast(landingOrigin,Vector3.new(0,-landingDepth,0),params)
    if not landing or landing.Normal.Y<0.65 or landing.Position.Y-feet.Y>maxRise or landing.Position.Y<=workspace.FallenPartsDestroyHeight+3 then return false end
    if not A.collectorSegmentSafe(move.root.Position,landing.Position)then return false end
    move.obstacleJump={direction=direction,landingGoal=landing.Position,untilAt=now+1.2}
    move.nextSmallStepJump=now+2;move.airDirection=direction
    move.jumpPending=true;move.jumpRequestedIndex=nil
    move.humanoid.Jump=true;move.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    move.humanoid:Move(direction,false)
    A.log("small_obstacle_step",{position=move.root.Position,rise=rise,landing=landing.Position,obstacle=low.Instance})
    return true
end

function A.collectorDefenseReason(root,threat)
    if A.collectorIncomingAttacker==threat.player and os.clock()<(A.collectorIncomingUntil or 0)then return "incoming_knife"end
    local enemyPosition=threat.current or threat.position
    local delta=root.Position-enemyPosition
    if math.abs(delta.Y)>6 then return nil end
    local flat=Vector3.new(delta.X,0,delta.Z)
    if flat.Magnitude<=40 then return "range"end
    local _,_,enemy=A.body(threat.player)
    if enemy and flat.Magnitude<=80 and flat.Magnitude>0.1 then
        local velocity=enemy.AssemblyLinearVelocity
        local speed=Vector3.new(velocity.X,0,velocity.Z)
        if speed.Magnitude>2 and speed:Dot(flat.Unit)>2 and speed.Unit:Dot(flat.Unit)>0.65 then return "chasing"end
    end
end
function A.collectorDefenseRangeStep(root)
    if A.isZombie(A.player)or A.role(A.player)=="Murderer"then return false end
    A.updateCollectorThreats()
    local state=getgenv().QOS_MM2_TP_STATE or {}
    local map=A.collectContainer;while map and map.Parent~=workspace do map=map.Parent end
    local onCooldown=os.clock()<(state.nextAt or 0)or os.clock()<(A.nextCollectorTeleport or 0)
    if not onCooldown or not A.collectorPositionReady()then
        if not A.collectorShootWhileCollecting then A.collectorDefensiveUntil=nil;A.collectorDefensiveTarget=nil end
        return false
    end
    local chosen,distance,chosenReason=nil,math.huge,nil
    for _,threat in ipairs(A.collectorThreats)do
        if not threat.provisional and threat.player then
            local delta=(threat.current or threat.position)-root.Position
            local flat=Vector3.new(delta.X,0,delta.Z).Magnitude
            local reason=A.collectorDefenseReason(root,threat)
            if reason and flat<distance then
                chosen,distance,chosenReason=threat.player,flat,reason
            end
        end
    end
    if not chosen then return false end
    if not A.findTool(A.player,"Gun")then
        if os.clock()>=(A.nextNoDefenseGunLog or 0)then
            A.nextNoDefenseGunLog=os.clock()+2;A.log("defense_unarmed",{target=chosen.Name,distance=distance})
        end
        return false
    end
    A.collectorDefensiveTarget=chosen;A.collectorDefensiveUntil=os.clock()+2.5
    if os.clock()>=(A.nextDefenseLog or 0)then
        A.nextDefenseLog=os.clock()+1;A.log("defense_early",{target=chosen.Name,distance=distance,teleportUnavailable=true,reason=chosenReason})
    end
    return true
end

function A.collectorUrgentEscape(root)
    if A.collectorFullCombatPriority()then return false end
    if A.role(A.player)=="Murderer"then return false end
    A.updateCollectorThreats()
    if A.collectorKnifeEscape(root)or A.collectorEmergencyTeleport(root)then return true end
    local near=#A.collectorEscapePressure(root)>0
    if not near then return false end
    if not A.movement then
        if not A.acquireMove("farm")then return false end
        local m=A.movement;m.walking=true;m.walkSpeed=m.humanoid.WalkSpeed
        m.walkDirection=Vector3.zero;m.humanoid.AutoRotate=true
        m.humanoid.WalkSpeed=math.clamp(A.config.farmWalkSpeed,4,16);m.appliedWalkSpeed=m.humanoid.WalkSpeed
    end
    local move=A.movement
    if move.owner~="farm"then return false end
    return A.collectorPlanningEscape(move)
end

function A.collectorNoRouteGoal(move)
    local now=os.clock();local origin=move.root.Position
    local memory=move.noRouteMemory or {};move.noRouteMemory=memory
    for i=#memory,1,-1 do
        if now-memory[i].at>30 or(origin-memory[i].position).Magnitude>32 then table.remove(memory,i)end
    end
    if #memory==0 or(origin-memory[#memory].position).Magnitude>2 then
        memory[#memory+1]={position=origin,at=now};if #memory>24 then table.remove(memory,1)end
    end
    local forward=move.noRouteDirection or move.walkDirection or move.root.CFrame.LookVector
    forward=Vector3.new(forward.X,0,forward.Z)
    if forward.Magnitude<0.1 then forward=move.root.CFrame.LookVector;forward=Vector3.new(forward.X,0,forward.Z)end
    if forward.Magnitude<0.1 then return nil end
    forward=forward.Unit;local side=Vector3.new(-forward.Z,0,forward.X)
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={move.character};params.RespectCanCollide=true
    local best,bestScore,bestDirection
    for _,direction in ipairs({forward,(forward+side).Unit,(forward-side).Unit,side,-side,-forward})do
        local goal=origin+direction*6
        local ground=workspace:Raycast(goal,Vector3.new(0,-8,0),params)
        local drop=ground and A.collectorFeet(move).Y-ground.Position.Y
        if ground and ground.Normal.Y>=0.6 and drop>=-1 and drop<=4
            and A.collectorBodyClear(move,direction,6)and A.collectorRecoveryClear(move,goal)
            and A.collectorSegmentSafe(origin,goal)then
            local score=direction:Dot(forward)*3-math.abs(drop)*0.2
            for _,visited in ipairs(memory)do
                local distance=(goal-visited.position).Magnitude
                if distance<5 then score=score-(5-distance)*4 end
            end
            if not bestScore or score>bestScore then best,bestScore,bestDirection=goal,score,direction end
        end
    end
    if best then move.noRouteDirection=bestDirection end
    return best
end
function A.collectorNoRouteMove(root)
    -- A fresh route comparison needs its sampled origin to remain valid.
    -- Existing proven routes keep moving through the normal path controller.
    if A.collectorChoosing then return false end
    if not A.movement and not A.acquireMove("farm")then return false end
    local move=A.movement
    if not move or move.owner~="farm"then return false end
    if move.recoveryGoal then return true end
    local goal=A.collectorNoRouteGoal(move)
    if not goal then return false end
    if not move.walking then
        move.walking=true;move.walkSpeed=move.humanoid.WalkSpeed
        move.humanoid.AutoRotate=true
    end
    local speed=math.clamp(A.config.farmWalkSpeed,4,16)
    move.humanoid.WalkSpeed=speed;move.appliedWalkSpeed=speed
    A.clearWalkRoute(move)
    move.recoveryGoal=goal;move.recoveryUntil=os.clock()+(goal-root.Position).Magnitude/speed+0.25
    local delta=goal-root.Position;local flat=Vector3.new(delta.X,0,delta.Z)
    if flat.Magnitude>0.1 then move.walkDirection=flat.Unit;move.humanoid:Move(flat.Unit,false)end
    A.log("no_coin_route_reposition",{origin=root.Position,goal=goal})
    return true
end
function A.farmStep(dt)
    if not A.config.farm then return end
    A.collectorInstallRoundStop()
    if not A.collectorMapReady() then
        A.collectorActiveRound=false
        A.stopCollectorCombat()
        A.clearCollectorThreats()
        A.collectorWatch=nil;A.collectorRoundStarted=nil;A.collectorFailedOrigins=nil
        if A.movement and A.movement.owner == "farm" then A.releaseMove(true) end
        A.note("Collector", "Waiting for the round")
        return
    end
    A.collectorActiveRound=true
    if A.movement and A.movement.owner ~= "farm" then return end
    if os.clock() - A.lastScan > 0.25 then A.coinCache = A.coins(); A.lastScan = os.clock() end
    local _, _, root = A.body(A.player)
    if not root then return end
    A.collectorEnsureLadders()
    if not A.collectorFullCombatPriority()then A.collectorRefreshTeleportRoutes()end
    local defense=A.collectorDefenseRangeStep(root)
    local collectionShots=A.collectorInfectionShotStep(root)
    local escaping=A.collectorUrgentEscape(root)
    if defense or collectionShots or(A.collectorDefensiveUntil or 0)>os.clock()then
        A.collectorRoleStep(root)
        if escaping then return end
    elseif escaping then return end
    if A.collectorOrphanClimbStep(root)then return end
    if (not A.collectorCombatRole or A.collectorCollectingCoins()) and A.movement and A.movement.owner=="farm"and A.collectorAirStep(A.movement)then return end
    if A.collectorRoleStep(root)then return end
    if (not A.collectorCombatRole or A.collectorCollectingCoins()) and (A.collectorKnifeEscape(root) or A.collectorEmergencyTeleport(root)) then return end
    if A.movement and A.movement.owner=="farm" and (A.collectorRaisedPickupStep(A.movement) or A.collectorClimbStep(A.movement)) then return end
    A.collectorDoorStep(root)
    if A.movement and os.clock()<(A.movement.doorWaitingUntil or 0)then return end
    A.collectorRoundStarted=A.collectorRoundStarted or os.clock()
    A.updateCollectorThreats()
    -- This monitor belongs to the collector, not to an individual candy or path.
    -- A chain of rejected routes must still trigger physical recovery.
    local activeMove=A.movement
    if activeMove and activeMove.owner=="farm" and activeMove.recoveryGoal then return end
    local nowWatch=os.clock()
    local watch=A.collectorWatch
    if not watch or (root.Position-watch.position).Magnitude>1.5 then
        A.collectorWatch={position=root.Position,at=nowWatch}
    elseif activeMove and activeMove.walking and nowWatch-watch.at>2.4 then
        watch.at=nowWatch
        local goal=A.collectorRecoveryGoal(activeMove)
        if goal then
            A.clearWalkRoute(activeMove)
            activeMove.recoveryGoal=goal;activeMove.recoveryUntil=nowWatch+1
            activeMove.jumpPending=false
            A.note("Collector","Unstuck")
            return
        end
    end
    if A.movement and A.collectorSurfaceRecovery(A.movement)then return end
    local nearest,distance=A.collectorGoal(root,A.movement and A.movement.target)
    if not nearest then
        if A.collectorNoRouteMove(root)then
            A.note("Collector","Looking for candy")
            return
        end
        if A.collectorChoosing then
            A.note("Collector","Choosing a route")
            return
        end
        if A.movement and A.collectorPlanningEscape(A.movement)then return end
        if A.movement then A.releaseMove(true) end
        A.note("Collector", "No safe route")
        return
    end
    if not A.movement and not A.acquireMove("farm") then return end
    local m = A.movement
    if not m.walking then
        m.walking, m.walkSpeed, m.walkDirection = true, m.humanoid.WalkSpeed, Vector3.zero
        m.humanoid.AutoRotate = true
    end
    local speed = math.min(m.walkSpeed, math.clamp(A.config.farmWalkSpeed, 4, 16))
    if speed ~= m.humanoid.WalkSpeed then m.humanoid.WalkSpeed = speed; m.appliedWalkSpeed = speed end
    if m.target~=nearest then
        A.log("target_selected",{target=nearest,position=nearest.Position,combat=A.collectorCombatRole})
        A.collectorCoast(m)
        m.target = nearest; m.arrivedAt = nil; m.replan = false; m.nextPlanAt=0; m.exhaustedRoutes=0; m.threatBlocks=0; m.routeStartedAt=os.clock()
    end
    local target = m.target
    if not target then return end
    local offset = target.Position - root.Position
    local horizontal = Vector3.new(offset.X, 0, offset.Z)
    if (not A.collectorCombatRole or A.collectorCollectingCoins()) and horizontal.Magnitude <= 1.8 and math.abs(target.Position.Y-A.collectorFeet(m).Y)<2 then
        if not m.arrivedAt then A.collectorCoast(m) end
        m.arrivedAt = m.arrivedAt or os.clock()
        if os.clock() - m.arrivedAt > 0.15 then
            local previous=m.walkDirection
            A.skipCollectorTarget(m,target,"Pickup did not register; trying the next closest candy",5)
            m.walkDirection=previous;A.collectorCoast(m)
        end
        return
    end
    -- Watch physical movement before route/planning early returns. Replanning is
    -- not evidence of progress, and must not restart this watchdog.
    local now=os.clock()
    if m.recoveryGoal then return end
    if m.walkDirection and m.walkDirection.Magnitude>0.01
        and A.collectorMotionStalled(m,root.Position,now) then
        m.stallRecoveries=(m.stallRecoveries or 0)+1
        local goal=m.stallRecoveries<3 and A.collectorRecoveryGoal(m)
        if goal then
            A.clearWalkRoute(m);m.recoveryGoal=goal;m.recoveryUntil=now+1
            m.lastProgressAt=now
            A.note("Collector","Stepping around an obstacle")
        else A.skipCollectorTarget(m,target,"Obstacle blocks this route; choosing another candy",20) end
        return
    end
    if not m.lastProgressPosition or (root.Position-m.lastProgressPosition).Magnitude>0.8 then
        m.lastProgressPosition=root.Position;m.lastProgressAt=now;m.stallRecoveries=0
    elseif now-(m.lastProgressAt or now)>1.2 then
        m.lastProgressAt=now;m.stallRecoveries=(m.stallRecoveries or 0)+1
        if m.stallRecoveries>=3 then
            A.skipCollectorTarget(m,target,"Physical movement blocked; skipping this destination",20)
            return
        end
        m.replan=true;m.nextPlanAt=0
    end
    if A.collectorCombatRole and m.waypoints and os.clock()>=(m.nextCombatReplan or 0)then
        local endpoint=m.waypoints[#m.waypoints]
        if endpoint and (endpoint.Position-A.collectorCombatRouteGoal(m,target)).Magnitude>4 then
            m.nextCombatReplan=os.clock()+0.65;m.routeTarget=nil;m.nextPlanAt=0
        end
    end
    if m.replan then m.replan = false; A.clearWalkRoute(m) end
    if not m.waypoints or m.routeTarget~=target then
        A.planWalk(m,target)
        if not m.waypoints then return end
    end
    -- Skip detours around non-collidable decoration only after checking real
    -- collision, supported ground, floor height and threat clearance.
    for index=m.pathIndex+1,math.min(#m.waypoints,m.pathIndex+4) do
        local candidate=m.waypoints[index]
        if candidate.Action==Enum.PathWaypointAction.Jump or candidate.Label=="Climb" then break end
        local previous=m.waypoints[index-1]
        if previous.Action==Enum.PathWaypointAction.Jump or previous.Label=="Climb" then break end
        if A.collectorWalkClear(m,candidate.Position)then m.pathIndex=index else break end
    end
    if os.clock()>=(m.nextRouteSafetyCheck or 0)then
        m.nextRouteSafetyCheck=os.clock()+0.3
        if not A.collectorRouteSafe(root.Position,m.waypoints,m.pathIndex)then
            A.skipCollectorTarget(m,target,"Murderer moved into this route; choosing another candy",5)
            m.humanoid:Move(Vector3.zero,false)
            return
        end
    end
    local waypoint = m.waypoints[m.pathIndex]
    while waypoint do
        local delta = waypoint.Position - root.Position
        if not A.collectorWaypointReached(m,waypoint) then break end
        if waypoint.Action==Enum.PathWaypointAction.Jump and m.jumpedIndex~=m.pathIndex then break end
        m.pathIndex = m.pathIndex + 1; waypoint = m.waypoints[m.pathIndex]
    end
    if not waypoint then
        m.exhaustedRoutes=(m.exhaustedRoutes or 0)+1
        if m.exhaustedRoutes>=2 then A.skipCollectorTarget(m,target,"Route ended without reaching candy; skipping",15)
        else if not A.collectorCoast(m) then A.clearWalkRoute(m) end end
        return
    end
    if not A.collectorSegmentSafe(root.Position,waypoint.Position) then
        m.walkDirection=Vector3.zero;m.smoothDirection=Vector3.zero;m.replan=true
        if target==A.collectorEscape then A.collectorEscapeFailed=true;A.collectorEscapeAttempt=(A.collectorEscapeAttempt or 0)+1 end
        m.threatBlocks=(m.threatBlocks or 0)+1
        if m.threatBlocks>=3 then A.skipCollectorTarget(m,target,"Candy route stays unsafe; choosing another",5)
        else A.note("Collector","Murderer on this route") end
        return
    end
    local delta = waypoint.Position - root.Position
    local direction = Vector3.new(delta.X, 0, delta.Z)
    m.walkDirection = direction.Magnitude > 0.01 and direction.Unit or Vector3.zero


    if waypoint.Action == Enum.PathWaypointAction.Jump and m.jumpedIndex ~= m.pathIndex then
        if direction.Magnitude<=4 and not A.requestWalkJump(m,m.pathIndex) then
            A.skipCollectorTarget(m,target,"Jump blocked or repeated; finding another route",15)
        end
    end
end
A.group(A.farmPage,"Collect")
A.toggle(A.farmPage, "Auto grab dropped gun", "autoGun", function()
    if A.config.farm then
        A.note("Collector", "Gun pickup on"); return true
    end
    return true
end)
A.toggle(A.farmPage, "Walking coin / candy collector", "farm", function()
    A.coinCache, A.coinSkip, A.lastScan = {}, setmetatable({}, { __mode = "k" }), 0
    A.note("Collector", "Collector on")
    return true
end)
A.number(A.farmPage, "Walk speed", "farmWalkSpeed", 4, 16)
A.toggle(A.farmPage, "Require round data before moving", "requireRound")
A.label(A.farmPage, "Fills the bag, then uses the role weapon. WASD or Space stops movement.", 36)
A.button(A.farmPage, "Stop", function() A.set("farm", false) end)

-- Diagnostics are copied as plain text only when the user presses the button.
function A.report()
    local executor = "unknown"
    if type(identifyexecutor) == "function" then
        local ok, value = pcall(identifyexecutor); if ok then executor = tostring(value) end
    end
    local out = { "qos-MM2 " .. A.version, "Executor: " .. executor,
        "Place: " .. tostring(game.PlaceId), "Universe: " .. tostring(game.GameId),
        "Round module: " .. tostring(A.round ~= nil), "Local role: " .. A.role(A.player),
        "Round eligible: " .. tostring(A.inRound()), "Touch API: " .. tostring(type(firetouchinterest) == "function"),
        "Gun shots use the weapon hook.",
        "Old hooks present: " .. tostring(ENV.QOS_MM2_HOOK ~= nil or ENV.QOS_MM2_TARGET_HOOK ~= nil),
        "Movement: " .. tostring(A.movement and A.movement.owner or "none") }
    for key, value in pairs(A.statuses) do table.insert(out, key .. ": " .. tostring(value)) end
    return table.concat(out, "\n")
end
A.group(A.settingsPage,"Settings")
A.button(A.settingsPage,"Copy diagnostics",function()
    if type(setclipboard)=="function" then setclipboard(A.report()); A.note("Diagnostics","Copied") end
end)
A.group(A.settingsPage,"General")
A.toggle(A.settingsPage,"Anti-AFK","antiAfk")
A.button(A.settingsPage, "Turn all features off", function()
    for key, value in pairs(A.config) do
        if type(value) == "boolean" and key ~= "requireRound" then A.set(key, false) end
    end
    A.releaseMove(true); A.restoreCollision()
    for p in pairs(A.esp) do A.clearESP(p) end
    A.note("qos-MM2", "All features off")
end)
function A.Unload()
    if not A.alive then return A.unloadReport end
    A.stopCollectorCombat();A.collectorRestoreZombieCamera();A.log("session_end",{});A.flushLog()
    A.alive=false
    local report={errors={}}
    local function clean(name,fn)
        local ok,err=pcall(fn)
        if not ok then table.insert(report.errors,name..": "..tostring(err)) end
    end
    for key,value in pairs(A.config) do if type(value)=="boolean" then A.config[key]=false end end
    clean("collector danger zones",A.clearCollectorThreats)
    clean("weapon hooks",A.disableSilentAim)
    if A.collectorJumpHeld then A.collectorJumpHeld.Jump=false;A.collectorJumpHeld=nil end
    for _,name in ipairs({"qos-MM2-Tracers","qos-MM2-Walking","qos-MM2-JumpHold","qos-MM2-Safety","qos-MM2-Aiming","qos-MM2-CombatCamera"}) do
        clean(name,function()A.Run:UnbindFromRenderStep(name)end)
    end
    for _,connection in ipairs(A.connections) do clean("connection",function()connection:Disconnect()end) end
    clean("movement",function()A.releaseMove(true)end)
    clean("collision",A.restoreCollision)
    local current=coroutine.running()
    for thread in pairs(A.tasks or {}) do
        if thread~=current and coroutine.status(thread)~="dead" then clean("task",function()task.cancel(thread)end) end
    end
    for resource in pairs(A.resources or {}) do clean("path",function()resource:Destroy()end) end
    A.uiMounted=false
    if A.reactRoot then clean("React unmount",function()
        if ReactRoblox.flushSync then ReactRoblox.flushSync(function()A.reactRoot:unmount()end)
        else A.reactRoot:unmount() end
    end) end
    if A.bundleCleanup then clean("UI scheduler",A.bundleCleanup) end
    for _,field in ipairs({"uiHost","gui","prismPackage"}) do
        if A[field] then clean(field,function()A[field]:Destroy()end) end
    end
    if ENV.QOS_MM2==A then ENV.QOS_MM2=nil end
    local unload=A.Unload
    table.clear(A)
    A.alive=false;A.Unload=unload;A.unloadReport=report
    return report
end

A.button(A.settingsPage,"Export log",function()
    A.flushLog()
    if type(writefile)=="function"then
        writefile("qos-MM2-logs/latest-export.jsonl",A.logText())
        A.note("Logs","Saved qos-MM2-logs/latest-export.jsonl")
    end
end)
A.button(A.settingsPage, "Unload qos-MM2 (End)", A.Unload)
-- 0.3.124. R15 movement, free camera, gun hook, knife read, plainer status text.

function A.r15Profile(character, humanoid, root)
    local airborne = humanoid.FloorMaterial == Enum.Material.Air
        or humanoid:GetState() == Enum.HumanoidStateType.Jumping
        or humanoid:GetState() == Enum.HumanoidStateType.Freefall
        or humanoid:GetState() == Enum.HumanoidStateType.Climbing
    local cache = A.r15Cache
    if airborne and cache and cache.character == character then return cache.profile end
    local declared = humanoid.HipHeight + root.Size.Y / 2
    if humanoid.RigType == Enum.HumanoidRigType.R6 then
        local leg = character:FindFirstChild("Left Leg") or character:FindFirstChild("Right Leg")
        if leg and leg:IsA("BasePart") then declared = declared + leg.Size.Y end
    end
    local function sole(name)
        local foot = character:FindFirstChild(name)
        if foot and foot:IsA("BasePart") then return foot.Position.Y - foot.Size.Y / 2 end
    end
    local left, right = sole("LeftFoot"), sole("RightFoot")
    local measured = (left or right) and (root.Position.Y - math.min(left or right, right or left))
    local footOffset = declared
    if measured and not airborne and math.abs(measured - declared) > 0.75 then footOffset = measured end
    if footOffset < 1 or footOffset > 8 then footOffset = (measured and not airborne and measured) or 3 end
    local radius = math.clamp(math.max(root.Size.X, root.Size.Z) / 2, 0.5, 1.5)
    local head = character:FindFirstChild("Head")
    local top = head and head:IsA("BasePart") and (head.Position.Y + head.Size.Y / 2) or (root.Position.Y + 1.5)
    local height = math.clamp(top - (root.Position.Y - footOffset), 3, 8)
    local profile = {
        footOffset = footOffset, radius = radius, tightRadius = math.max(0.5, radius - 0.2),
        height = height, hipHeight = humanoid.HipHeight,
    }
    if not airborne then A.r15Cache = {character = character, profile = profile} end
    return profile
end

function A.collectorFeet(move)
    local profile = A.r15Profile(move.character, move.humanoid, move.root)
    return move.root.Position - Vector3.new(0, profile.footOffset, 0)
end

function A.collectorPlanOrigin(move)
    local origin = move.root.Position
    local feet = A.collectorFeet(move).Y
    local footOffset = origin.Y - feet
    if move.humanoid.FloorMaterial == Enum.Material.Air then
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {move.character}
        params.RespectCanCollide = true
        local ground = workspace:Raycast(origin, Vector3.new(0, -12, 0), params)
        if not ground or ground.Normal.Y < 0.6 then return nil end
        feet = ground.Position.Y
        origin = Vector3.new(origin.X, feet + footOffset, origin.Z)
    end
    return origin, feet
end

do
    local service = game:GetService("PathfindingService")
    local create = service.CreatePath
    service.CreatePath = function(self, params)
        local copy = {}
        for key, value in pairs(params or {}) do copy[key] = value end
        local character, humanoid, root = A.body(A.player)
        if character and humanoid and root and humanoid.RigType ~= Enum.HumanoidRigType.R6 then
            local profile = A.r15Profile(character, humanoid, root)
            if copy.AgentHeight == 5 or copy.AgentHeight == nil then copy.AgentHeight = profile.height end
            if copy.AgentRadius == 2 then copy.AgentRadius = profile.radius
            elseif copy.AgentRadius == 1.25 then copy.AgentRadius = math.clamp((profile.radius + profile.tightRadius) / 2, 0.5, 1.5)
            elseif copy.AgentRadius == 1 then copy.AgentRadius = profile.tightRadius end
            if copy.AgentRadius and copy.AgentRadius <= profile.tightRadius + 0.05 and copy.WaypointSpacing == 2 then
                copy.WaypointSpacing = 1
            end
            if copy.AgentCanClimb == nil then copy.AgentCanClimb = true end
        end
        return create(self, copy)
    end
end

function A.suspendToolCollision()
    local character = A.player.Character
    local tool = character and character:FindFirstChildOfClass("Tool")
    if A.toolCollisionTool and A.toolCollisionTool ~= tool then A.restoreToolCollision() end
    if not tool or not A.movement or not A.movement.walking then return end
    A.toolCollision = A.toolCollision or {}
    A.toolCollisionTool = tool
    for _, part in ipairs(tool:GetDescendants()) do
        if part:IsA("BasePart") then
            if A.toolCollision[part] == nil then A.toolCollision[part] = part.CanCollide end
            part.CanCollide = false
        end
    end
end
function A.restoreToolCollision()
    for part, value in pairs(A.toolCollision or {}) do
        pcall(function() if part.Parent then part.CanCollide = value end end)
    end
    A.toolCollision, A.toolCollisionTool = nil, nil
end
do
    local walk, release = A.walkInput, A.releaseMove
    function A.walkInput(dt)
        A.suspendToolCollision()
        return walk(dt)
    end
    function A.releaseMove(restorePosition)
        A.restoreToolCollision()
        return release(restorePosition)
    end
end

function A.collectorBodyClear(move, direction, length)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {move.character}
    params.RespectCanCollide = true
    local profile = A.r15Profile(move.character, move.humanoid, move.root)
    local feet = A.collectorFeet(move)
    local center = Vector3.new(move.root.Position.X, feet.Y + profile.height / 2, move.root.Position.Z)
    local forward = Vector3.new(direction.X, 0, direction.Z)
    if forward.Magnitude < 0.01 then return true end
    local size = Vector3.new(math.max(0.8, move.root.Size.X), profile.height, math.max(0.6, move.root.Size.Z))
    return workspace:Blockcast(CFrame.lookAt(center, center + forward), size, forward.Unit * length, params) == nil
end

function A.collectorJumpClearance(move, needed)
    local humanoid = move.humanoid
    if not humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {move.character}
    params.RespectCanCollide = true
    local profile = A.r15Profile(move.character, move.humanoid, move.root)
    local origin = A.collectorFeet(move) + Vector3.new(0, profile.height + 0.3, 0)
    return workspace:Raycast(origin, Vector3.new(0, math.max(2, needed or 3), 0), params) == nil
end

function A.collectorDoorwayDirection(move, desired)
    if desired.Magnitude < 0.1 or move.humanoid:GetState() == Enum.HumanoidStateType.Climbing then return desired end
    local forward = desired.Unit
    local side = Vector3.new(-forward.Z, 0, forward.X)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {move.character}
    params.RespectCanCollide = true
    local profile = A.r15Profile(move.character, move.humanoid, move.root)
    local minSpan = profile.radius * 2 + 0.15
    local center, width
    for _, ahead in ipairs({0, 1}) do
        local origin = move.root.Position + forward * ahead
        local left = workspace:Raycast(origin, -side * 3, params)
        local right = workspace:Raycast(origin, side * 3, params)
        if left and right and math.abs(left.Normal.Y) < 0.25 and math.abs(right.Normal.Y) < 0.25 then
            local span = left.Distance + right.Distance
            if span >= minSpan and span < 4.5 and (not width or span < width) then
                center = (right.Distance - left.Distance) * 0.5
                width = span
            end
        end
    end
    if not center or math.abs(center) < 0.25 then return desired end
    local correction = side * math.clamp(center * 1.5, -0.75, 0.75)
    local direction = (forward + correction).Unit
    if workspace:Raycast(move.root.Position, direction * 1.2, params) then return desired end
    return direction
end

function A.collectorSupportedStairs(move, direction)
    if not move.waypoints or direction.Magnitude < 0.1 then return false end
    local point = move.waypoints[move.pathIndex or 1]
    if not point or point.Action == Enum.PathWaypointAction.Jump or point.Label == "Climb" then return false end
    local now = os.clock()
    local cache = move.stairProbe
    if cache and now - cache.at < 0.12 and cache.direction:Dot(direction.Unit) > 0.9 then return cache.value end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {move.character}
    params.RespectCanCollide = true
    local minNormal = math.cos(math.rad(math.clamp(move.humanoid.MaxSlopeAngle, 0, 89)))
    local previousY, previousNormal, ramp, supported = nil, nil, false, true
    for _, distance in ipairs({0, 0.6, 1.2, 1.8}) do
        local hit = workspace:Raycast(move.root.Position + direction.Unit * distance + Vector3.new(0, 1, 0), Vector3.new(0, -8, 0), params)
        if not hit or hit.Normal.Y < minNormal then supported = false; break end
        if previousY then
            local rise = hit.Position.Y - previousY
            local flat = hit.Normal.Y >= 0.92 and (not previousNormal or previousNormal >= 0.92)
            if flat and math.abs(rise) > 1.15 then supported = false; break end
            if math.abs(rise) > 0.08 then ramp = true end
        end
        previousY, previousNormal = hit.Position.Y, hit.Normal.Y
    end
    if supported and ramp then
        for _, side in ipairs({0, -0.7, 0.7}) do
            local offset = Vector3.new(-direction.Z, 0, direction.X).Unit * side
            local wall = workspace:Raycast(move.root.Position + Vector3.new(0, 2, 0) + offset, direction.Unit * 1.8, params)
            if wall and wall.Normal.Y < minNormal then supported = false; break end
        end
    end
    local value = supported and ramp
    move.stairProbe = {at = now, direction = direction.Unit, value = value}
    return value
end

function A.collectorSmallObstacleStep(move, desired)
    if A.collectorSupportedStairs(move, desired) then return false end
    local now = os.clock()
    if now < (move.nextSmallStepJump or 0) or move.humanoid.FloorMaterial == Enum.Material.Air
        or move.jumpPending or desired.Magnitude < 0.1 then return false end
    local direction = desired.Unit
    local feet = A.collectorFeet(move)
    local humanoid = move.humanoid
    local profile = A.r15Profile(move.character, humanoid, move.root)
    local apex = humanoid.UseJumpPower and humanoid.JumpPower * humanoid.JumpPower / (2 * math.max(workspace.Gravity, 1)) or humanoid.JumpHeight
    local maxRise = math.min(4.5, apex - 0.75)
    if maxRise < 0.25 then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {move.character}
    params.RespectCanCollide = true
    local body = Vector3.new(math.max(0.8, move.root.Size.X), profile.height, math.max(0.6, move.root.Size.Z))
    local center = Vector3.new(move.root.Position.X, feet.Y + profile.height / 2, move.root.Position.Z)
    local low = workspace:Raycast(feet + Vector3.new(0, 0.35, 0), direction * 1.8, params)
    if not low then low = workspace:Blockcast(CFrame.new(center), body, direction * 1.8, params) end
    if not low or low.Normal.Y > 0.65 then return false end
    local top = workspace:Raycast(low.Position + direction * 0.35 + Vector3.new(0, maxRise + 1, 0), Vector3.new(0, -maxRise - 2, 0), params)
    if not top or top.Normal.Y < 0.65 then return false end
    local rise = top.Position.Y - feet.Y
    local flat = Vector3.new(top.Position.X - feet.X, 0, top.Position.Z - feet.Z)
    if rise < 0.25 or rise > maxRise or flat.Magnitude < 0.3 or flat.Magnitude > 4.5 then return false end
    if not A.collectorJumpClearance(move, rise + 1) then return false end
    if workspace:Blockcast(CFrame.new(center), body, Vector3.new(0, rise + 0.35, 0), params) then return false end
    if workspace:Blockcast(CFrame.new(center + Vector3.new(0, rise + 0.35, 0)), body, direction * math.min(flat.Magnitude, 3), params) then return false end
    if top.Position.Y <= workspace.FallenPartsDestroyHeight + 3 then return false end
    if not A.collectorSegmentSafe(move.root.Position, top.Position) then return false end
    move.obstacleJump = {direction = direction, landingGoal = top.Position, untilAt = now + 1.2}
    move.nextSmallStepJump = now + 2
    move.airDirection = direction
    move.jumpPending = true
    move.jumpRequestedIndex = nil
    humanoid.Jump = true
    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    humanoid:Move(direction, false)
    return true
end

function A.collectorLadderShape(object)
    if object:IsA("TrussPart") then return nil end
    local named = object.Name:lower():find("ladder", 1, true) ~= nil
    local parts = {}
    if object:IsA("Model") then
        for _, part in ipairs(object:GetDescendants()) do
            if part:IsA("TrussPart") then return nil end
            if part:IsA("BasePart") and part.CanCollide then parts[#parts + 1] = part end
        end
    elseif object:IsA("BasePart") and object.CanCollide and named then parts = {object}
    else return nil end
    if #parts == 0 or #parts > 40 then return nil end
    local cf, size
    if object:IsA("Model") then cf, size = object:GetBoundingBox() else cf, size = object.CFrame, object.Size end
    if math.abs(cf.UpVector.Y) < 0.85 or size.Y < 4 or size.Y > 80 then return nil end
    local width, depth = math.max(size.X, size.Z), math.min(size.X, size.Z)
    if width < 1 or width > 8 or depth > 3 then return nil end
    if named then return cf, size, "named" end
    local rails, rungs = 0, {}
    for _, part in ipairs(parts) do
        local localCF = cf:ToObjectSpace(part.CFrame)
        if math.abs(localCF.UpVector.Y) > 0.85 then
            if part.Size.Y >= size.Y * 0.7 and math.min(part.Size.X, part.Size.Z) <= 0.6 then rails = rails + 1 end
            if part.Size.Y <= 0.45 and math.max(part.Size.X, part.Size.Z) >= width * 0.5
                and math.min(part.Size.X, part.Size.Z) <= 0.8 then rungs[#rungs + 1] = localCF.Position.Y end
        end
    end
    if rails < 2 or #rungs < 4 then return nil end
    table.sort(rungs)
    for i = 2, #rungs do
        local gap = rungs[i] - rungs[i - 1]
        if gap < 0.35 or gap > 2.1 then return nil end
    end
    if rungs[#rungs] - rungs[1] < 4 then return nil end
    return cf, size, "rung geometry"
end

function A.collectorEnsureLadders()
    local now = os.clock()
    if now < (A.nextAutoLadderScan or 0) then return end
    A.nextAutoLadderScan = now + 2
    local map = A.collectContainer
    while map and map.Parent ~= workspace do map = map.Parent end
    if not map then return end
    if A.autoLadderMap ~= map then
        if A.autoLadderFolder then A.resources[A.autoLadderFolder] = nil; A.autoLadderFolder:Destroy() end
        A.autoLadderMap = map
        A.autoLadderSources = setmetatable({}, {__mode = "k"})
        A.autoLadderFolder = Instance.new("Folder")
        A.autoLadderFolder.Name = "QOS_AutoLadders"
        A.autoLadderFolder.Parent = workspace
        A.resources[A.autoLadderFolder] = true
    end
    for source, truss in pairs(A.autoLadderSources) do
        if not source:IsDescendantOf(map) then truss:Destroy() A.autoLadderSources[source] = nil end
    end
    local _, humanoid, root = A.body(A.player)
    local radius = (humanoid and root) and A.r15Profile(A.player.Character, humanoid, root).radius or 1
    for _, object in ipairs(map:GetDescendants()) do
        if (object:IsA("Model") or (object:IsA("BasePart") and object.Name:lower():find("ladder", 1, true)))
            and not A.autoLadderSources[object] then
            local nested, parent = false, object.Parent
            while parent and parent ~= map do
                if A.autoLadderSources[parent] then nested = true; break end
                parent = parent.Parent
            end
            if not nested then
                local cf, size, kind = A.collectorLadderShape(object)
                if cf then
                    local thin = math.min(size.X, size.Z)
                    local face = (size.X <= size.Z) and cf.RightVector or cf.LookVector
                    if face.Magnitude < 0.01 then face = cf.LookVector end
                    face = face.Unit
                    local up = cf.UpVector.Magnitude > 0.01 and cf.UpVector.Unit or Vector3.yAxis
                    local right = up:Cross(face)
                    if right.Magnitude < 0.01 then right = Vector3.xAxis end
                    right = right.Unit
                    local depth = math.clamp(radius, 0.8, 1.4)
                    local truss = Instance.new("TrussPart")
                    truss.Name = "DetectedLadder"
                    truss.Size = Vector3.new(math.clamp(math.max(size.X, size.Z), 1.2, 2.5), size.Y, depth)
                    truss.CFrame = CFrame.fromMatrix(cf.Position + face * (thin / 2 + depth / 2), right, up)
                    truss.Anchored = true
                    truss.Transparency = 1
                    truss.CanCollide = true
                    truss.Parent = A.autoLadderFolder
                    A.autoLadderSources[object] = truss
                    A.nextTrussScan = 0
                    A.nextEscapeLadderScan = 0
                    A.log("ladder_detected", {source = object, kind = kind, position = truss.Position, size = truss.Size})
                end
            end
        end
    end
end

function A.collectorNearbyTruss(move, waypoint)
    local now = os.clock()
    if now >= (A.nextTrussScan or 0) then
        A.nextTrussScan = now + 1
        A.collectorTrusses = {}
        for _, part in ipairs(workspace:GetDescendants()) do
            if part:IsA("TrussPart") then table.insert(A.collectorTrusses, part) end
        end
    end
    local best, score
    for _, part in ipairs(A.collectorTrusses or {}) do
        if part.Parent then
            local localPoint = part.CFrame:PointToObjectSpace(move.root.Position)
            local half = part.Size / 2
            local gap = Vector3.new(math.max(0, math.abs(localPoint.X) - half.X), 0, math.max(0, math.abs(localPoint.Z) - half.Z)).Magnitude
            local within = math.abs(localPoint.Y) <= half.Y + 3
            local rising = waypoint and waypoint.Position.Y > A.collectorFeet(move).Y + 2
            if gap < 4 and within and (rising or move.humanoid:GetState() == Enum.HumanoidStateType.Climbing) and (not score or gap < score) then
                best, score = part, gap
            end
        end
    end
    return best
end

do
    local beginExit = A.collectorBeginLadderExit
    function A.collectorBeginLadderExit(move, truss)
        if not truss then return false end
        local feet = A.collectorFeet(move).Y
        local top = truss.Position.Y + A.collectorTrussSize(truss).Y / 2
        if feet < top - 0.5 then return false end
        return beginExit(move, truss)
    end
end

function A.collectorTeleportRouteDistance(origin, goal)
    local _, humanoid, root = A.body(A.player)
    local drop = 3
    if humanoid and root then drop = A.r15Profile(A.player.Character, humanoid, root).footOffset end
    local path = game:GetService("PathfindingService"):CreatePath({
        AgentRadius = 1.25, AgentHeight = 5, AgentCanJump = true, AgentCanClimb = true, WaypointSpacing = 4,
    })
    A.resources[path] = true
    local distance
    pcall(function()
        path:ComputeAsync(origin, goal)
        if path.Status ~= Enum.PathStatus.Success then return end
        local points = path:GetWaypoints()
        local last = points[#points]
        if not last or (last.Position - goal).Magnitude > 3 or math.abs(last.Position.Y - goal.Y) > 1.8 then return end
        local startY = points[1] and points[1].Position.Y
        if not startY or (math.abs(startY - (origin.Y - drop)) > 4 and math.abs(startY - (origin.Y - 3)) > 4) then return end
        distance = 0
        for i = 2, #points do distance = distance + (points[i].Position - points[i - 1].Position).Magnitude end
    end)
    A.resources[path] = nil
    path:Destroy()
    return distance
end

function A.collectorSegmentSafe(from, to)
    if A.isZombie(A.player) then return true end
    if A.collectorCombatRole and not A.collectorCollectingCoins() then return true end
    local delta = to - from
    for _, threat in ipairs(A.collectorThreats) do
        if A.collectorThreatRelevant(from, threat) or A.collectorThreatRelevant(to, threat) then
            local positions = {threat.current or threat.position, threat.position}
            for _, sample in ipairs(threat.future or {}) do positions[#positions + 1] = sample.position end
            for _, position in ipairs(positions) do
                local start = (from - position).Magnitude
                local finish = (to - position).Magnitude
                local t = delta:Dot(delta) > 0.001 and math.clamp((position - from):Dot(delta) / delta:Dot(delta), 0, 1) or 0
                local closest = (from + delta * t - position).Magnitude
                if start < 58 then
                    if finish < start - 0.1 or closest < start - 0.25 then return false end
                elseif closest < 48 then return false end
            end
        end
    end
    return true
end

function A.collectorDangerDistance()
    return 36
end

function A.roundMurdererKnown()
    for _, player in ipairs(A.playerList) do
        if player ~= A.player then
            local data = A.roundData(player)
            if data and data.Role == "Murderer" and data.Dead ~= true and data.Killed ~= true then return true end
            if A.role(player) == "Murderer" then return true end
        end
    end
    return false
end

do
    local ready = A.collectorMapReady
    function A.collectorMapReady()
        if not A.collectorRoundEnded then return ready() end
        if not A.roundMurdererKnown() then return ready() end
        A.collectorRoundEnded = false
        local open = ready()
        if not open then A.collectorRoundEnded = true end
        return open
    end
    local farm = A.farmStep
    function A.farmStep(dt)
        if A.config.farm and A.collectorMapReady() then
            A.collectorRoundStarted = A.collectorRoundStarted or os.clock()
        end
        return farm(dt)
    end
end

function A.collectorEscapePressure(root)
    if A.isZombie(A.player) or A.role(A.player) == "Murderer" then return {} end
    if A.collectorFullCombatPriority and A.collectorFullCombatPriority() then return {} end
    local now = os.clock()
    local threats = {}
    A.approachSamples = A.approachSamples or setmetatable({}, {__mode = "k"})
    for _, threat in ipairs(A.collectorThreats) do
        local known = false
        if threat.player then
            local data = A.roundData(threat.player)
            known = (data and data.Role == "Murderer") or A.role(threat.player) == "Murderer"
                or A.findTool(threat.player, "Knife") ~= nil or A.isZombie(threat.player)
        end
        if not (threat.provisional and not known) then
            local los = A.collectorThreatRelevant(root.Position, threat)
            if los or known then
                local enemy = threat.current or threat.position
                local delta = root.Position - enemy
                local flat = Vector3.new(delta.X, 0, delta.Z)
                local distance = flat.Magnitude
                local closing = 0
                local humanoid, part
                if threat.player then
                    local _, hum, rootPart = A.body(threat.player)
                    humanoid, part = hum, rootPart
                end
                if part and distance > 0.1 then
                    local velocity = part.AssemblyLinearVelocity
                    if velocity.Magnitude < 1 and humanoid then velocity = humanoid.MoveDirection * humanoid.WalkSpeed end
                    closing = math.max(velocity:Dot(flat.Unit), (velocity - root.AssemblyLinearVelocity):Dot(flat.Unit))
                end
                local sample = threat.player and A.approachSamples[threat.player]
                if sample and now - sample.at >= 0.08 and now - sample.at < 1 then
                    closing = math.max(closing, (sample.distance - distance) / (now - sample.at))
                end
                if threat.player and (not sample or now - sample.at >= 0.08) then
                    A.approachSamples[threat.player] = {distance = distance, at = now}
                end
                local limit = closing > 0.5 and 78 or 55
                if math.abs(delta.Y) <= 8 and distance < limit then threats[#threats + 1] = threat end
            end
        end
    end
    return threats
end

function A.collectorZombieCombat()
    if not A.config.farm then return false end
    local data = A.roundData(A.player)
    if data and data.Role == "Zombie" then return true end
    if A.isZombie(A.player) or A.collectorShootWhileCollecting then return true end
    for _, player in ipairs(A.playerList) do
        if A.isZombie(player) and A.espAlive(player) then return true end
    end
    return false
end
function A.collectorFirstPerson()
    if A.collectorSavedCameraMode then
        local zoom = A.collectorSavedZoom
        if zoom then
            A.player.CameraMaxZoomDistance = zoom.max
            A.player.CameraMinZoomDistance = zoom.min
        end
        A.player.CameraMode = A.collectorSavedCameraMode
        A.collectorSavedCameraMode, A.collectorSavedZoom = nil, nil
    end
    A.collectorRestoreZombieCamera()
end
function A.collectorCombatCameraReady()
    return true
end
function A.collectorCameraStep()
    A.collectorFirstPerson()
end

function A.sampleGunTarget(player, camera, requireScreen)
    local character, humanoid, root = A.body(player)
    if not character or not humanoid or not root then return nil end
    local origin = A.gunOrigin()
    if not origin then return nil end
    local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or root
    local position = A.gunAimPoint(torso, root, humanoid)
    if not A.finite(position) or not A.weaponVisible(origin, position, character) then return nil end
    local screen, onScreen
    if camera then screen, onScreen = camera:WorldToViewportPoint(torso.Position) end
    if requireScreen and not onScreen then return nil end
    return {
        position = position, screen = screen and Vector2.new(screen.X, screen.Y) or Vector2.zero,
        onScreen = onScreen == true, at = os.clock(), part = torso, root = root,
        character = character, humanoid = humanoid, distance = (position - origin).Magnitude,
    }
end

function A.redirectGunTarget(original)
    if not A.alive or not A.config.silentGunAim or A.Input:GetFocusedTextBox() ~= nil then return original end
    local gun = A.findTool(A.player, "Gun")
    if not gun or gun.Parent ~= A.player.Character then return original end
    local role = A.role(A.player)
    if role ~= "Sheriff" and role ~= "Hero" and role ~= "Gun holder" and not A.collectorShootWhileCollecting then return original end
    local camera = workspace.CurrentCamera
    local cursor = camera and A.aimCursor(camera)
    local best, bestDistance
    local fov = A.config.fov or 160
    for _, player in ipairs(A.playerList) do
        if A.isAimTarget(player) then
            local sample = A.sampleGunTarget(player, camera, true)
            if sample and sample.onScreen and cursor then
                local distance = (sample.screen - cursor).Magnitude
                if distance <= fov and (not bestDistance or distance < bestDistance) then best, bestDistance = sample, distance end
            end
        end
    end
    if not best then
        local nearest = math.huge
        for _, player in ipairs(A.playerList) do
            if A.isAimTarget(player) then
                local sample = A.sampleGunTarget(player, camera, false)
                if sample and sample.distance < nearest then best, nearest = sample, sample.distance end
            end
        end
    end
    if not best then return original end
    A.aimSample, A.aimPoint, A.aimEligible = best, best.position, true
    A.silentRedirects = (A.silentRedirects or 0) + 1
    if typeof(original) == "CFrame" then return CFrame.new(best.position) * original.Rotation end
    if typeof(original) == "Vector3" then return best.position end
    return original
end

do
    local aim = A.collectorCombatAim
    local lock = A.collectorSilentLockReady
    function A.collectorCombatAim(original, caller)
        if A.collectorCombatRole == "Sheriff" or A.collectorShootWhileCollecting then
            local player = A.collectorCombatTarget or A.collectorDefensiveTarget
            local sample = player and A.sampleGunTarget(player, workspace.CurrentCamera, false)
            if sample then
                A.aimSample, A.aimPoint, A.aimEligible = sample, sample.position, true
                if typeof(original) == "CFrame" then return CFrame.new(sample.position) * original.Rotation, true end
                if typeof(original) == "Vector3" then return sample.position, true end
            end
            return original, false
        end
        return aim(original, caller)
    end
    function A.collectorSilentLockReady(character)
        if A.Input:GetFocusedTextBox() ~= nil then return false end
        if lock(character) then return true end
        local player
        for _, candidate in ipairs(A.playerList) do
            if candidate.Character == character then player = candidate; break end
        end
        local sample = player and A.sampleGunTarget(player, workspace.CurrentCamera, false)
        if not sample then return false end
        A.aimSample, A.aimPoint, A.aimEligible, A.aimBlocked = sample, sample.position, true, false
        return true
    end
end

function A.hideKnifeRead()
    if A.knifeMarker then A.knifeMarker:Destroy() A.knifeMarker = nil end
end
function A.showKnifeRead(fromPos, aimPos, shooterPos)
    local folder = A.knifeMarker
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "qos-MM2-KnifeRead"
        folder.Parent = workspace
        A.resources[folder] = true
        local function mark(name, shape)
            local part = Instance.new("Part")
            part.Name = name
            part.Anchored = true
            part.CanCollide = false
            part.CanQuery = false
            part.CanTouch = false
            part.Material = Enum.Material.Neon
            part.Color = Color3.fromRGB(255, 236, 196)
            part.Transparency = 0.2
            part.Shape = shape
            part.Parent = folder
            return part
        end
        folder:SetAttribute("Line", true)
        A.knifeLine = mark("Line", Enum.PartType.Cylinder)
        A.knifeDot = mark("Dot", Enum.PartType.Ball)
        A.knifeMarker = folder
    end
    local delta = aimPos - fromPos
    local length = delta.Magnitude
    local dotAt = aimPos
    if length < 1.5 then
        local toward = Vector3.new(shooterPos.X - fromPos.X, 0, shooterPos.Z - fromPos.Z)
        if toward.Magnitude > 0.1 then dotAt = fromPos + toward.Unit * 1.7 + Vector3.new(0, 0.35, 0) end
        A.knifeLine.Transparency = 1
    else
        local start = fromPos + delta.Unit * 1.3
        local span = aimPos - start
        local mid = (start + aimPos) / 2
        A.knifeLine.Transparency = 0.25
        A.knifeLine.Size = Vector3.new(math.max(span.Magnitude, 0.05), 0.08, 0.08)
        A.knifeLine.CFrame = CFrame.lookAt(mid, aimPos) * CFrame.Angles(0, math.pi / 2, 0)
    end
    A.knifeDot.Size = Vector3.new(0.32, 0.32, 0.32)
    A.knifeDot.CFrame = CFrame.new(dotAt)
    A.knifeDot.Transparency = 0.05
end

function A.noteKnifeMotion(character, root)
    A.knifeReads = A.knifeReads or setmetatable({}, {__mode = "k"})
    local now = os.clock()
    local velocity = root.AssemblyLinearVelocity
    if not A.finite(velocity) or velocity.Magnitude > 120 then velocity = Vector3.zero end
    velocity = Vector3.new(velocity.X, 0, velocity.Z)
    local entry = A.knifeReads[character]
    if not entry then entry = {samples = {}}; A.knifeReads[character] = entry end
    local samples = entry.samples
    local last = samples[#samples]
    if not last or now - last.at >= 0.05 then samples[#samples + 1] = {at = now, v = velocity} end
    while samples[1] and now - samples[1].at > 0.4 do table.remove(samples, 1) end
    return entry
end
function A.knifeLeadWeight(entry)
    local samples = entry and entry.samples
    if not samples or #samples < 3 then return 0 end
    local newest = samples[#samples].v
    local speed = newest.Magnitude
    if speed < 4 then return 0 end
    local older = samples[1].v.Magnitude
    if older > 1 and speed < older * 0.55 then return 0 end
    local agree, count = 0, 0
    for i = 1, #samples do
        local sample = samples[i].v
        if sample.Magnitude > 3 then
            count = count + 1
            if sample.Unit:Dot(newest.Unit) > 0.75 then agree = agree + 1 end
        end
    end
    if count == 0 or agree / count < 0.7 then return 0 end
    return math.clamp(older > 1 and speed / older or 1, 0, 1)
end
function A.knifePrediction(weapon, origin, enemyRoot, enemyHumanoid, enemyCharacter)
    local torso = enemyCharacter:FindFirstChild("UpperTorso") or enemyCharacter:FindFirstChild("Torso") or enemyRoot
    local speed = 130
    for _, name in ipairs({"ProjectileSpeed", "ThrowVelocity"}) do
        local value = weapon and weapon:GetAttribute(name)
        if type(value) == "number" and value >= 40 and value <= 400 then speed = value; break end
    end
    local entry = A.noteKnifeMotion(enemyCharacter, enemyRoot)
    local weight = A.knifeLeadWeight(entry)
    local velocity = enemyRoot.AssemblyLinearVelocity
    if not A.finite(velocity) or velocity.Magnitude > 80 then velocity = Vector3.zero end
    if enemyHumanoid and enemyHumanoid.FloorMaterial ~= Enum.Material.Air then
        velocity = Vector3.new(velocity.X, 0, velocity.Z)
    else
        velocity = Vector3.new(velocity.X, math.clamp(velocity.Y, -40, 40), velocity.Z)
    end
    local t = math.clamp((torso.Position - origin).Magnitude / speed, 0.08, 1.2)
    for _ = 1, 4 do
        local predicted = torso.Position + velocity * (t * weight)
        local flat = Vector3.new(predicted.X - origin.X, 0, predicted.Z - origin.Z)
        t = math.clamp(math.max(flat.Magnitude, 0.01) / speed, 0.08, 1.2)
    end
    local bodyPoint = torso.Position + velocity * (t * weight)
    local lookPoint = bodyPoint + Vector3.new(0, 0.5 * workspace.Gravity * t * t, 0)
    return bodyPoint, lookPoint, weight
end
function A.faceThrow(root, aim)
    local flat = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
    if flat.Magnitude > 0.2 then root.CFrame = CFrame.lookAt(root.Position, root.Position + flat) end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local saved = camera.CFrame
    local token = {}
    A.knifeCameraToken = token
    camera.CFrame = CFrame.lookAt(camera.CFrame.Position, aim)
    A.delay(0.35, function()
        if A.knifeCameraToken == token and camera.Parent then camera.CFrame = saved end
    end)
end

function A.murdererSeekCover(root, enemyCharacter, enemyRoot)
    local move = A.movement
    if move and move.coverUntil and os.clock() < move.coverUntil and move.recoveryGoal then return true end
    local _, humanoid = A.body(A.player)
    if not humanoid then return false end
    if not move and not A.acquireMove("farm") then return false end
    move = A.movement
    if not move or move.owner ~= "farm" then return false end
    if not move.walking then
        move.walking = true
        move.walkSpeed = humanoid.WalkSpeed
        humanoid.AutoRotate = true
    end
    local torso = enemyCharacter:FindFirstChild("UpperTorso") or enemyCharacter:FindFirstChild("Torso") or enemyRoot
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {A.player.Character, enemyCharacter}
    params.RespectCanCollide = true
    local best, bestScore
    for i = 0, 15 do
        local direction = Vector3.new(math.cos(i * math.pi / 8), 0, math.sin(i * math.pi / 8))
        for _, dist in ipairs({8, 14, 20}) do
            local probe = root.Position + direction * dist
            local ground = workspace:Raycast(probe + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), params)
            if ground and ground.Normal.Y > 0.65 then
                local stand = Vector3.new(probe.X, ground.Position.Y + (root.Position.Y - A.collectorFeet(move).Y), probe.Z)
                local hidden = not A.collectorCombatVisible(stand + Vector3.new(0, 2, 0), torso.Position, enemyCharacter)
                if hidden and (stand - root.Position).Magnitude > 2 then
                    local beside = workspace:Raycast(stand, direction * 5, params) or workspace:Raycast(stand, Vector3.new(-direction.Z, 0, direction.X) * 5, params)
                    local score = (stand - enemyRoot.Position).Magnitude + (beside and 10 or 0)
                    if not bestScore or score > bestScore then best, bestScore = stand, score end
                end
            end
        end
    end
    if not best then return false end
    A.clearWalkRoute(move, true)
    move.recoveryGoal = best
    move.recoveryUntil = os.clock() + 0.7
    move.coverUntil = move.recoveryUntil
    local flat = Vector3.new(best.X - root.Position.X, 0, best.Z - root.Position.Z)
    if flat.Magnitude > 0.1 then
        move.walkDirection = flat.Unit
        humanoid:Move(flat.Unit, false)
    end
    return true
end

function A.collectorRoleStep(root)
    local role = A.role(A.player)
    local zombie = A.isZombie(A.player)
    local defensive = (A.collectorDefensiveUntil or 0) > os.clock() and A.findTool(A.player, "Gun")
    if defensive then role = "Gun holder" end
    if zombie then role = "Murderer" end
    if A.collectorBagFull() and A.collectorFullLife ~= A.player.Character then
        A.collectorFullLife = A.player.Character
        A.log("bag_full", {role = role})
        A.set("autoGun", true)
    end
    A.collectorGunTarget = nil
    if A.collectorFullLife == A.player.Character and role ~= "Murderer" then
        if A.findTool(A.player, "Gun") then role = "Gun holder"
        elseif A.config.autoGun then
            local drop = A.drop()
            A.note("Collector", drop and "Bag full. Getting the gun." or "Bag full. No gun yet.")
            if drop and not A.collectorGunPickupBusy and os.clock() >= (A.nextGunAttempt or 0) then
                if A.movement and A.movement.owner == "farm" then A.releaseMove(false) end
                A.collectorGunPickupBusy = true
                A.spawn(function()
                    local ok, err = pcall(A.grabGun)
                    A.collectorGunPickupBusy = false
                    if not ok then A.nextGunAttempt = os.clock() + 2 end
                end)
            end
            A.hideKnifeRead()
            return true
        end
    end
    if role ~= "Murderer" and role ~= "Sheriff" and role ~= "Hero" and role ~= "Gun holder" then
        if A.collectorCombatRole then A.stopCollectorCombat() end
        A.hideKnifeRead()
        return false
    end
    if A.collectorBagFull() and not A.collectorFullLife then
        A.collectorFullLife = A.player.Character
        A.log("bag_full", {role = role})
    end
    if A.collectorFullLife ~= A.player.Character and not defensive then
        if zombie then A.collectorZombieNearbyAttack(root) end
        if A.collectorCombatRole then A.stopCollectorCombat() end
        A.hideKnifeRead()
        return false
    end
    local mode = role == "Murderer" and "Murderer" or "Sheriff"
    if A.collectorCombatRole ~= mode then
        A.log("combat_start", {role = mode})
        A.collectorCombatRole = mode
    end
    local _, humanoid = A.body(A.player)
    if not humanoid then return true end
    local options = {}
    for _, player in ipairs(A.playerList) do
        if player ~= A.player and (not A.collectorShootWhileCollecting or player == A.collectorDefensiveTarget)
            and (mode == "Murderer" or A.isAimTarget(player) or (defensive and player == A.collectorDefensiveTarget))
            and (not zombie or not A.isZombie(player))
            and (A.espAlive(player) or (defensive and player == A.collectorDefensiveTarget)) then
            local _, _, enemy = A.body(player)
            if enemy and not A.collectorTargetCoolingDown(enemy) then
                local distance = (enemy.Position - root.Position).Magnitude
                if not (zombie and distance > 12) then
                    local gun = A.findTool(player, "Gun")
                    local targetRole = A.role(player)
                    local armed = gun ~= nil or targetRole == "Sheriff" or targetRole == "Hero" or targetRole == "Gun holder"
                    options[#options + 1] = {player = player, enemy = enemy, distance = distance, armed = armed, role = targetRole}
                end
            end
        end
    end
    local pool = options
    if mode == "Murderer" then
        local sheriffs, armedOnly = {}, {}
        for _, item in ipairs(options) do
            if item.role == "Sheriff" then sheriffs[#sheriffs + 1] = item end
            if item.armed then armedOnly[#armedOnly + 1] = item end
        end
        if #sheriffs > 0 then pool = sheriffs elseif #armedOnly > 0 then pool = armedOnly end
    end
    local chosen, distance, chosenArmed
    local best = math.huge
    for _, item in ipairs(pool) do
        local priority = item.distance * ((item.player == A.collectorCombatTarget) and 0.9 or 1)
        if priority < best then
            chosen, distance, chosenArmed, best = item.player, item.distance, item.armed, priority
        end
    end
    if A.collectorCombatTarget ~= chosen then A.collectorCombatTarget = chosen end
    A.collectorCombatTargetArmed = chosen and chosenArmed or false
    A.collectorCombatJump(humanoid)
    if not chosen then
        A.hideKnifeRead()
        if defensive then return false end
        if A.movement and A.movement.owner == "farm" then A.clearWalkRoute(A.movement) end
        A.note("Collector", "No target")
        return true
    end
    local weapon = A.findTool(A.player, mode == "Murderer" and "Knife" or "Gun")
    if not weapon and zombie then
        A.collectorCombatWeapon = nil
        A.hideKnifeRead()
        A.note("Collector", "Chasing")
        return false
    end
    if not weapon then
        A.hideKnifeRead()
        A.note("Collector", "No weapon")
        return true
    end
    A.collectorCombatWeapon = weapon
    A.ensureWeaponHooks()
    local character, _, enemy = A.body(chosen)
    if not enemy then return false end
    local enemyHumanoid = character:FindFirstChildOfClass("Humanoid")
    local point = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or enemy).Position
    local handle = weapon:FindFirstChild("Handle")
    local origin = handle and handle:IsA("BasePart") and handle.Position or root.Position
    if mode == "Sheriff" then origin = A.gunOrigin() or origin end
    if mode == "Sheriff" and A.config.silentGunAim then
        A.aimStep()
        if A.collectorSilentLockReady(character) then point = A.aimSample.position end
    end
    local visible
    if mode == "Sheriff" and A.collectorSilentLockReady(character) then visible = A.weaponVisible(origin, point, character)
    else visible = A.collectorCombatVisible(origin, point, character) end
    local now = os.clock()
    local function holdKnife(equip)
        if mode ~= "Murderer" then
            if weapon.Parent ~= A.player.Character then
                humanoid:EquipTool(weapon)
                A.combatEquippedAt = now
            end
            return
        end
        if equip then
            if weapon.Parent ~= A.player.Character then
                humanoid:EquipTool(weapon)
                A.combatEquippedAt = now
            end
        elseif weapon.Parent == A.player.Character then
            humanoid:UnequipTools()
        end
    end
    if mode == "Murderer" and not zombie then
        local bodyPoint = point
        if visible then
            local lookPoint, weight
            bodyPoint, lookPoint, weight = A.knifePrediction(weapon, origin, enemy, enemyHumanoid, character)
            A.showKnifeRead(point, bodyPoint, root.Position)
            A.knifeLookPoint = lookPoint
        else
            A.hideKnifeRead()
            A.noteKnifeMotion(character, enemy)
            if chosenArmed then
                holdKnife(false)
                if A.murdererSeekCover(root, character, enemy) then return true end
            end
        end
    else
        A.hideKnifeRead()
    end
    if not visible then A.gunReadySince = nil end
    local muzzleClear = mode ~= "Sheriff" or A.collectorGunClearance(weapon, character, point, origin)
    if mode == "Sheriff" and not muzzleClear and not A.collectorMuzzleEscape and not A.collectorRecoveryActive(A.movement) then
        local goal = A.collectorMuzzleEscapeGoal(root, character, point, origin)
        if goal then A.collectorMuzzleEscape = {goal = goal, untilAt = now + 0.5} end
    elseif mode == "Sheriff" and muzzleClear then A.collectorMuzzleEscape = nil end
    local shotReady = mode ~= "Sheriff" or (visible and A.collectorGunShotReady(weapon, character, point, origin, muzzleClear))
    if weapon.Parent == A.player.Character and not A.combatEquippedAt then A.combatEquippedAt = now - 1 end
    if mode == "Murderer" then
        local wantStab = visible and distance <= 4.5
        local wantThrow = (not zombie) and visible and distance > 4.5 and distance < 90 and now >= (A.nextCombatThrow or 0)
        holdKnife(wantStab or wantThrow)
        if weapon.Parent == A.player.Character and weapon.Enabled and now - (A.combatEquippedAt or now) >= 0.12 then
            if wantStab and now >= (A.nextCombatAttack or 0) then
                A.nextCombatAttack = now + 0.7
                A.lastCollectorStab = now
                local flat = Vector3.new(enemy.Position.X - root.Position.X, 0, enemy.Position.Z - root.Position.Z)
                if flat.Magnitude > 0.2 then root.CFrame = CFrame.lookAt(root.Position, root.Position + flat) end
                pcall(function() weapon:Activate() end)
            elseif wantThrow then
                A.nextCombatThrow = now + 1.15
                local input = A.player.PlayerGui:FindFirstChild("InputContext")
                local context = input and input:FindFirstChild("GameplayContext")
                local action = context and context:FindFirstChild("Throw")
                pcall(function()
                    assert(weapon:GetAttribute("Disabled") ~= true, "Knife disabled")
                    A.faceThrow(root, A.knifeLookPoint or point)
                    A.collectorNativeThrow(weapon, action)
                end)
            end
        end
    else
        local wasEquipped = weapon.Parent == A.player.Character
        if not wasEquipped then
            humanoid:EquipTool(weapon)
            A.combatEquippedAt = now
        end
        if wasEquipped and weapon.Enabled and visible and muzzleClear and shotReady
            and now - (A.combatEquippedAt or now) >= (defensive and 0.1 or 0.12)
            and now >= (A.nextCombatAttack or 0) then
            A.nextCombatAttack = now + 1.2
            pcall(function() weapon:Activate() end)
        end
    end
    if mode == "Sheriff" then
        if not A.movement then A.acquireMove("farm") end
        local move = A.movement
        if move and move.owner == "farm" then
            if not move.walking then move.walking = true; move.walkSpeed = humanoid.WalkSpeed end
            if A.collectorRangedStep(move) then return true end
        end
    end
    return false
end

do
    local esp = A.espStepUnsafe
    function A.espStepUnsafe()
        esp()
        for player, entry in pairs(A.esp) do
            if entry.highlight then
                entry.highlight.FillTransparency = 0.92
                entry.highlight.OutlineTransparency = 0
            end
            if entry.billboard and entry.text and entry.lastRole then
                entry.billboard.Size = UDim2.fromOffset(180, 28)
                entry.text.TextSize = 15
                entry.text.TextStrokeTransparency = 0.1
                entry.text.Text = player.Name .. "  " .. entry.lastRole
            end
        end
    end
    local stop = A.stopCollectorCombat
    function A.stopCollectorCombat()
        A.hideKnifeRead()
        return stop()
    end
    local unload = A.Unload
    function A.Unload(...)
        A.hideKnifeRead()
        return unload(...)
    end
end

A.mountUI()
A.connect(A.Input.InputBegan, function(input, processed)
    if input.KeyCode == Enum.KeyCode.End then A.Unload();return end
    if processed or A.Input:GetFocusedTextBox() then return end
    if A.movement and A.movement.walking and (input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.A
        or input.KeyCode == Enum.KeyCode.S or input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Space) then
        A.set("farm", false); A.note("Collector", "Stopped for manual movement")
    end
    if input.KeyCode == Enum.KeyCode.RightBracket then A.window.Visible = not A.window.Visible end
    if input.KeyCode == Enum.KeyCode.End then A.Unload() end
end)
A.connect(A.Players.PlayerRemoving, function(p) A.clearESP(p);if A.tracers and A.tracers[p]then A.tracers[p]:Destroy();A.tracers[p]=nil end end)
A.connect(A.player.CharacterRemoving, function()
    A.log("character_removed",{});A.stopCollectorCombat()
    A.releaseMove(false); A.lastStable = nil; A.aimPoint = nil
end)
A.connect(A.player.CharacterAdded, function()
    A.log("character_added",{});A.stopCollectorCombat()
    A.lastStable = nil; A.lastScan = 0; A.coinSkip = setmetatable({}, { __mode = "k" }); A.farmTarget = nil
end)
A.connect(A.Run.Stepped, function()
    if not A.alive or (not A.config.antiFling and not A.movement) then return end
    local ok, err = pcall(function() A.noclipLocal(); A.antiFlingStep() end)
    if not ok then A.note("Physics", tostring(err)) end
end)
A.elapsed = 0
A.connect(A.Run.Heartbeat, function(dt)
    if not A.alive then return end
    local ok, err = xpcall(function()
        A.logStep()
        if A.config.farm then
            A.farmElapsed=(A.farmElapsed or 0)+dt
            if A.farmElapsed>=0.05 then local elapsed=A.farmElapsed; A.farmElapsed=0; A.farmStep(elapsed) end
        end
        A.elapsed = A.elapsed + dt
        if A.elapsed >= 0.15 then
            A.elapsed = 0; A.espStep(); A.refreshTracers()
        end
    end,function(err)return tostring(err).."\n"..debug.traceback()end)
    if not ok then
        A.log("runtime_error",{error=err})
        if A.movement and A.movement.owner == "farm" then A.set("farm", false) end
        A.note("Runtime", tostring(err))
    end
end)
A.Run:BindToRenderStep("qos-MM2-Tracers",Enum.RenderPriority.Camera.Value+2,function()
    if A.alive and A.tracerTargets and #A.tracerTargets>0 then A.tracerStep() end
end)
A.Run:BindToRenderStep("qos-MM2-CombatCamera",Enum.RenderPriority.Camera.Value+3,function(dt)
    if A.alive then local ok,err=pcall(A.collectorCameraStep,dt);if not ok then A.log("camera_error",{error=err})end end
end)
A.Run:BindToRenderStep("qos-MM2-Aiming", Enum.RenderPriority.Camera.Value + 1, function()
    if not A.alive then return end
    if not (A.config.cameraAim or A.config.silentGunAim or A.config.showFov or A.fovCircle.Visible) then return end
    local ok, err = pcall(A.aimStep)
    if not ok then A.aimPoint = nil; A.note("Aim", tostring(err)) end
end)
A.Run:BindToRenderStep("qos-MM2-JumpHold",Enum.RenderPriority.Input.Value+2,function()
    if not A.alive then return end
    local _,humanoid=A.body(A.player)
    if humanoid then A.collectorCombatJump(humanoid)end
end)
A.Run:BindToRenderStep("qos-MM2-Safety",Enum.RenderPriority.Input.Value,function()
    if not A.alive or not A.config.farm or not A.collectorActiveRound
        or A.isZombie(A.player)or A.role(A.player)=="Murderer"then return end
    local _,_,root=A.body(A.player)
    if not root then return end
    local ok,err=pcall(A.collectorEmergencyTeleport,root)
    if not ok then A.log("emergency_monitor_error",{error=err})end
end)
A.Run:BindToRenderStep("qos-MM2-Walking", Enum.RenderPriority.Input.Value + 1, function(dt)
    if not A.alive then return end
    if not A.movement or not A.movement.walking then return end
    local ok, err = pcall(A.walkInput,dt)
    if not ok then A.set("farm", false); A.note("Collector", tostring(err)) end
end)
A.spawn(function()
    while A.alive do
        if A.config.autoGun then
            local ok, err = pcall(A.collectorAutoGunStep)
            if not ok and A.alive then
                if A.movement and A.movement.owner == "gun" then A.releaseMove(true) end
                A.note("Gun pickup", tostring(err))
            end
        end
        if A.alive then A.resize() end
        task.wait(A.config.autoGun and 0.08 or 0.8)
    end
end)
print("[qos-MM2] v"..A.version.." loaded. ] = menu; End = unload.")
