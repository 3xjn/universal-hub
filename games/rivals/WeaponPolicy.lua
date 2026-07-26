local WeaponPolicy = {}

local AUTOMATIC_SHOOT_COOLDOWN = 0.15
local TRIGGER_DAMAGE_RETENTION = 0.9
local TRIGGER_INTERVAL = 0.1

function WeaponPolicy.itemName(item)
    if not item then
        return nil
    end

    local info = item.Info
    if type(info) == "table" then
        return info.DisplayName or info.Name or info.ItemName or item.Name
    end
    return item.Name
end

function WeaponPolicy.itemLabel(item)
    local name = WeaponPolicy.itemName(item)
    local info = item and item.Info
    local maximum = type(info) == "table" and info.MaxAbsorption or nil
    if not name or type(maximum) ~= "number" then
        return name
    end

    local current
    if type(item.Get) == "function" then
        local ok, value = pcall(item.Get, item, "Ammo")
        current = ok and value or nil
    end
    if type(current) ~= "number" and type(item.Data) == "table" then
        current = item.Data.Ammo
    end
    if type(current) ~= "number" then
        return name
    end

    return ("%s (%s/%s)"):format(name, tostring(current), tostring(maximum))
end

function WeaponPolicy.backstabPlan(localPosition, observation, info, acquisitionDistance)
    local health = observation and observation.health
    local character = observation and observation.character
    local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
    if type(health) ~= "number"
        or type(info) ~= "table"
        or type(info.CriticalDamage) ~= "number"
        or health > info.CriticalDamage
        or not targetRoot
        or not targetRoot.CFrame
    then
        return nil
    end

    local offset = localPosition - targetRoot.Position
    local reach = info.HeavyAttackReach or info.AttackReach
    if type(reach) ~= "number" or offset.Magnitude <= 1e-3 then
        return nil
    end

    local rearDirection = offset.Unit
    local rearDot = targetRoot.CFrame.LookVector:Dot(rearDirection)
    local ready = offset.Magnitude <= reach and rearDot <= 0.1
    local acquisitionReach = math.min(24, math.max(16, reach * 2.5))
    if type(acquisitionDistance) == "number" then
        acquisitionReach = math.max(acquisitionReach, acquisitionDistance)
    end
    if not ready and offset.Magnitude > acquisitionReach then
        return nil
    end

    local approachDistance = math.clamp(reach * 0.65, 3.5, 5)
    local approachPosition = targetRoot.Position
        - targetRoot.CFrame.LookVector * approachDistance
    return {
        aimPosition = ready and observation.position or approachPosition,
        approachPosition = approachPosition,
        movePosition = approachPosition,
        path = {
            localPosition,
            approachPosition,
            targetRoot.Position,
        },
        ready = ready,
        rearDot = rearDot,
    }
end

function WeaponPolicy.backstabReady(localPosition, observation, info)
    local plan = WeaponPolicy.backstabPlan(localPosition, observation, info)
    return plan ~= nil and plan.ready == true
end

function WeaponPolicy.adsSettled(cameraController, item)
    local info = item and item.Info
    local data = item and item.Data
    if type(info) ~= "table" or info.AimScopePercent == nil
        or type(data) ~= "table" or data.IsAiming ~= true
    then
        return true
    end

    local spring = cameraController._fov_weapons_spring
    return spring ~= nil
        and type(spring.Value) == "number"
        and type(spring.Target) == "number"
        and math.abs(spring.Value - spring.Target) <= 0.5
end

function WeaponPolicy.holdToFire(item)
    local info = item and item.Info
    local inputSpamming = type(info) == "table" and info.InputSpammingEnabled
    if type(inputSpamming) ~= "table"
        or type(inputSpamming.StartShooting) ~= "number"
        or info.IsProjectile == true
    then
        return false
    end

    return type(info.InternalUseCooldown) == "number"
        or type(info.ShootCooldown) == "number"
            and info.ShootCooldown <= AUTOMATIC_SHOOT_COOLDOWN
end

function WeaponPolicy.gunbladeMode(item)
    if WeaponPolicy.itemName(item) ~= "Gunblade" then
        return nil
    end

    local info = item and item.Info
    local getMobileInputSettings = item and item.GetMobileInputSettings
    local bladeSettings = type(info) == "table" and info.BladeModeMobileInputSettings
    local gunSettings = type(info) == "table" and info.MobileInputSettings
    if type(getMobileInputSettings) ~= "function"
        or type(bladeSettings) ~= "table"
        or type(gunSettings) ~= "table"
    then
        return nil
    end

    local succeeded, currentSettings = pcall(getMobileInputSettings, item)
    if not succeeded or type(currentSettings) ~= "table" then
        return nil
    end
    if currentSettings == bladeSettings then
        return "blade"
    end
    if currentSettings == gunSettings then
        return "gun"
    end

    if bladeSettings.Aim ~= gunSettings.Aim then
        if currentSettings.Aim == bladeSettings.Aim then
            return "blade"
        end
        if currentSettings.Aim == gunSettings.Aim then
            return "gun"
        end
    end
    return nil
end

function WeaponPolicy.gunbladeDashRange(item)
    if WeaponPolicy.itemName(item) ~= "Gunblade" then
        return nil
    end

    local info = item and item.Info
    local reach = info and info.BladeReach
    local dashSpeed = info and info.DashSpeed
    local dashDuration = info and info.DashDuration
    if type(reach) ~= "number"
        or type(dashSpeed) ~= "number"
        or type(dashDuration) ~= "number"
    then
        return nil
    end
    return reach + dashSpeed * dashDuration
end

local function gunbladeState(item, target, phase, readyAt, dashReadyAt)
    return {
        dashReadyAt = dashReadyAt or 0,
        item = item,
        phase = phase,
        readyAt = readyAt,
        target = target,
    }
end

local function gunbladeQuickAttackReady(item)
    local canQuickAttack = item and item.CanQuickAttack
    if type(canQuickAttack) ~= "function" then
        return true
    end
    local succeeded, ready = pcall(canQuickAttack, item)
    return succeeded and ready == true
end

function WeaponPolicy.gunbladeTriggerAction(state, item, target, distance, now)
    local mode = WeaponPolicy.gunbladeMode(item)
    local dashRange = WeaponPolicy.gunbladeDashRange(item)
    local info = item and item.Info
    local bladeReach = info and info.BladeReach
    if not mode
        or not target
        or type(distance) ~= "number"
        or type(now) ~= "number"
        or type(dashRange) ~= "number"
        or distance > dashRange
        or type(bladeReach) ~= "number"
    then
        return nil, nil
    end

    if type(state) ~= "table" or state.item ~= item or state.target ~= target then
        state = nil
    end
    local phase = state and state.phase
    local readyAt = state and state.readyAt or 0
    local dashReadyAt = state and state.dashReadyAt or 0
    local transitionCooldown = type(info.TransitionCooldown) == "number"
            and info.TransitionCooldown
        or 0

    if mode == "gun" then
        if phase == "awaitBlade"
            or (phase == "awaitGun" and now < readyAt)
        then
            return state, nil
        end

        local shootCooldown = type(info.ShootCooldown) == "number" and info.ShootCooldown or TRIGGER_INTERVAL
        return gunbladeState(
            item,
            target,
            "awaitBlade",
            now + math.max(shootCooldown, transitionCooldown),
            dashReadyAt
        ), {
            cooldown = shootCooldown,
            kind = "shoot",
        }
    end

    if phase == "strike" then
        if now < readyAt
            or distance > bladeReach
            or not gunbladeQuickAttackReady(item)
        then
            return state, nil
        end
    elseif phase == "awaitGun" then
        return state, nil
    else
        if now < dashReadyAt or (phase == "awaitBlade" and now < readyAt) then
            return state, nil
        end

        local dashCooldown = type(info.DashCooldown) == "number" and info.DashCooldown or TRIGGER_INTERVAL
        return gunbladeState(
            item,
            target,
            "strike",
            now,
            now + dashCooldown
        ), {
            cooldown = dashCooldown,
            kind = "dash",
        }
    end

    local bladeCooldown = type(info.BladeCooldown) == "number" and info.BladeCooldown or TRIGGER_INTERVAL
    return gunbladeState(
        item,
        target,
        "awaitGun",
        now + math.max(bladeCooldown, transitionCooldown),
        dashReadyAt
    ), {
        cooldown = bladeCooldown,
        kind = "strike",
    }
end

function WeaponPolicy.damageAtDistance(item, observation, distance)
    local info = item and item.Info
    local startDistance =
        info and (info.DamageFallOffStartDist or info.RaycastDamageDropoffStartDistance)
    local endDistance = info and (info.DamageFallOffEndDist or info.RaycastDamageDropoffEndDistance)
    local minimumMultiplier =
        info and (info.DamageFallOffMultiplier or info.RaycastDamageDropoffMultiplier)
    local part = observation and observation.part
    local baseDamage = part and part.Name == "Head" and info and info.CriticalDamage
        or info and info.ShootDamage
    if type(baseDamage) ~= "number" then
        return nil
    end
    if type(startDistance) ~= "number"
        or type(endDistance) ~= "number"
        or endDistance <= startDistance
        or type(minimumMultiplier) ~= "number"
        or type(distance) ~= "number"
    then
        return baseDamage
    end

    local alpha = math.clamp((distance - startDistance) / (endDistance - startDistance), 0, 1)
    return baseDamage * (1 + (minimumMultiplier - 1) * alpha)
end

function WeaponPolicy.triggerDamageReady(item, observation, distance)
    local info = item and item.Info
    local startDistance =
        info and (info.DamageFallOffStartDist or info.RaycastDamageDropoffStartDistance)
    local endDistance = info and (info.DamageFallOffEndDist or info.RaycastDamageDropoffEndDistance)
    local minimumMultiplier =
        info and (info.DamageFallOffMultiplier or info.RaycastDamageDropoffMultiplier)
    if type(info) ~= "table"
        or type(startDistance) ~= "number"
        or type(endDistance) ~= "number"
        or type(minimumMultiplier) ~= "number"
    then
        return true
    end

    local part = observation and observation.part
    local baseDamage = part and part.Name == "Head" and info.CriticalDamage or info.ShootDamage
    local damage = WeaponPolicy.damageAtDistance(item, observation, distance)
    local health = observation and observation.health
    return type(baseDamage) == "number"
        and type(damage) == "number"
        and (damage >= baseDamage * TRIGGER_DAMAGE_RETENTION
            or type(health) == "number" and damage >= health)
end

function WeaponPolicy.bowChargeTime(item, observation)
    local info = item and item.Info
    local timestamps = info and info.ChargeLevelTimestamps
    local multipliers = info and info.ChargeLevelDamageMultipliers
    if type(timestamps) ~= "table" or type(multipliers) ~= "table" then
        return 0
    end

    local part = observation and observation.part
    local baseDamage = part and part.Name == "Head" and info.CriticalDamage or info.ShootDamage
    local health = observation and observation.health
    if type(baseDamage) ~= "number" or type(health) ~= "number" then
        return timestamps[#timestamps] or 0
    end

    for level, timestamp in ipairs(timestamps) do
        local multiplier = multipliers[level]
        if type(timestamp) == "number"
            and type(multiplier) == "number"
            and baseDamage * multiplier >= health
        then
            return timestamp
        end
    end
    return timestamps[#timestamps] or 0
end

function WeaponPolicy.bowQuickShotLethal(item, observation)
    local info = item and item.Info
    if type(info) ~= "table" then
        return false
    end

    local part = observation and observation.part
    local damage = part and part.Name == "Head" and info.CriticalDamage or info.ShootDamage
    local health = observation and observation.health
    if type(damage) ~= "number" or type(health) ~= "number" or damage < health then
        return false
    end

    local shootCooldown = info.ShootCooldown
    local releaseCooldown = info.ChargeReleaseCooldown
    return type(shootCooldown) == "number"
        and type(releaseCooldown) == "number"
        and shootCooldown + TRIGGER_INTERVAL < releaseCooldown
end

local function revolverCanShoot(item, now)
    local data = item and item.Data
    local ammo = type(data) == "table" and data.Ammo
    if type(now) ~= "number" or type(ammo) ~= "number" or ammo <= 0 then
        return false
    end

    if item.IsEquipping == true then
        return false
    end
    if type(item._shoot_cooldown) == "number" and now < item._shoot_cooldown then
        return false
    end

    local reloadCooldown = item._reload_cooldown
    if type(reloadCooldown) ~= "number" or now >= reloadCooldown then
        return true
    end

    local cancelCooldown = item._reload_cancel_cooldown
    local cancelExpiration = item._reload_cancel_expiration
    return type(cancelCooldown) == "number"
        and now >= cancelCooldown
        and type(cancelExpiration) == "number"
        and now < cancelExpiration
end

local function targetFitsRevolverSpread(observation, distance, spread)
    if type(spread) ~= "number" or type(distance) ~= "number" then
        return false
    end

    local part = observation and observation.part
    local size = part and part.Size
    local targetRadius = 1
    if size and type(size.X) == "number" and type(size.Y) == "number" then
        targetRadius = math.min(size.X, size.Y) * 0.5
    end
    return math.tan(math.rad(spread)) * distance <= targetRadius
end

function WeaponPolicy.revolverTriggerAction(item, observation, distance, now)
    local info = item and item.Info
    if not item
        or item.Name ~= "Revolver"
        or type(info) ~= "table"
        or not revolverCanShoot(item, now)
    then
        return nil
    end

    local quickCooldown = info.QuickShotCooldown
    local preciseCooldown = info.ShootCooldown
    if type(quickCooldown) ~= "number" or type(preciseCooldown) ~= "number" then
        return nil
    end

    local preciseLockedUntil = item._is_revolver_quick_shooting
    local preciseReady = type(preciseLockedUntil) ~= "number" or now >= preciseLockedUntil
    local preciseFits =
        targetFitsRevolverSpread(observation, distance, info.ShootSpread)
    local preciseDamage = WeaponPolicy.damageAtDistance(item, observation, distance)
    local health = observation and observation.health
    if preciseReady
        and preciseFits
        and type(preciseDamage) == "number"
        and type(health) == "number"
        and preciseDamage >= health
    then
        return {
            cooldown = preciseCooldown,
            kind = "precise",
        }
    end

    if targetFitsRevolverSpread(observation, distance, info.QuickShotSpread) then
        return {
            cooldown = quickCooldown,
            kind = "fan",
        }
    end
    if preciseReady and preciseFits then
        return {
            cooldown = preciseCooldown,
            kind = "precise",
        }
    end
    return nil
end


return WeaponPolicy
