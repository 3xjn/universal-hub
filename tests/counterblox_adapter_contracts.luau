local roblox = require("@lune/roblox")
CFrame = roblox.CFrame
Color3 = roblox.Color3
Vector3 = roblox.Vector3

local Counterblox = require("../games/Counterblox")

assert(Counterblox.match({ gameId = 7633926880, placeId = 0 }) == 100)
assert(Counterblox.match({ gameId = 0, placeId = 114234929420007 }) == 200)
assert(Counterblox.match({ gameId = 0, placeId = 0 }) == 0)

assert(Counterblox.classifyWeapon({
    Bullet = {},
    IsDestroyed = false,
    Name = "Any skin name",
}) == "Gun", "Gun detection must use behavior, not tool names")
assert(Counterblox.classifyWeapon({
    IsDestroyed = false,
    Properties = { Range = 8 },
    shoot = function() end,
}) == "Knife")
assert(Counterblox.classifyWeapon({ IsDestroyed = true, Bullet = {} }) == nil)

local wall = {}
local targetPart = {}
local origin = Vector3.new(0, 0, 0)
local targetPosition = Vector3.new(0, 0, -50)
local redirected, accepted = Counterblox.redirectBullet({
    Direction = Vector3.new(1, 0, 0),
    Hits = {},
    Origin = origin,
}, {
    part = targetPart,
    position = targetPosition,
}, {
    Properties = {
        Penetration = 10,
        Range = 500,
    },
}, {
    cast = function(castOrigin, direction, _params, ignore)
        assert(castOrigin == origin and math.round(direction.Magnitude) == 500)
        assert(ignore == "ignore-list")
        return {
            instance = wall,
            position = Vector3.new(0, 0, -10),
        }
    end,
    castThrough = function(castOrigin, direction, penetration, ignore)
        assert(castOrigin.Z < -9.99 and math.round(direction.Magnitude) == 500)
        assert(penetration == 10 and ignore == "ignore-list")
        return {
            {
                instance = wall,
                material = { Name = "Concrete" },
                normal = Vector3.new(0, 0, 1),
                position = Vector3.new(0, 0, -10),
            },
            {
                instance = wall,
                material = { Name = "Concrete" },
                normal = Vector3.new(0, 0, -1),
                position = Vector3.new(0, 0, -12),
            },
            {
                instance = targetPart,
                material = { Name = "Plastic" },
                normal = Vector3.new(0, 0, 1),
                position = targetPosition,
            },
        }
    end,
    getIgnore = function()
        return "ignore-list"
    end,
})

assert(accepted == true)
assert(redirected.Direction == Vector3.new(0, 0, -1))
assert(#redirected.Hits == 3)
assert(redirected.Hits[1].Exit == false and redirected.Hits[2].Exit == true)
assert(redirected.Hits[3].Instance == targetPart)

local originalResult = {
    Direction = Vector3.new(1, 0, 0),
    Hits = {},
    Origin = origin,
}
local rejected, rejectedAccepted = Counterblox.redirectBullet(originalResult, {
    part = targetPart,
    position = targetPosition,
}, {
    Properties = {
        Penetration = 10,
        Range = 500,
    },
}, {
    cast = function()
        return {
            instance = wall,
            position = Vector3.new(0, 0, -10),
        }
    end,
    castThrough = function()
        return {
            {
                instance = wall,
                position = Vector3.new(0, 0, -10),
            },
            {
                instance = wall,
                position = Vector3.new(0, 0, -12),
            },
        }
    end,
    getIgnore = function()
        return "ignore-list"
    end,
})
assert(rejectedAccepted == false, "A penetrated wall is not an accepted path unless the target is reached")
assert(rejected == originalResult, "Rejected penetration must preserve the game's original raycast")

local inventoryController = {}
local bulletModule = {
    _performRaycast = function() end,
    getTrueSpread = function()
        return 12
    end,
}
local currentCamera = {
    CFrame = roblox.CFrame.new(),
}
local viewmodelPart = {
    LocalTransparencyModifier = 0,
    Parent = {},
    IsA = function(_, className)
        return className == "BasePart"
    end,
}
local viewmodelModel = {
    Name = "AK-47",
    GetDescendants = function()
        return { viewmodelPart }
    end,
    IsA = function(_, className)
        return className == "Model"
    end,
}
function currentCamera:GetChildren()
    return { viewmodelModel }
end
local meleeAimLook
local meleeModule = {
    shoot = function()
        meleeAimLook = currentCamera.CFrame.LookVector
    end,
}
local cameraController = {
    updateCamera = function(cameraFrame)
        currentCamera.CFrame = cameraFrame or roblox.CFrame.new()
    end,
    weaponKick = function() end,
}
local characterModule = {
    GetMaxSpeed = function()
        return 6
    end,
}
local weaponNewArguments
local weaponComponentModule = {
    new = function(...)
        weaponNewArguments = table.pack(...)
        return {
            Bullet = {
                Properties = {
                    Penetration = 10,
                    Range = 500,
                },
            },
            Float = weaponNewArguments[7],
            IsDestroyed = false,
            Name = weaponNewArguments[5],
            Player = weaponNewArguments[1],
            Skin = weaponNewArguments[6],
            StatTrack = weaponNewArguments[8],
            Viewmodel = {
                IsEquipped = true,
                destroy = function() end,
            },
        }
    end,
}
local viewmodelEquipCalls = 0
local viewmodelNewArguments
local viewmodelConstructCalls = {}
local viewmodelModule = {
    construct = function(self, character)
        local equippedGloves = character:GetAttribute("EquippedGloves")
        table.insert(viewmodelConstructCalls, {
            equippedGloves = equippedGloves,
            player = self.Player,
        })
        return equippedGloves
    end,
    new = function(component, name, skin)
        viewmodelNewArguments = {
            component = component,
            name = name,
            skin = skin,
        }
        assert(component.Skin == skin)
        return {
            IsEquipped = false,
            ModelName = name,
            destroy = function() end,
            equip = function(self)
                self.IsEquipped = true
                viewmodelEquipCalls += 1
            end,
        }
    end,
}
weaponComponentModule.Classes = {
    Viewmodel = viewmodelModule,
}
local skinsModule = {
    GetGloves = function(name, skin, wear)
        return {
            name = name,
            skin = skin,
            wear = wear,
        }
    end,
    GetAllSkinsForWeapon = function(name)
        if name == "AK-47" then
            return {
                {
                    floatRange = { min = 0, max = 0.15 },
                    name = "AK-47",
                    skin = "PinPoint",
                    supportsStatTrak = true,
                },
            }
        elseif name == "Karambit" then
            return {
                {
                    floatRange = { min = 0, max = 0.15 },
                    name = "Karambit",
                    skin = "Fade",
                    supportsStatTrak = true,
                },
            }
        elseif name == "T Knife" then
            return {}
        elseif name == "CT Glove" then
            return {}
        elseif name == "Driver Gloves" then
            return {
                {
                    floatRange = { min = 0.1, max = 0.8 },
                    name = "Driver Gloves",
                    skin = "Crimson Weave",
                    supportsStatTrak = false,
                },
            }
        end
        error("unexpected weapon skin request: " .. tostring(name))
    end,
}
local flashCalls = 0
local flashCancelCalls = 0
local flashEffect = {
    CancelFlash = function()
        flashCancelCalls += 1
    end,
    Flash = function()
        flashCalls += 1
        return true
    end,
}
local smokeCreateCalls = 0
local smokeDestroyAllCalls = 0
local voxelSmoke = {
    Create = function()
        smokeCreateCalls += 1
    end,
    DestroyAll = function()
        smokeDestroyAllCalls += 1
    end,
}
local getRayIgnore = function()
    return {}
end
local getWeaponProperties = function(name)
    if name == "T Knife" or name == "Karambit" then
        return { Class = "Melee" }
    elseif name == "CT Glove" or name == "Driver Gloves" then
        return { Class = "Glove" }
    end
    return { Class = "Rifle" }
end
local gameRaycastFirst
local gameRaycastHits = {}
local gameRaycast = {
    cast = function()
        return gameRaycastFirst
    end,
    castThrough = function()
        return gameRaycastHits
    end,
}
local replicatedStorage = {
    Assets = {
        Weapons = {
            GetChildren = function()
                return {
                    { Name = "CT Glove" },
                    { Name = "Driver Gloves" },
                    { Name = "Karambit" },
                    { Name = "T Knife" },
                }
            end,
        },
    },
    Classes = {
        Character = characterModule,
        WeaponComponent = weaponComponentModule,
    },
    Controllers = {
        CameraController = cameraController,
        InventoryController = inventoryController,
    },
    Components = {
        Common = {
            GetRayIgnore = getRayIgnore,
            GetWeaponProperties = getWeaponProperties,
            VFXLibary = {
                CreateVoxelSmoke = voxelSmoke,
                FlashEffect = flashEffect,
            },
        },
        Melee = meleeModule,
        Weapon = {
            Classes = {
                Bullet = bulletModule,
            },
        },
    },
    Database = {
        Components = {
            Libraries = {
                Skins = skinsModule,
            },
        },
    },
    Shared = {
        Raycast = gameRaycast,
    },
}
local localTeam = "T"
local localPlayer = {
    Character = nil,
    GetAttribute = function(_, name)
        if name == "Team" then
            return localTeam
        elseif name == "CurrentEquipped" then
            return '{"Name":"AK-47","Type":"Gun"}'
        end
        return nil
    end,
}
local existingViewmodelDestroyCalls = 0
local existingLiveComponent = {
    Float = 0,
    IsDestroyed = false,
    Name = "AK-47",
    Player = localPlayer,
    Skin = "Stock",
    StatTrack = false,
    Viewmodel = {
        IsEquipped = false,
        destroy = function()
            existingViewmodelDestroyCalls += 1
        end,
    },
}
local gameMode = "Competitive"
local serverGameMode = "Competitive"
local renderCallback
local lateRenderCallback
local lateRenderName
local lateRenderPriority
local encodedGloveValue
local services = {
    Players = {
        LocalPlayer = localPlayer,
    },
    HttpService = {
        JSONDecode = function()
            return {
                Name = "AK-47",
                Type = "Gun",
            }
        end,
        JSONEncode = function(_, value)
            encodedGloveValue = value
            return "encoded-glove-override"
        end,
    },
    ReplicatedStorage = replicatedStorage,
    RunService = {
        RenderStepped = {
            Connect = function(_, callback)
                renderCallback = function(...)
                    callback(...)
                    if lateRenderCallback then
                        lateRenderCallback(...)
                    end
                end
                return {
                    Disconnect = function() end,
                }
            end,
        },
        BindToRenderStep = function(_, name, priority, callback)
            lateRenderName = name
            lateRenderPriority = priority
            lateRenderCallback = callback
        end,
        UnbindFromRenderStep = function(_, name)
            assert(name == lateRenderName)
            lateRenderCallback = nil
        end,
    },
    UserInputService = {
        GetMouseLocation = function()
            return {}
        end,
        IsKeyDown = function()
            return true
        end,
    },
    Workspace = {
        CurrentCamera = currentCamera,
        GetAttribute = function(_, name)
            if name == "Gamemode" then
                return gameMode
            end
            if name == "ServerGamemode" then
                return serverGameMode
            end
            return nil
        end,
        Raycast = function() end,
        Spherecast = function() end,
    },
}
local requiredModules = {}
local hookImplementations = {}
local adapterState = {
    activeWeapon = "AK-47",
    settings = {
        fullScreenAim = false,
        noSpread = true,
        silentAim = true,
        triggerBot = true,
        bhop = false,
        knifeAura = false,
        microStep = false,
        noFlash = false,
        spinBot = false,
        noSmoke = false,
        noWeaponSlow = false,
        fov = 180,
        gloveOverride = false,
        gloveColorOverride = false,
        skinOverrides = {},
    },
}
local clickCount = 0
local inputCaptured = false
local movementDirection = Vector3.new(1, 0, 0)
local thirdPersonStates = {}
local nearestTargetPosition = Vector3.new(0, 0, -10)
local nearestTargetVisible = true
local moduleValues = {
    [bulletModule] = bulletModule,
    [cameraController] = cameraController,
    [characterModule] = characterModule,
    [flashEffect] = flashEffect,
    [getRayIgnore] = getRayIgnore,
    [gameRaycast] = gameRaycast,
    [meleeModule] = meleeModule,
    [skinsModule] = skinsModule,
    [viewmodelModule] = viewmodelModule,
    [weaponComponentModule] = weaponComponentModule,
    [voxelSmoke] = voxelSmoke,
}

game = {
    GetService = function(_, name)
        return services[name]
    end,
}
getrenv = function()
    return {
        require = function(module)
            table.insert(requiredModules, module)
            return assert(moduleValues[module], "unexpected game module requirement")
        end,
    }
end

local initialized, adapter = pcall(Counterblox.new, {
    click = function()
        clickCount += 1
    end,
    gcObjects = function()
        return { existingLiveComponent }
    end,
    hookFunction = function(target, replacement)
        hookImplementations[target] = replacement
        return target
    end,
    isInputCaptured = function()
        return inputCaptured
    end,
    isJumpHeld = function()
        return true
    end,
    movementDirection = function()
        return movementDirection
    end,
    requireModule = function(module)
        table.insert(requiredModules, module)
        return assert(moduleValues[module], "unexpected game module requirement")
    end,
    oh = {
        targeting = {
            nearestPlayer = function(options)
                adapterState.lastNearestOptions = options
                return {
                    player = {},
                    part = targetPart,
                    position = nearestTargetPosition,
                    visible = nearestTargetVisible,
                }
            end,
            observePlayers = function()
                return {}
            end,
        },
    },
    render = function() end,
    restoreFunction = function() end,
    settingsChanged = function()
        adapterState.settingsChanged = (adapterState.settingsChanged or 0) + 1
    end,
    setThirdPerson = function(enabled)
        table.insert(thirdPersonStates, enabled)
    end,
    store = {
        Get = function()
            return adapterState
        end,
        Patch = function(patch)
            local function merge(target, source)
                for key, value in pairs(source) do
                    if type(value) == "table" and type(target[key]) == "table" then
                        merge(target[key], value)
                    else
                        target[key] = value
                    end
                end
            end
            merge(adapterState, patch)
        end,
    },
})

assert(initialized, "Counterblox adapter must initialize without requiring InventoryController: " .. tostring(adapter))
assert(
    lateRenderName ~= nil and lateRenderPriority >= 2000,
    "Spin Bot must run after Counterblox's own character rotation step"
)
local sameTeamPlayer = {
    GetAttribute = function(_, name)
        if name == "Team" then
            return localTeam
        end
        return nil
    end,
}
local livingCharacter = {
    GetAttribute = function(_, name)
        if name == "Dead" then
            return false
        end
        return nil
    end,
    FindFirstChildOfClass = function(_, className)
        if className == "Humanoid" then
            return { Health = 100 }
        end
        return nil
    end,
}
assert(adapter.isOpponent(sameTeamPlayer, livingCharacter) == false, "Team modes must exclude allies")
gameMode = "Deathmatch"
assert(
    adapter.isOpponent(sameTeamPlayer, livingCharacter) == true,
    "Deathmatch must treat every other living player as an opponent even when teams match"
)
currentCamera.CameraSubject = {
    IsDescendantOf = function(_, ancestor)
        return ancestor == livingCharacter
    end,
}
assert(
    adapter.isOpponent(sameTeamPlayer, livingCharacter) == false,
    "ESP must exclude the character currently followed by the spectating camera"
)
currentCamera.CameraSubject = nil
gameMode = "Competitive"
assert(
    hookImplementations[bulletModule.getTrueSpread],
    "No Spread must hook Bullet.getTrueSpread, the value consumed before raycast"
)
adapter.selectTarget(false)
assert(adapterState.lastNearestOptions.maxScreenDistance == 180)
adapterState.settings.fullScreenAim = true
adapter.selectTarget(false)
assert(
    adapterState.lastNearestOptions.maxScreenDistance == nil,
    "Fullscreen aim must remove only the screen-distance constraint"
)
adapterState.settings.fullScreenAim = false

assert(hookImplementations[weaponComponentModule.new], "Skin changer must hook WeaponComponent.new")
assert(
    hookImplementations[viewmodelModule.construct],
    "Glove changer must hook viewmodel construction where the owning player is available"
)
assert(
    hookImplementations[skinsModule.GetGloves] == nil,
    "Glove changer must not hook global GetGloves because that leaks the override to every player"
)
adapter:cycleSkin(1)
assert(adapterState.settings.skinOverrides["AK-47"].skin == "PinPoint")
assert(
    existingLiveComponent.Viewmodel.ModelName == "AK-47"
        and existingLiveComponent.Viewmodel.IsEquipped == true
        and existingViewmodelDestroyCalls == 1,
    "Changing a cosmetic must immediately rebuild the already-live equipped viewmodel"
)
local component = hookImplementations[weaponComponentModule.new](
    localPlayer,
    "identifier",
    "id",
    "Primary",
    "AK-47",
    "Stock",
    0,
    false,
    nil,
    nil,
    nil,
    nil
)
assert(weaponNewArguments[6] == "PinPoint", "Weapon construction must receive the selected skin")
adapter:setWear(1)
assert(adapterState.settings.skinOverrides["AK-47"].wear == 0.15)
adapter:toggleStatTrak()
assert(adapterState.settings.skinOverrides["AK-47"].statTrak == true)
assert(component.Viewmodel.IsEquipped == true and viewmodelEquipCalls > 0)
adapter:resetSkin()
assert(adapterState.settings.skinOverrides["AK-47"].skin == "Stock")
assert(adapterState.settingsChanged == 4, "Every cosmetic change must request per-game persistence")

adapterState.activeWeapon = "T Knife"
adapter:cycleSkin(1)
local knifeOverride = adapterState.settings.skinOverrides["T Knife"]
assert(knifeOverride.weapon == "Karambit", "Stock knives must cycle into other melee weapon families")
assert(knifeOverride.skin == "Stock")
local knifeComponent = hookImplementations[weaponComponentModule.new](
    localPlayer,
    "knife-identifier",
    "knife-id",
    3,
    "T Knife",
    "Stock",
    0,
    false,
    nil,
    nil,
    nil,
    nil
)
assert(weaponNewArguments[5] == "T Knife", "Knife cosmetics must preserve the server-backed weapon identity")
assert(knifeComponent.Name == "T Knife")
assert(viewmodelNewArguments.name == "Karambit" and viewmodelNewArguments.skin == "Stock")
adapterState.activeWeapon = "AK-47"

adapter:cycleGlove(1)
assert(adapterState.settings.gloveOverride.weapon == "CT Glove")
assert(adapterState.settings.gloveOverride.skin == "Stock")
local gloveAttribute = "original-gloves"
local gloveCharacter = {
    GetAttribute = function(_, name)
        assert(name == "EquippedGloves")
        return gloveAttribute
    end,
    SetAttribute = function(_, name, value)
        assert(name == "EquippedGloves")
        gloveAttribute = value
    end,
}
local localConstructResult = hookImplementations[viewmodelModule.construct](
    { Player = localPlayer },
    gloveCharacter,
    {}
)
assert(
    localConstructResult == "encoded-glove-override"
        and encodedGloveValue.Name == "CT Glove"
        and encodedGloveValue.Skin == "Stock",
    "Local viewmodel construction must receive the selected glove override"
)
assert(gloveAttribute == "original-gloves", "Local glove attribute must be restored after construction")
local foreignPlayer = {}
local foreignConstructResult = hookImplementations[viewmodelModule.construct](
    { Player = foreignPlayer },
    gloveCharacter,
    {}
)
assert(foreignConstructResult == "original-gloves")
assert(
    viewmodelConstructCalls[#viewmodelConstructCalls].player == foreignPlayer
        and viewmodelConstructCalls[#viewmodelConstructCalls].equippedGloves == "original-gloves",
    "Other players' viewmodels must retain their own equipped gloves"
)
adapter:cycleGlove(1)
adapter:cycleGlove(1)
assert(adapterState.settings.gloveOverride.weapon == "Driver Gloves")
assert(adapterState.settings.gloveOverride.skin == "Crimson Weave")
adapter:setGloveWear(1)
assert(adapterState.settings.gloveOverride.wear == 0.8)
local appearanceDestroyed = false
local gloveAppearance = {
    Destroy = function()
        appearanceDestroyed = true
    end,
    IsA = function(_, className)
        return className == "SurfaceAppearance"
    end,
}
local glovePart = {
    Color = Color3.new(),
    Name = "Glove",
    TextureID = "rbxassetid://texture",
    GetDescendants = function()
        return { gloveAppearance }
    end,
    IsA = function(_, className)
        return className == "BasePart" or className == "MeshPart"
    end,
}
local gloveModel = {
    GetDescendants = function()
        return { glovePart }
    end,
}
adapter:setGloveColor({ r = 0.2, g = 0.4, b = 0.6 })
hookImplementations[viewmodelModule.construct](
    { Player = localPlayer, Model = gloveModel },
    gloveCharacter,
    {}
)
assert(adapterState.settings.gloveColorOverride.g == 0.4)
assert(glovePart.Color == Color3.new(0.2, 0.4, 0.6))
assert(glovePart.TextureID == "" and appearanceDestroyed == true)
adapter:resetGlove()
assert(adapterState.settings.gloveOverride == false)
assert(adapterState.settings.gloveColorOverride == false)
local gameGloves = skinsModule.GetGloves("T Glove", "Stock", 0.2)
assert(gameGloves.name == "T Glove" and gameGloves.skin == "Stock" and gameGloves.wear == 0.2)

assert(hookImplementations[bulletModule.getTrueSpread]({}) == 0)
adapterState.settings.noSpread = false
assert(hookImplementations[bulletModule.getTrueSpread]({}) == 12)
assert(hookImplementations[flashEffect.Flash], "No Flash must hook the centralized FlashEffect.Flash seam")
assert(hookImplementations[voxelSmoke.Create], "No Smoke must hook the centralized voxel smoke Create seam")
assert(hookImplementations[characterModule.GetMaxSpeed], "No Weapon Slow must hook Character.GetMaxSpeed")
adapterState.settings.noFlash = true
assert(hookImplementations[flashEffect.Flash]({}) == false)
assert(flashCalls == 0, "No Flash must block the centralized flash effect")
adapterState.settings.noFlash = false
assert(hookImplementations[flashEffect.Flash]({}) == true and flashCalls == 1)
adapterState.settings.noSmoke = true
hookImplementations[voxelSmoke.Create]({})
assert(smokeCreateCalls == 0, "No Smoke must block voxel smoke creation")
adapterState.settings.noSmoke = false
hookImplementations[voxelSmoke.Create]({})
assert(smokeCreateCalls == 1)
adapterState.settings.noWeaponSlow = true
assert(
    hookImplementations[characterModule.GetMaxSpeed]({
        IsClimbing = false,
        IsCrouching = false,
        IsJumping = false,
        IsWalking = false,
    }) == 20,
    "No Weapon Slow must lift a positive movement result to unencumbered run speed"
)
adapterState.settings.noWeaponSlow = false
assert(hookImplementations[characterModule.GetMaxSpeed]({}) == 6)
adapterState.settings.spinBot = true
assert(
    hookImplementations[characterModule.GetMaxSpeed]({
        IsClimbing = false,
        IsCrouching = true,
        IsJumping = false,
        IsWalking = true,
    }) == 20,
    "Spin Bot must keep full ground speed while the character is crouched"
)
adapterState.settings.spinBot = false
assert(renderCallback, "Counterblox adapter must connect its render loop")
renderCallback()
assert(clickCount == 0, "Trigger Bot must not click while LocalPlayer.Character is nil")
adapterState.settings.noFlash = true
adapterState.settings.noSmoke = true
renderCallback()
renderCallback()
assert(flashCancelCalls == 1, "No Flash must cancel an active effect only on its enable transition")
assert(smokeDestroyAllCalls == 1, "No Smoke must clear active clouds only on its enable transition")

local root = {
    AssemblyAngularVelocity = Vector3.new(0, 0, 0),
    AssemblyLinearVelocity = Vector3.new(0, 0, 0),
    CFrame = roblox.CFrame.new(),
    Position = Vector3.new(0, 0, 0),
}
local rootJoint = {
    C0 = roblox.CFrame.new(),
    Part0 = root,
    Part1 = {},
    Transform = roblox.CFrame.new(),
    IsA = function(_, className)
        return className == "Motor6D"
    end,
}
local characterPart = {
    LocalTransparencyModifier = 1,
    Parent = {},
    IsA = function(_, className)
        return className == "BasePart"
    end,
}
local humanoid = {
    AutoRotate = true,
    FloorMaterial = {
        Name = "Concrete",
    },
    Health = 100,
    Jump = false,
    MoveDirection = Vector3.new(1, 0, 0),
    WalkSpeed = 16,
}
local character = {
    GetDescendants = function()
        return { rootJoint, characterPart }
    end,
    GetAttribute = function()
        return false
    end,
    FindFirstChild = function(_, name)
        if name == "HumanoidRootPart" then
            return root
        end
        return nil
    end,
    FindFirstChildOfClass = function(_, className)
        if className == "Humanoid" then
            return humanoid
        end
        return nil
    end,
}
localPlayer.Character = character
adapterState.settings.triggerBot = true
adapterState.settings.silentAim = true
adapterState.settings.wallbang = true
nearestTargetVisible = false
gameRaycastFirst = {
    instance = wall,
    position = Vector3.new(0, 0, -2),
}
gameRaycastHits = {}
local clicksBeforeRejectedWallbang = clickCount
renderCallback(0.016)
assert(
    clickCount == clicksBeforeRejectedWallbang,
    "Trigger Bot must not fire a blocked target when the game's penetration path cannot reach it"
)

adapterState.settings.silentAim = false
adapterState.settings.wallbang = false
nearestTargetVisible = true
inputCaptured = true
renderCallback(0.016)
assert(
    clickCount == clicksBeforeRejectedWallbang + 1,
    "Trigger Bot must select an eligible FOV target without requiring mouse hover or menu focus"
)
inputCaptured = false
hookImplementations[bulletModule._performRaycast](component.Bullet, 0)

component.Name = "Skinned AK-47"
adapterState.settings.silentAim = true
adapterState.settings.wallbang = true
nearestTargetVisible = false
gameRaycastHits = {
    {
        instance = wall,
        position = Vector3.new(0, 0, -2),
    },
    {
        instance = wall,
        position = Vector3.new(0, 0, -4),
    },
    {
        instance = targetPart,
        position = nearestTargetPosition,
    },
}
require("@lune/task").wait(0.11)
renderCallback(0.016)
assert(
    clickCount == clicksBeforeRejectedWallbang + 2,
    "Wallbang preflight must use the tracked weapon identity when a skin changes the live component name"
)
hookImplementations[bulletModule._performRaycast](component.Bullet, 0)
nearestTargetVisible = true

adapterState.settings.triggerBot = false
adapterState.settings.bhop = true
adapterState.settings.spinBot = true
local initialRootCFrame = root.CFrame
local initialRootAngularVelocity = root.AssemblyAngularVelocity
local initialRootLinearVelocity = Vector3.new(7, 0, -3)
root.AssemblyLinearVelocity = initialRootLinearVelocity
local initialRootJointC0 = rootJoint.C0
local initialRootJointTransform = rootJoint.Transform
currentCamera.CFrame = roblox.CFrame.new()
renderCallback(0.0625)
assert(humanoid.Jump == true, "Bunny Hop must jump only through the live humanoid")
assert(humanoid.AutoRotate == true, "Spin Bot must leave Humanoid.AutoRotate under game control")
assert(
    root.CFrame == initialRootCFrame,
    "Spin Bot must not write root CFrame because Counterblox movement depends on owning it"
)
assert(
    root.AssemblyAngularVelocity == initialRootAngularVelocity,
    "Spin Bot must not disturb the movement controller's angular velocity"
)
assert(
    rootJoint.C0 ~= initialRootJointC0,
    "Spin Bot must rotate the persistent visual root-joint offset without applying physical torque"
)
assert(
    math.abs(rootJoint.C0.LookVector.X) > 0.9,
    "Spin Bot must rotate at least a quarter turn in 1/16 second"
)
assert(rootJoint.Transform == initialRootJointTransform, "Spin Bot must not fight the Animator-owned Transform")
assert(
    currentCamera.CFrame.Position.Z == 8,
    "Spin Bot must establish third person in its late render step without depending on one game camera path"
)
assert(
    root.AssemblyLinearVelocity.X > initialRootLinearVelocity.X
        and root.AssemblyLinearVelocity.Magnitude <= humanoid.WalkSpeed + 0.001,
    "Bunny Hop movement input must add acceleration without discarding perpendicular momentum"
)
local acceleratedVelocity = root.AssemblyLinearVelocity
movementDirection = Vector3.new(0, 0, 0)
root.AssemblyLinearVelocity = Vector3.new(2, 0, -1)
renderCallback(0.016)
assert(
    root.AssemblyLinearVelocity == acceleratedVelocity,
    "Bunny Hop must retain horizontal momentum while Space is held without movement input"
)
movementDirection = Vector3.new(0, 0, 1)
renderCallback(0.016)
assert(
    root.AssemblyLinearVelocity.Z > acceleratedVelocity.Z
        and root.AssemblyLinearVelocity.Magnitude >= acceleratedVelocity.Magnitude,
    "Bunny Hop strafing must bend retained momentum toward movement input without losing speed"
)
local speedCeiling = math.max(initialRootLinearVelocity.Magnitude, humanoid.WalkSpeed)
for _ = 1, 60 do
    local velocity = root.AssemblyLinearVelocity
    movementDirection = Vector3.new(-velocity.Z, 0, velocity.X).Unit
    renderCallback(0.016)
end
assert(
    root.AssemblyLinearVelocity.Magnitude <= speedCeiling + 0.001,
    "Bunny Hop strafing must not accumulate server-rejected horizontal speed"
)
assert(thirdPersonStates[#thirdPersonStates] == true, "Spin Bot must request third-person view")
assert(characterPart.LocalTransparencyModifier == 0, "Third person must reveal the local character")
assert(viewmodelPart.LocalTransparencyModifier == 1, "Third person must hide the first-person viewmodel")
local thirdPersonRequestCount = #thirdPersonStates
renderCallback(0.016)
assert(
    #thirdPersonStates > thirdPersonRequestCount and thirdPersonStates[#thirdPersonStates] == true,
    "Spin Bot must maintain third person every frame against game camera overrides"
)
assert(hookImplementations[cameraController.updateCamera], "Spin Bot must hook Counterblox's custom camera update")
hookImplementations[cameraController.updateCamera](nil)
assert(
    currentCamera.CFrame.Position.Z == 8,
    "Spin Bot third person must offset the rendered camera behind its first-person frame"
)
local weaponFireCameraFrame = roblox.CFrame.new(1, 2, 3)
hookImplementations[cameraController.updateCamera](weaponFireCameraFrame)
assert(
    currentCamera.CFrame.Position.Z == 11,
    "Spin Bot third person must offset Counterblox's explicit per-frame camera CFrame"
)

adapterState.settings.spinBot = false
renderCallback(0.016)
assert(humanoid.AutoRotate == true, "Disabling Spin Bot must restore Humanoid.AutoRotate")
assert(root.AssemblyAngularVelocity == initialRootAngularVelocity, "Disabling Spin Bot must restore root angular velocity")
assert(rootJoint.C0 == initialRootJointC0, "Disabling Spin Bot must restore the visual root joint")
assert(thirdPersonStates[#thirdPersonStates] == false, "Disabling Spin Bot must restore the camera")
assert(characterPart.LocalTransparencyModifier == 1, "Disabling Spin Bot must restore character transparency")
assert(viewmodelPart.LocalTransparencyModifier == 0, "Disabling Spin Bot must restore the viewmodel")

nearestTargetPosition = Vector3.new(6, 0, 0)
adapterState.settings.silentAim = true
adapterState.settings.knifeAura = false
currentCamera.CFrame = roblox.CFrame.new()
local cameraBeforeKnifeAim = currentCamera.CFrame
hookImplementations[meleeModule.shoot]({
    Properties = {
        Range = 8,
    },
}, false)
assert(
    meleeAimLook:Dot(nearestTargetPosition.Unit) < 0.1,
    "Gun Silent Aim must not redirect a knife attack"
)
adapterState.settings.knifeAura = true
hookImplementations[meleeModule.shoot]({
    Properties = {
        Range = 8,
    },
}, false)
assert(
    meleeAimLook:Dot(nearestTargetPosition.Unit) > 0.999,
    "Knife Aura must exclusively align the synchronous melee direction with its selected target"
)
assert(currentCamera.CFrame == cameraBeforeKnifeAim, "Knife target alignment must restore the player's camera immediately")
nearestTargetPosition = Vector3.new(0, 0, -10)
adapterState.settings.silentAim = false
adapterState.settings.bhop = false
adapterState.settings.knifeAura = true
local clicksBeforeKnifeRangeCheck = clickCount
renderCallback(0.016)
assert(
    clickCount == clicksBeforeKnifeRangeCheck,
    "Knife Aura must not attack a target beyond its measured melee range"
)
adapterState.settings.microStep = true
local beforeMicroStep = root.CFrame.Position
renderCallback(0.016)
local microStepDistance = (root.CFrame.Position - beforeMicroStep).Magnitude
assert(microStepDistance > 0 and microStepDistance <= 0.75, "Micro Step must close range in bounded increments")
assert(clickCount == clicksBeforeKnifeRangeCheck, "Micro Step must not attack until the target is inside melee range")

assert(moduleValues[inventoryController] == nil)
for _, module in ipairs(requiredModules) do
    assert(module ~= inventoryController, "Counterblox adapter must not require InventoryController")
    assert(
        module ~= getWeaponProperties,
        "Cosmetic discovery must not load GetWeaponProperties because Potassium cannot execute its nested requires"
    )
end
adapter:stop()
print("counterblox-adapter-contracts-ok")
