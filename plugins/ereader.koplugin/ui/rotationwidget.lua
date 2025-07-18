local Device = require("device")
local IconButton = require("ui/widget/iconbutton")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local TouchMenu = require("ui/widget/touchmenu")
local Screen = Device.screen
local bit = require("bit")
local _ = require("gettext")

--[[
RotationWidget
--------------
A small toolbar button that lets the user quickly adjust screen orientation.
On devices with a G-sensor *and* with auto-rotation enabled, it exposes three
radio options:
  • Auto rotate        – gyro events fully honoured (default KOReader logic)
  • Portrait (lock)    – gyro honoured only within portrait group (180° flips)
  • Landscape (lock)   – same for landscape group

When the device has no G-sensor, or the user globally disabled auto-rotation
(setting `input_ignore_gsensor`), the widget instead offers four manual
orientation choices.

--]]

local RotationWidget = IconButton:extend{
    name          = "rotation_widget",
    icon          = "rotation.auto",
    overlap_align = "right",
    width         = nil,
    height        = nil,
    padding       = nil,
    show_parent   = nil,
}

-- Helpers --------------------------------------------------------------
local function autoRotationAvailable()
    return Device:hasGSensor() and G_reader_settings:nilOrFalse("input_ignore_gsensor")
end

local function isAspectLocked()
    return G_reader_settings:isTrue("input_lock_gsensor")
end

local function isPortraitGroup()
    return bit.band(Screen:getRotationMode(), 1) == 0
end

local function setAspectLock(flag)
    G_reader_settings:saveSetting("input_lock_gsensor", flag)
    Device:lockGSensor(flag)
end

local function setRotation(mode)
    UIManager:broadcastEvent(Event:new("SetRotationMode", mode))
end

function RotationWidget:updateIcon()
    local new_icon

    if not autoRotationAvailable() then
        local rota_icon_map = {
            [Screen.DEVICE_ROTATED_UPRIGHT]           = "rotation.P.0UR",
            [Screen.DEVICE_ROTATED_CLOCKWISE]         = "rotation.L.90CW",
            [Screen.DEVICE_ROTATED_UPSIDE_DOWN]       = "rotation.P.180UD",
            [Screen.DEVICE_ROTATED_COUNTER_CLOCKWISE] = "rotation.L.90CCW",
        }

        new_icon = rota_icon_map[Screen:getRotationMode()] or "rotation.manual"
    else
        if isAspectLocked() then
            if isPortraitGroup() then
                new_icon = "rotation.lock.portrait"
            else
                new_icon = "rotation.lock.landscape"
            end
        else
            new_icon = "rotation.auto"
        end
    end

    if new_icon and self.icon ~= new_icon then
        self:setIcon(new_icon)
        UIManager:setDirty("all", "ui")
    end
end

function RotationWidget:init()
    if not self.width  then self.width  = Screen:scaleBySize(32) end
    if not self.height then self.height = self.width end
    if not self.padding then self.padding = Screen:scaleBySize(8) end

    self:updateIcon()

    self.callback = function()
        self:showMenu()
    end

    IconButton.init(self)
end


-- Menu builders -------------------------------------------------------
function RotationWidget:menuAutoRotation()
    local items = {}

    -- Auto rotate -----------------------------------------------------
    table.insert(items, {
        text        = _("Auto rotate"),
        icon        = "rotation.auto",
        radio       = true,
        checked_func = function()
            return not isAspectLocked()
        end,
        callback    = function(touchmenu_instance)
            if isAspectLocked() then setAspectLock(false) end
            touchmenu_instance:closeMenu()
            self:updateIcon()
        end,
        check_callback_closes_menu = true,
    })

    -- Portrait lock ---------------------------------------------------
    table.insert(items, {
        text        = _("Portrait"),
        icon        = "rotation.lock.portrait",
        radio       = true,
        checked_func = function()
            return isAspectLocked() and isPortraitGroup()
        end,
        callback    = function(touchmenu_instance)
            if not isPortraitGroup() then
                setRotation(Screen.DEVICE_ROTATED_UPRIGHT)
            end
            setAspectLock(true)
            touchmenu_instance:closeMenu()
            self:updateIcon()
        end,
        check_callback_closes_menu = true,
    })

    -- Landscape lock --------------------------------------------------
    table.insert(items, {
        text        = _("Landscape"),
        icon        = "rotation.lock.landscape",
        radio       = true,
        checked_func = function()
            return isAspectLocked() and not isPortraitGroup()
        end,
        callback    = function(touchmenu_instance)
            if isPortraitGroup() then
                setRotation(Screen.DEVICE_ROTATED_CLOCKWISE)
            end
            setAspectLock(true)
            touchmenu_instance:closeMenu()
            self:updateIcon()
        end,
        check_callback_closes_menu = true,
    })

    return items
end

function RotationWidget:menuManual()
    local function genateMenuItem(text, mode, icon)
        return {
            text        = text,
            icon        = icon,
            radio       = true,
            checked_func = function() return Screen:getRotationMode() == mode end,
            callback    = function(touchmenu_instance)
                if Screen:getRotationMode() ~= mode then
                    setRotation(mode)
                end
                touchmenu_instance:closeMenu()
                self:updateIcon()
            end,
            check_callback_closes_menu = true,
        }
    end

    local items = {
        genateMenuItem(_("Portrait"),            Screen.DEVICE_ROTATED_UPRIGHT,      "rotation.P.0UR"),
        genateMenuItem(_("Landscape"),           Screen.DEVICE_ROTATED_CLOCKWISE,     "rotation.L.90CW"),
        genateMenuItem(_("Inverted portrait"),   Screen.DEVICE_ROTATED_UPSIDE_DOWN,   "rotation.P.180UD"),
        genateMenuItem(_("Inverted landscape"),  Screen.DEVICE_ROTATED_COUNTER_CLOCKWISE, "rotation.L.90CCW"),
    }

    return items
end

function RotationWidget:showMenu()
    local item_table = autoRotationAvailable() and self:menuAutoRotation() or self:menuManual()

    -- TouchMenu expects a tab_item_table structure
    local first_tab = { icon = self.icon }
    for i, it in ipairs(item_table) do
        first_tab[i] = it
    end
    local tab_item_table = { first_tab }

    local menu_container = require("ui/widget/container/centercontainer"):new{
        dimen = Screen:getSize(),
        ignore = "height",
    }

    local menu = TouchMenu:new{
        width = Screen:getWidth(),
        tab_item_table = tab_item_table,
        show_parent = menu_container,
        close_callback = function()
            UIManager:close(self)
            UIManager:close(menu_container)
            self:updateIcon()
        end,
    }

    if menu.footer then
        -- Make footer zero height to hide it (we can't remove it without breaking TouchMenu)
        menu.footer:clear()
        function menu.footer:getSize() return {w = 0, h = 0} end
    end
    if menu.footer_top_margin then
        menu.footer_top_margin.width = 0
        function menu.footer_top_margin:getSize() return {w = 0, h = 0} end
    end

    menu_container[1] = menu

    UIManager:show(menu_container)
end

return RotationWidget 