local ItemPolicy = require("./ItemPolicy")
local ItemInput = {}
ItemInput.__index = ItemInput

ItemInput.START_SHOOTING = "StartShooting"
ItemInput.FINISH_SHOOTING = "FinishShooting"
ItemInput.START_AIMING = "StartAiming"
ItemInput.FINISH_AIMING = "FinishAiming"
ItemInput.EQUIP_PRIMARY = "EquipPrimary"
ItemInput.EQUIP_SECONDARY = "EquipSecondary"

function ItemInput.equipAction(item)
    local info = item and item.Info
    if type(info) ~= "table" then
        return nil
    end
    if info.Class == "Secondary" then
        return ItemInput.EQUIP_SECONDARY
    end
    if info.Class == "Primary" then
        return ItemInput.EQUIP_PRIMARY
    end
    return nil
end

function ItemInput.dispatch(fighter, action)
    if
        type(fighter) ~= "table"
        or type(fighter.Input) ~= "function"
        or type(action) ~= "string"
        or action == ""
    then
        return false
    end
    local succeeded, result = pcall(fighter.Input, fighter, action)
    return succeeded and result ~= false
end

function ItemInput.new(getFighter)
    assert(type(getFighter) == "function", "RIVALS item input requires a fighter getter")
    return setmetatable({
        deflecting = false,
        fireHeld = false,
        aimHeld = false,
        getFighter = getFighter,
    }, ItemInput)
end

function ItemInput:_dispatch(action)
    return ItemInput.dispatch(self.getFighter(), action)
end

function ItemInput:canFire(item)
    return not self.deflecting or ItemPolicy.capabilities(item).bypassesDeflection
end

function ItemInput:fire()
    local fighter = self.getFighter()
    local item = fighter and fighter.EquippedItem
    if not fighter or not self:canFire(item) then
        self:releaseFire()
        return false
    end
    return self:_dispatch(ItemInput.START_SHOOTING)
end

function ItemInput:pressFire()
    if not self:fire() then
        return false
    end
    self.fireHeld = true
    return true
end

function ItemInput:releaseFire()
    if not self.fireHeld then
        return false
    end
    self:_dispatch(ItemInput.FINISH_SHOOTING)
    self.fireHeld = false
    return true
end

function ItemInput:pressAim()
    if not self:_dispatch(ItemInput.START_AIMING) then
        return false
    end
    self.aimHeld = true
    return true
end

function ItemInput:aim()
    return self:_dispatch(ItemInput.START_AIMING)
end

function ItemInput:releaseAim()
    if not self.aimHeld then
        return false
    end
    self:_dispatch(ItemInput.FINISH_AIMING)
    self.aimHeld = false
    return true
end

function ItemInput:disownAim()
    self.aimHeld = false
end

function ItemInput:releaseAll()
    self:releaseAim()
    self:releaseFire()
end

function ItemInput:setDeflecting(deflecting)
    self.deflecting = deflecting == true
    if self.deflecting then
        local fighter = self.getFighter()
        if not self:canFire(fighter and fighter.EquippedItem) then
            self:releaseFire()
        end
    end
end

function ItemInput:isFireHeld()
    return self.fireHeld
end

function ItemInput:isAimHeld()
    return self.aimHeld
end

return ItemInput
