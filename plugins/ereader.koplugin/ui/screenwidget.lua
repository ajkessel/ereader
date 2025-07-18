local WidgetContainer = require("ui/widget/container/widgetcontainer")
local IconButton = require("ui/widget/iconbutton")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")

local ScreenWidget = IconButton:extend{
    name = "screen_widget",
    icon = "brightness",
    overlap_align = "right",
    width = nil,
    height = nil,
    padding = nil,
    show_parent = nil,
    callback = function()
        local FrontLightWidget = require("ui/widget/frontlightwidget")
        UIManager:show(FrontLightWidget:new{})
    end,
}

function ScreenWidget:init()
    -- Create icon button with brightness icon
    if not self.width then
        self.width = Screen:scaleBySize(32)
    end
    if not self.height then
        self.height = self.width
    end
    if not self.padding then
        self.padding = Screen:scaleBySize(8)
    end
    -- Call parent init
    IconButton.init(self)
end

return ScreenWidget 