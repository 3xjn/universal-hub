local TriggerBot = {}

-- Fallback only. Live fire uses the equipped weapon's native cooldown.
TriggerBot.INTERVAL = 0

function TriggerBot.weaponReady(item, now)
    if type(now) ~= "number" then
        return true
    end
    if type(item) == "table" and type(item._shoot_cooldown) == "number" then
        return now >= item._shoot_cooldown
    end
    return true
end

function TriggerBot.fireDelay(item, fallback)
    local info = item and item.Info
    if type(info) == "table" then
        if type(info.ShootCooldown) == "number" then
            return info.ShootCooldown
        end
        if type(info.InternalUseCooldown) == "number" then
            return info.InternalUseCooldown
        end
    end
    if type(fallback) == "number" then
        return fallback
    end
    return TriggerBot.INTERVAL
end

function TriggerBot.hubReady(state, now)
    local nextAt = state and state.nextAt
    if type(nextAt) ~= "number" or type(now) ~= "number" or now >= nextAt then
        return true
    end
    -- A previous click stored tick() in nextAt. os.clock() can never catch that.
    if nextAt - now > 60 then
        state.nextAt = 0
        return true
    end
    return false
end

TriggerBot.MAX_DELAY_MS = 250
TriggerBot.TARGET_GRACE_SECONDS = 0.1

function TriggerBot.delaySeconds(settings)
    local ms = settings and settings.triggerDelay
    if type(ms) ~= "number" or ms <= 0 then
        return 0
    end
    return math.clamp(ms, 0, TriggerBot.MAX_DELAY_MS) / 1000
end

function TriggerBot.delayReady(state, now, delay, targetKey)
    if type(delay) ~= "number" or delay <= 0 then
        if state then
            state.armedAt = nil
            state.armedDelay = nil
            state.armedKey = nil
        end
        return true
    end
    if type(now) ~= "number" then
        return true
    end
    if
        state.armedKey ~= targetKey
        or state.armedDelay ~= delay
        or type(state.armedAt) ~= "number"
        or type(state.lostAt) == "number"
            and now - state.lostAt > TriggerBot.TARGET_GRACE_SECONDS
    then
        state.armedAt = now
        state.armedDelay = delay
        state.armedKey = targetKey
    end
    state.lostAt = nil
    return now >= state.armedAt + delay
end

function TriggerBot.delayLost(state, now)
    if
        type(state) == "table"
        and type(state.armedAt) == "number"
        and type(state.lostAt) ~= "number"
    then
        state.lostAt = now
    end
end

function TriggerBot.holdDropped(item, now, fallback)
    if type(now) ~= "number" or not TriggerBot.weaponReady(item, now) then
        return false
    end
    local delay = TriggerBot.fireDelay(item, fallback)
    if type(delay) ~= "number" or delay <= 0 then
        return false
    end
    local readyAt = item and item._shoot_cooldown
    if type(readyAt) ~= "number" or readyAt <= 0 then
        return false
    end
    return now - readyAt > delay
end

function TriggerBot.target(session, alignedTarget)
    local settings = session and session.settings or {}
    if settings.shotAim == true then
        return session and session.presented or nil
    end
    return alignedTarget
end

function TriggerBot.solvedPath(target)
    return target ~= nil
        and (
            target.projectileAim ~= nil
            or target.ricochet ~= nil
            or target.slingshot ~= nil
            or target.splashImpact ~= nil
        )
end

local function policyFlag(weaponPolicy, name, item)
    local query = weaponPolicy and weaponPolicy[name]
    return type(query) == "function" and query(item) == true
end

local function cameraOrigin(ctx)
    local camera = ctx and ctx.camera
    local frame = camera and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
    return frame and frame.Position or nil
end

function TriggerBot.hitscanReady(target, origin, raycast, targeting)
    if typeof(origin) ~= "Vector3" or type(raycast) ~= "function" then
        return target and target.visible == true
    end
    targeting = targeting or {}
    if type(targeting.visibleHeadPoint) == "function" then
        local point = targeting.visibleHeadPoint(target, origin, raycast)
        if point then
            return true
        end
    end
    if type(targeting.visibleBodyPoint) == "function" then
        local point = targeting.visibleBodyPoint(target, origin, raycast)
        if point then
            return true
        end
    end
    return false
end

function TriggerBot.pathReady(target, item, ctx)
    ctx = ctx or {}
    if not target then
        return false
    end
    local WeaponPolicy = ctx.weaponPolicy or {}
    local ProjectileAim = ctx.projectileAim or {}
    if
        policyFlag(WeaponPolicy, "isBackstabKnife", item)
        or policyFlag(WeaponPolicy, "isDualModeBlade", item)
    then
        return true
    end
    if TriggerBot.solvedPath(target) then
        return true
    end
    local usesArc = (
        type(ProjectileAim.isSplashProjectile) == "function"
        and ProjectileAim.isSplashProjectile(item)
    )
        or (type(ProjectileAim.isDirectProjectile) == "function" and ProjectileAim.isDirectProjectile(
            item
        ))
        or policyFlag(WeaponPolicy, "isRicochetWeapon", item)
        or policyFlag(WeaponPolicy, "isBouncingProjectile", item)
    if usesArc then
        return false
    end
    return TriggerBot.hitscanReady(target, cameraOrigin(ctx), ctx.raycast, ctx.targeting)
end

function TriggerBot.shouldHoldForDeflect(target, item, ctx)
    if not target or type(ctx) ~= "table" or type(ctx.isDeflecting) ~= "function" then
        return false
    end
    local targetFighter = target.player
        and type(ctx.fighterFor) == "function"
        and ctx.fighterFor(target.player)
    local counter = ctx.taskCounterPolicy
    local sprayCounter = targetFighter
        and type(counter) == "table"
        and type(counter.shouldForceSpray) == "function"
        and counter.shouldForceSpray(item, targetFighter.EquippedItem)
    return ctx.isDeflecting(target.player) == true and sprayCounter ~= true
end

function TriggerBot.update(session, ctx)
    local settings = session and session.settings or {}
    local alignedTarget = TriggerBot.target(session, ctx.alignedTarget)
    local taskCombatActive = ctx.taskCombatActive
    local taskDebug = ctx.taskDebug
    local state = ctx.state
    local WeaponPolicy = ctx.weaponPolicy
    local ProjectileAim = ctx.projectileAim
    local interval = ctx.interval or TriggerBot.INTERVAL
    local manualAimHeld = type(ctx.isAimInputHeld) == "function" and ctx.isAimInputHeld() == true
    if manualAimHeld and state.held then
        if type(ctx.disownAim) == "function" then
            ctx.disownAim()
        end
        state.held = false
        state.heldItem = nil
    end
    if taskDebug then
        taskDebug.triggerStage = "entered"
        taskDebug.triggerAt = ctx.clock()
    end
    if
        settings.triggerBot ~= true and taskCombatActive ~= true
        or (ctx.inputCaptured and taskCombatActive ~= true)
        or not ctx.fighterActive
        or not ctx.inCombat
    then
        if taskDebug then
            taskDebug.triggerStage = "inactive"
        end
        state.gunblade = nil
        state.armedAt = nil
        state.armedDelay = nil
        state.armedKey = nil
        state.lostAt = nil
        ctx.releaseFire()
        if state.held then
            ctx.aimRelease()
            state.held = false
            state.heldItem = nil
        end
        return
    end
    local fighter = ctx.getFighter()
    local item = fighter and fighter.EquippedItem
    if WeaponPolicy.automationPolicy(item).triggerBot ~= true then
        if taskDebug then
            taskDebug.triggerStage = "unsupported-weapon"
        end
        state.gunblade = nil
        ctx.clearAimPlan()
        state.armedAt = nil
        state.armedDelay = nil
        state.armedKey = nil
        state.lostAt = nil
        ctx.releaseFire()
        if state.held then
            ctx.aimRelease()
            state.held = false
            state.heldItem = nil
        end
        return
    end
    local itemData = item.Data
    local ammo = WeaponPolicy.ammo(item)
    if ammo == 0 or type(itemData) == "table" and itemData.IsReloading == true then
        if taskDebug then
            taskDebug.triggerStage = ammo == 0 and "empty" or "reloading"
        end
        ctx.releaseFire()
        if state.held then
            ctx.aimRelease()
            state.held = false
            state.heldItem = nil
        end
        return
    end
    local gunblade = WeaponPolicy.isDualModeBlade(item)
    local target
    if gunblade then
        if settings.shotAim then
            target = alignedTarget
        else
            target = ctx.selectDualModeBladeTarget(fighter, item)
        end
    else
        target = alignedTarget
        if target and target.aimSettled == false then
            ctx.releaseFire()
            if taskDebug then
                taskDebug.triggerStage = "aim-settling"
            end
            return
        elseif not target and not settings.shotAim then
            target = ctx.selectCrosshairTarget()
        end
    end
    if TriggerBot.shouldHoldForDeflect(target, item, ctx) then
        if taskDebug then
            taskDebug.triggerStage = "target-deflecting"
        end
        state.gunblade = nil
        state.armedAt = nil
        state.armedDelay = nil
        state.armedKey = nil
        state.lostAt = nil
        ctx.releaseFire()
        if state.held then
            ctx.aimRelease()
            state.held = false
            state.heldItem = nil
        end
        return
    end
    if not target or not TriggerBot.pathReady(target, item, ctx) then
        if taskDebug then
            taskDebug.triggerStage = not target and "no-target" or "path-blocked"
        end
        local now = ctx.clock()
        TriggerBot.delayLost(state, now)
        if state.fireHeld then
            state.fireLostAt = state.fireLostAt or now
            if now - state.fireLostAt <= TriggerBot.TARGET_GRACE_SECONDS then
                return
            end
        end
        state.fireLostAt = nil
        state.gunblade = nil
        ctx.releaseFire()
        if state.held then
            ctx.aimRelease()
            state.held = false
            state.heldItem = nil
            state.nextAt = ctx.clock() + TriggerBot.fireDelay(item, interval)
        end
        return
    end
    state.fireLostAt = nil

    if gunblade then
        ctx.releaseFire()
        if state.held then
            ctx.aimRelease()
            state.held = false
            state.heldItem = nil
        end

        local entity = fighter and fighter.Entity
        local localRoot = entity and entity.RootPart
        local localPosition = localRoot and localRoot.Position
        local targetPosition = ctx.targetRootPosition(target)
        local targetDistance = localPosition
            and targetPosition
            and (targetPosition - localPosition).Magnitude
        local action
        state.gunblade, action = WeaponPolicy.gunbladeTriggerAction(
            state.gunblade,
            item,
            target.character or target.player or target,
            targetDistance,
            ctx.clock()
        )
        if not action then
            return
        end

        local camera = ctx.camera
        local cameraFrame = camera
            and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
        local cameraPosition = cameraFrame and cameraFrame.Position
        local cameraOffset = cameraPosition and targetPosition and targetPosition - cameraPosition
        local visibleFrame = camera and camera.CFrame
        local visibleRotation = ctx.cameraController.Rotation
        if cameraOffset and cameraOffset.Magnitude > 1e-3 then
            ctx.cameraController:SetRotation(
                ctx.targeting.rotationToward(cameraPosition, targetPosition)
            )
            camera.CFrame = CFrame.lookAt(cameraPosition, targetPosition)
        end
        if action.kind == "dash" then
            ctx.aimClick()
        else
            ctx.click()
        end
        if visibleFrame then
            camera.CFrame = visibleFrame
        end
        if visibleRotation then
            ctx.cameraController:SetRotation(visibleRotation)
        end
        ctx.clearAimPlan()
        return
    end
    state.gunblade = nil
    if
        ProjectileAim.isSplashProjectile(item)
        and not (alignedTarget and alignedTarget.splashImpact)
    then
        ctx.releaseFire()
        return
    end
    if WeaponPolicy.isBackstabKnife(item) then
        ctx.releaseFire()
        if not WeaponPolicy.backstabTriggerReady(fighter, item, alignedTarget, ctx.isGunGame()) then
            return
        end
        if state.held then
            ctx.aimRelease()
            state.held = false
            state.heldItem = nil
        end
        if not TriggerBot.hubReady(state, ctx.clock()) then
            return
        end
        state.nextAt = ctx.clock() + (item.Info.HeavyAttackCooldown or interval)
        ctx.aimClick()
        return
    end
    local targetFighter = target.player and ctx.fighterFor(target.player)
    local sprayCounter = targetFighter
        and ctx.taskCounterPolicy.shouldForceSpray(item, targetFighter.EquippedItem)
    local camera = ctx.camera
    local cameraFrame = camera
        and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
    local targetDistance = cameraFrame
        and target.position
        and (target.position - cameraFrame.Position).Magnitude
    if
        targetDistance
        and WeaponPolicy.isShotgun(item)
        and not sprayCounter
        and not WeaponPolicy.triggerDamageReady(item, target, targetDistance)
    then
        if taskDebug then
            taskDebug.triggerStage = "damage-gate"
        end
        ctx.releaseFire()
        return
    end
    local sniperCrouching = WeaponPolicy.isScoped(item) and ctx.localFighterIsCrouching(fighter)
    if
        not WeaponPolicy.sniperTriggerReady(
            ctx.cameraController,
            item,
            target,
            targetDistance,
            sniperCrouching,
            settings.alwaysScoped == true
        )
    then
        if taskDebug then
            taskDebug.triggerStage = "precision-gate"
        end
        ctx.releaseFire()
        return
    end
    if taskDebug then
        taskDebug.triggerStage = "ready"
        taskDebug.triggerDistance = targetDistance
    end
    local targetKey = target.character or target.player or target
    local previousKey = state.armedKey
    if
        not TriggerBot.delayReady(state, ctx.clock(), TriggerBot.delaySeconds(settings), targetKey)
    then
        if taskDebug then
            taskDebug.triggerStage = "delay"
        end
        if previousKey ~= targetKey then
            ctx.releaseFire()
        end
        return
    end
    if WeaponPolicy.isFanFirearm(item) then
        ctx.releaseFire()
        local action =
            WeaponPolicy.revolverTriggerAction(item, target, targetDistance, ctx.itemClock())
        if state.held then
            ctx.aimRelease()
            state.held = false
            state.heldItem = nil
        end
        if not action or not TriggerBot.hubReady(state, ctx.clock()) then
            return
        end
        state.nextAt = ctx.clock() + action.cooldown
        if action.kind == "fan" then
            ctx.aimClick()
        else
            ctx.click()
        end
        ctx.clearAimPlan()
        return
    end
    if WeaponPolicy.isChargedBow(item) then
        ctx.releaseFire()
        if manualAimHeld then
            if taskDebug then
                taskDebug.triggerStage = "manual-aim"
            end
            return
        end
        if not state.held then
            if not TriggerBot.hubReady(state, ctx.clock()) then
                return
            end
            if WeaponPolicy.bowQuickShotLethal(item, target) then
                state.nextAt = ctx.clock() + (item.Info.ShootCooldown or interval)
                ctx.click()
                ctx.clearAimPlan()
                return
            end
            state.held = true
            state.heldAt = ctx.clock()
            state.heldItem = item
            ctx.aimPress()
            return
        end
        if state.heldItem ~= item then
            ctx.aimRelease()
            state.held = false
            state.heldItem = nil
            state.nextAt = ctx.clock() + interval
            return
        end
        if ctx.clock() - state.heldAt + 1e-3 < WeaponPolicy.bowChargeTime(item, target) then
            return
        end

        ctx.aimRelease()
        state.held = false
        state.heldItem = nil
        state.nextAt = ctx.clock() + (item.Info.ChargeReleaseCooldown or interval)
        ctx.clearAimPlan()
        return
    end

    if state.held then
        ctx.aimRelease()
        state.held = false
        state.heldItem = nil
    end
    if WeaponPolicy.holdToFire(item) then
        if not WeaponPolicy.adsSettled(ctx.cameraController, item) then
            if taskDebug then
                taskDebug.triggerStage = "ads-gate"
            end
            ctx.releaseFire()
            return
        end
        if state.fireHeld and state.fireItem == item then
            if WeaponPolicy.repeatShootingInput(item) then
                ctx.press()
            else
                local fireClock = type(ctx.itemClock) == "function" and ctx.itemClock()
                    or ctx.clock()
                if TriggerBot.holdDropped(item, fireClock, 0) then
                    ctx.releaseFire()
                    state.fireHeld = true
                    state.fireItem = item
                    ctx.press()
                end
            end
            if taskDebug then
                taskDebug.triggerStage = "holding-fire"
            end
            return
        end
        if not TriggerBot.hubReady(state, ctx.clock()) then
            return
        end
        state.fireHeld = true
        state.fireItem = item
        ctx.press()
        if taskDebug then
            taskDebug.triggerStage = "pressed-fire"
        end
        ctx.clearAimPlan()
        return
    end

    ctx.releaseFire()
    local fireClock = type(ctx.itemClock) == "function" and ctx.itemClock() or ctx.clock()
    if
        not TriggerBot.weaponReady(item, fireClock) or not TriggerBot.hubReady(state, ctx.clock())
    then
        return
    end
    if not WeaponPolicy.adsSettled(ctx.cameraController, item) then
        return
    end

    ctx.click()
    -- nextAt is os.clock(); item._shoot_cooldown is tick(). Never copy that
    -- stamp across clocks or a pistol waits ~1.7e9 seconds for the next shot.
    state.nextAt = sprayCounter and ctx.clock() + TriggerBot.fireDelay(item, interval) or 0
    if taskDebug then
        taskDebug.triggerStage = "clicked-fire"
    end
    ctx.clearAimPlan()
end

return TriggerBot
