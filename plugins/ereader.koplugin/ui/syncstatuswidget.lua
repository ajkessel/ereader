local IconButton = require("ui/widget/iconbutton")
local Screen = require("device").screen

local SyncStatusWidget = IconButton:extend{
    name = "sync_status_widget",
    width = nil,
    height = nil,
    padding = nil,
    overlap_align = "right",
    icon = "cre.render.reload",
    show_parent = nil,
    callback = nil,
}

function SyncStatusWidget:init()
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
    -- Call parent init
    IconButton.init(self)
end

return SyncStatusWidget 