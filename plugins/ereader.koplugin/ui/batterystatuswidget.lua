local Device = require("device")
local TextWidget = require("ui/widget/textwidget")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Blitbuffer = require("ffi/blitbuffer")

local BatteryStatusWidget = InputContainer:extend{
    name = "battery_status_widget",
    width = nil,
    height = nil,
    padding = nil,
    overlap_align = "right",
    show_parent = nil,
    show_info_on_tap = true, -- Whether to show battery info when tapped
    on_state_change = nil, -- Optional callback when battery state changes
}

function BatteryStatusWidget:init()
    -- Set default size if not provided
    if not self.width then
        self.width = Screen:scaleBySize(32)
    end
    if not self.height then
        self.height = self.width
    end
    if not self.padding then
        self.padding = Screen:scaleBySize(8)
    end
    
    -- Get power device
    self.powerd = Device:getPowerDevice()
    
    -- Create text widget for battery symbol
    local font_size = math.floor(self.height * 0.4) -- Use 60% of widget height for font size
    self.battery_text = TextWidget:new{
        text = "",
        face = Font:getFace("cfont", font_size),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
    
    -- Set initial text
    self:updateText()
    
    -- Set up touch events
    if Device:isTouchDevice() then
        self.ges_events.TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{ x = 0, y = 0, w = self.width, h = self.height },
            }
        }
    end
    
    -- Register for battery state changes
    self:registerEventHandlers()
    
    -- Set the main widget
    self[1] = self.battery_text
end

function BatteryStatusWidget:onTapSelect()
    if self.show_info_on_tap then
        self:showBatteryInfo()
    end
    
    -- Call optional callback
    if self.on_state_change then
        self.on_state_change()
    end
    return true
end

function BatteryStatusWidget:showBatteryInfo()
    local batt_text = string.format("Battery: %d%%", self.powerd:getCapacity())
    
    if Device:hasAuxBattery() and self.powerd:isAuxBatteryConnected() then
        local aux_batt_lvl = self.powerd:getAuxCapacity()
        batt_text = string.format("Battery: %d%% + %d%%", self.powerd:getCapacity(), aux_batt_lvl)
        
        if self.powerd:isAuxCharging() then
            batt_text = batt_text .. " (Charging)"
        elseif self.powerd:isAuxCharged() then
            batt_text = batt_text .. " (Full)"
        end
    else
        if self.powerd:isCharging() then
            batt_text = batt_text .. " (Charging)"
        elseif self.powerd:isCharged() then
            batt_text = batt_text .. " (Full)"
        end
    end
    
    UIManager:show(InfoMessage:new{
        text = batt_text,
        timeout = 2,
    })
end

function BatteryStatusWidget:updateText()
    local new_text
    local capacity = self.powerd:getCapacity()
    local is_charging = self.powerd:isCharging()
    local is_charged = self.powerd:isCharged()
    
    if Device:hasAuxBattery() and self.powerd:isAuxBatteryConnected() then
        local aux_capacity = self.powerd:getAuxCapacity()
        local aux_is_charging = self.powerd:isAuxCharging()
        local aux_is_charged = self.powerd:isAuxCharged()
        
        -- Use average capacity for symbol, but show charging state
        local avg_capacity = (capacity + aux_capacity) / 2
        new_text = self.powerd:getBatterySymbol(aux_is_charged, aux_is_charging, avg_capacity)
    else
        new_text = self.powerd:getBatterySymbol(is_charged, is_charging, capacity)
    end
    
    if self.battery_text.text ~= new_text then
        self.battery_text:setText(new_text)
        logger.dbg("BatteryStatusWidget: Updated text to", new_text)
    end
end

function BatteryStatusWidget:registerEventHandlers()
    -- Store original handlers to avoid overwriting
    local original_charging = UIManager.event_handlers.Charging
    local original_not_charging = UIManager.event_handlers.NotCharging
    
    UIManager.event_handlers.Charging = function()
        self:updateText()
        if original_charging then
            original_charging()
        end
    end
    
    UIManager.event_handlers.NotCharging = function()
        self:updateText()
        if original_not_charging then
            original_not_charging()
        end
    end
end

return BatteryStatusWidget 