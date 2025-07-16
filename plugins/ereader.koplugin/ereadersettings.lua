--[[
Ereader settings view and helper functions.
Handles persistent user preferences for the eReader plugin and exposes
methods to open the settings UI.

Usage (from main.lua):
    local Settings = require("ereadersettings")
    Settings:show() -- to open the settings page
    local n = Settings:getArticlesToDownload() -- retrieve value
]]

local _ = require("gettext")
local UIManager = require("ui/uimanager")
local KeyValuePage = require("ui/widget/keyvaluepage")
local InputDialog = require("ui/widget/inputdialog")
local ConfirmBox = require("ui/widget/confirmbox")
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")

local Settings = {}
Settings.__index = Settings

local SETTINGS_FILE = DataStorage:getSettingsDir().."/ereader.lua"
local SETTINGS_KEY  = "ereader"
local DEFAULT_ARTICLES = 10

local _instance = nil

local function loadSettings()
    local s = LuaSettings:open(SETTINGS_FILE)
    return s:readSetting(SETTINGS_KEY, {}) , s
end

function Settings:new()
    if _instance then
        return _instance
    end
    
    local o = {
        kv_page = nil,
    }
    setmetatable(o, self)
    self.__index = self
    
    _instance = o
    return o
end

-- Public helpers ------------------------------------------------------------
function Settings:getArticlesToDownload()
    local data = loadSettings()
    local val = tonumber(data.articles_to_download) or DEFAULT_ARTICLES
    if val < 1 then val = 1 end
    return val
end

function Settings:setArticlesToDownload(value)
    value = tonumber(value)
    if not value or value < 1 then return false end
    local data, settings = loadSettings()
    data.articles_to_download = value
    settings:saveSetting(SETTINGS_KEY, data)
    settings:flush()
    return true
end

-- Authentication settings ----------------------------------------------------
function Settings:getOAuthToken()
    local data = loadSettings()
    return data.instapaper_oauth_token
end

function Settings:getOAuthTokenSecret()
    local data = loadSettings()
    return data.instapaper_oauth_token_secret
end

function Settings:getUsername()
    local data = loadSettings()
    return data.instapaper_username
end

function Settings:setOAuthToken(token)
    local data, settings = loadSettings()
    data.instapaper_oauth_token = token
    settings:saveSetting(SETTINGS_KEY, data)
    settings:flush()
end

function Settings:setOAuthTokenSecret(secret)
    local data, settings = loadSettings()
    data.instapaper_oauth_token_secret = secret
    settings:saveSetting(SETTINGS_KEY, data)
    settings:flush()
end

function Settings:setUsername(username)
    local data, settings = loadSettings()
    data.instapaper_username = username
    settings:saveSetting(SETTINGS_KEY, data)
    settings:flush()
end

function Settings:clearAll()
    -- Clear the entire settings file
    local settings = LuaSettings:open(SETTINGS_FILE)
    settings:delSetting(SETTINGS_KEY)
    settings:flush()
end

-- UI helpers ----------------------------------------------------------------
function Settings:_promptArticlesToDownload()
    local current_val = self:getArticlesToDownload()
    local dialog
    dialog = InputDialog:new{
        title = _("Article auto-download limit"),
        description = _("When syncing, eReader will automatically download your most recent articles, up to this limit."),
        input = tostring(current_val),
        input_type = "number",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id   = "close",
                    callback = function()
                        UIManager:close(dialog)
                        self:show() -- reopen settings page if it was hidden
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local new_val = tonumber(dialog:getInputValue())
                        if not new_val or new_val < 1 then
                            UIManager:show(ConfirmBox:new{
                                text = _("Please enter a valid positive number."),
                                ok_text = _("OK"),
                            })
                            return
                        end
                        self:setArticlesToDownload(new_val)
                        UIManager:close(dialog)
                        self:show() -- refresh page
                    end,
                }
            }
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Settings:show()
    -- Close existing page if already open to refresh content
    if self.kv_page then
        UIManager:close(self.kv_page)
    end
    local kv_pairs = {
        {
            _("Article auto-download limit"),
            tostring(self:getArticlesToDownload()),
            callback = function()
                self:_promptArticlesToDownload()
            end,
        },
    }
    self.kv_page = KeyValuePage:new{
        title = _("eReader Settings"),
        value_overflow_align = "right",
        kv_pairs = kv_pairs,
        callback_return = function()
            UIManager:close(self.kv_page)
        end,
    }
    UIManager:show(self.kv_page)
end

-------------------------------------------------------------------------------
-- Module entrypoint ----------------------------------------------------------
-------------------------------------------------------------------------------
return Settings:new() 