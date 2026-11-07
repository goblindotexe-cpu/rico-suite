local _, RP = ...
local Inventory = RP.Inventory

local function InCombat()
    return InCombatLockdown and RP.PublicTrue(InCombatLockdown())
end

local function PaintNativeSlots(inventory, frame)
    if not frame:IsShown() or not frame.EnumerateValidItems then return end
    local combat = InCombat()
    for _, button in frame:EnumerateValidItems() do
        if RP.CanUseFrame(button) and button.HasItem then
            if not combat or inventory.slots[button] then
                local hasItem = button:HasItem()
                if RP.Readable(hasItem) then
                    local icon = button.icon or button.Icon
                    local stockNormal = button.GetNormalTexture and button:GetNormalTexture()
                    inventory:PaintSlot(button, icon, stockNormal, not RP.PublicTrue(hasItem))
                end
            else
                inventory.pendingSkin = true
            end
        end
    end
end

function Inventory:SkinNativeBody(frame)
    if frame ~= _G.ContainerFrameCombinedBags or not RP.CanUseFrame(frame) or not frame:IsShown() then return end
    if not self.bodies[frame] then
        if InCombat() then
            self.pendingSkin = true
            return
        end

        -- These are the combined bag's decorative panels. The portrait,
        -- search box, close button and money frame are separate widgets.
        self:PaintBody(frame)
        if frame.Bg then frame.Bg:SetAlpha(0) end
        if frame.NineSlice then frame.NineSlice:SetAlpha(0) end
        -- Blizzard refreshes the pooled item buttons here after changing
        -- bags, moving items or updating search and item state.
        if hooksecurefunc and frame.UpdateItems then
            hooksecurefunc(frame, "UpdateItems", function(updated) PaintNativeSlots(self, updated) end)
        end
    end
    PaintNativeSlots(self, frame)
end
