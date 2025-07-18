local Device = require("device")
local IconButton = require("ui/widget/iconbutton")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local WiFiStatusWidget = IconButton:extend{
    name = "wifi_status_widget",
    width = nil,
    height = nil,
    padding = nil,
    overlap_align = "right",
    show_parent = nil,
}

function WiFiStatusWidget:init()
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
    
    -- Set initial icon
    self:updateIcon()
    
    -- Set up callback
    self.callback = function()
        self:toggleWiFi()
    end
    
    -- Call parent init
    IconButton.init(self)
end

function WiFiStatusWidget:toggleWiFi()
    logger.dbg("ereader: toggling…")
    local callback = function()
        logger.dbg("ereader: toggleWiFi: callback")
        self:updateIcon()
    end

    if NetworkMgr:isWifiOn() then
        NetworkMgr:toggleWifiOff(callback)
    else
        NetworkMgr:toggleWifiOn(callback)
    end
end

function WiFiStatusWidget:getWiFiIcon()
    if not NetworkMgr:isWifiOn() then
        return "wifi.off"
    end
    
    -- Get current network information
    local current_network = NetworkMgr:getCurrentNetwork()
    if not current_network then
        return "wifi.open.0"
    end
    
    -- Try to get signal quality directly from wpa_cli status (much more efficient than scanning)
    local signal_quality = 0
    local flags = ""
    
    -- Use wpa_cli status to get current network info including signal strength
    local interface = NetworkMgr:getNetworkInterfaceName()
    if interface then
        local cmd = string.format("wpa_cli -i %s status", interface)
        local handle = io.popen(cmd, "r")
        if handle then
            local output = handle:read("*all")
            handle:close()
            
            if output then
                -- Parse wpa_cli status output
                for line in output:gmatch("[^\r\n]+") do
                    local key, value = line:match("^([^=]+)=(.+)$")
                    if key and value then
                        if key == "signal" then
                            -- Convert signal strength to quality (similar to NetworkSetting logic)
                            local signal = tonumber(value) or 0
                            -- Map signal strength to quality (rough approximation)
                            -- Signal strength is typically in dBm, ranging from -100 to -30
                            if signal >= -50 then
                                signal_quality = 100
                            elseif signal >= -60 then
                                signal_quality = 75
                            elseif signal >= -70 then
                                signal_quality = 50
                            elseif signal >= -80 then
                                signal_quality = 25
                            else
                                signal_quality = 0
                            end
                        elseif key == "key_mgmt" then
                            flags = value
                        end
                    end
                end
            end
        end
    end
    
    -- Fallback: if we couldn't get signal quality from wpa_cli, try a minimal scan
    if signal_quality == 0 then
        local network_list, err = NetworkMgr:getNetworkList()
        if network_list then
            for _, network in ipairs(network_list) do
                if network.connected and network.ssid == current_network.ssid then
                    signal_quality = network.signal_quality or 0
                    flags = network.flags or ""
                    break
                end
            end
        end
    end
    
    -- Use the same logic as NetworkSetting for determining signal strength icon
    local wifi_icon
    if flags and string.find(flags, "WPA") then
        wifi_icon = "wifi.secure.%d"
    else
        wifi_icon = "wifi.open.%d"
    end
    
    -- Based on NetworkManager's nmc_wifi_strength_bars
    -- c.f., https://github.com/NetworkManager/NetworkManager/blob/2fa8ef9fb9c7fe0cc2d9523eed6c5a3749b05175/clients/common/nm-client-utils.c#L585-L612
    if signal_quality > 80 then
        wifi_icon = string.format(wifi_icon, 100)
    elseif signal_quality > 55 then
        wifi_icon = string.format(wifi_icon, 75)
    elseif signal_quality > 30 then
        wifi_icon = string.format(wifi_icon, 50)
    elseif signal_quality > 5 then
        wifi_icon = string.format(wifi_icon, 25)
    else
        wifi_icon = string.format(wifi_icon, 0)
    end
    
    return wifi_icon
end

function WiFiStatusWidget:updateIcon()
    local new_icon = self:getWiFiIcon()
    if self.icon ~= new_icon then
        self:setIcon(new_icon)
        UIManager:setDirty("all", "ui")
        logger.dbg("ereader: Updated wifi icon to", new_icon)
    end
end


function WiFiStatusWidget:onNetworkConnected()
    self:updateIcon()
end

function WiFiStatusWidget:onToggleWifi()
    self:updateIcon()
end

function WiFiStatusWidget:onNetworkDisconnected()
    self:updateIcon()
end

function WiFiStatusWidget:schedulePeriodicUpdates()
    UIManager:scheduleIn(30, function()
        if self.updateIcon then
            self:updateIcon()
        end
        -- Reschedule
        self:schedulePeriodicUpdates()
    end)
end

return WiFiStatusWidget 