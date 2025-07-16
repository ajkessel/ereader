local _ = require("gettext")
local UIManager = require("ui/uimanager")
local InstapaperManager = require("instapapermanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local Trapper = require("ui/trapper")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local KeyValuePage = require("ui/widget/keyvaluepage")
local UI = require("ui/trapper")
local Screen = require("device").screen
local DocSettings = require("docsettings")
local Device = require("device")
local ListView = require("ui/widget/listview")
local ImageWidget = require("ui/widget/imagewidget")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalSpan = require("ui/widget/verticalspan")
local Font = require("ui/font")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local GestureRange = require("ui/gesturerange")
local IconButton = require("ui/widget/iconbutton")
local Blitbuffer = require("ffi/blitbuffer")
local Size = require("ui/size")
local Geom = require("ui/geometry")
local TitleBar = require("ui/widget/titlebar")
local OverlapGroup = require("ui/widget/overlapgroup")
local Button = require("ui/widget/button")
local Event = require("ui/event")
local NetworkMgr = require("ui/network/manager")
local TaskManager = require("taskmanager")

local Ereader = WidgetContainer:extend{
    name = "eReader",
    list_view = nil,
    main_view = nil,
    title_bar = nil,
}

-- DEVELOPMENT ONLY: Load stored credentials from api_keys.txt for testing convenience
local function loadDevCredentials()
    local stored_username = ""
    local stored_password = ""
    
    local home = "/mnt/onboard/"
    if Device:isEmulator() then
        home = os.getenv("HOME")
    end
    local secrets_path = home .. "/.config/koreader/auth.txt"
    logger.err("ereader: secrets_path:", secrets_path)
    local file = io.open(secrets_path, "r")
    if file then
        local content = file:read("*all")
        file:close()
        
        for key, value in string.gmatch(content, '"([^"]+)"%s*=%s*"([^"]+)"') do
            if key == "instapaper_username" then
                stored_username = value
            elseif key == "instapaper_password" then
                stored_password = value
            end
        end
    end
    return stored_username, stored_password
end

function Ereader:init()
    self.instapaperManager = InstapaperManager:instapaperManager()
    
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)    
    end

    if self.ui and self.ui.link then
        self.ui.link:addToExternalLinkDialog("instapaper", function(this, link_url)
            return {
                text = _("Save to Instapaper"),
                callback = function()
                    UIManager:close(this.external_link_dialog)
                    this.ui:handleEvent(Event:new("AddToInstapaper", link_url))
                end,
            }
        end)
    end
end

function Ereader:addToMainMenu(menu_items)
    menu_items.ereader = {
        text = "Ereader",
        callback = function()
            Trapper:wrap(function()
                self:showUI()
            end)
        end,
    }
end

function Ereader:showUI() 
    if not self:checkAPIKeys() then
        return
    end

    self:showArticles() 

    if not self.instapaperManager:isAuthenticated() then
        self.has_not_synced = true
        self:showLoginDialog()
    end
end

function Ereader:checkAPIKeys()
       -- Check if API keys are available
       local secrets = require("lib/ffi_secrets")
       if not secrets.has_secrets() then
           UIManager:show(ConfirmBox:new{
               text = [[
               Instapaper API credentials are required but not found. This may mean that the plugin has not been compiled for your platform.
               
               To set up the plugin for development/testing, you can use the following method:
               
               1. Get your Instapaper API credentials from:
                  https://www.instapaper.com/main/request_oauth_consumer_token
               
               2. Create a file called 'secrets.txt' in ~/.config/koreader/ with:
                  "instapaper_ouath_consumer_key" = "YOUR_CONSUMER_KEY"
                  "instapaper_oauth_consumer_secret" = "YOUR_CONSUMER_SECRET"
               ]],
               ok_text = _("OK"),
           })
           return false
       end

       return true
end

function Ereader:showLoginDialog()
    -- DEVELOPMENT ONLY: Pre-fill credentials for testing
    local stored_username, stored_password = loadDevCredentials()

    
    self.login_dialog = MultiInputDialog:new{
        title = _("Instapaper Login"),
        fields = {
            {
                text = stored_username,
                hint = _("Username"),
            },
            {
                text = stored_password,
                text_type = "password",
                hint = _("Password"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.login_dialog)
                    end,
                },
                {
                    text = _("Login"),
                    is_enter_default = true,
                    callback = function()
                        local fields = self.login_dialog:getFields()
                        local username = fields[1]:gsub("^%s*(.-)%s*$", "%1") -- trim whitespace
                        local password = fields[2]
                        
                        if username == "" or password == "" then
                            UIManager:show(ConfirmBox:new{
                                text = _("Please enter both username and password."),
                                ok_text = _("OK"),
                            })
                            return
                        end
                        
                        -- Use runWhenOnline to handle Wi-Fi reconnection non-blockingly
                        NetworkMgr:runWhenOnline(function()
                            -- Show loading message
                            local info = InfoMessage:new{ text = _("Logging in...") }
                            UIManager:show(info)
                            
                            -- Perform authentication
                            local success, error_message = self.instapaperManager:authenticate(username, password)

                            UIManager:close(info)

                            if success then
                                self:setStatusMessage(_("Syncing…"))
                                UIManager:close(self.login_dialog)
                                local articles_to_download = 5
                                -- initial sync can take a while, so show a message

                                TaskManager.run(function()
                                    return self.instapaperManager:synchWithAPI()
                                end, function(success, error_message)
                                    if success then
                                        -- download the first 20 articles
                                        self:showArticles()
                                        local articles = self.instapaperManager:getArticles()
                                        local downloaded_articles = 0
                                        for i = 1, articles_to_download do
                                            if i > #articles then
                                                self:setStatusMessage(_(""))
                                                goto continue
                                            end
                                            local article = articles[i]
                                            TaskManager.run(function()
                                                return self.instapaperManager:downloadArticle(article.bookmark_id)
                                            end, function(success, error_message)
                                                downloaded_articles = downloaded_articles + 1
                                                if success then
                                                    -- Refresh list only if it's still the active view
                                                    local UIManager = require("ui/uimanager")
                                                    if self.main_view == UIManager:getTopmostVisibleWidget() then
                                                        self:showArticles()
                                                        if downloaded_articles > #articles or downloaded_articles == articles_to_download then
                                                            self:setStatusMessage(_("Article downloads complete"), 2)
                                                            self.has_not_synced = false
                                                        else 
                                                            self:setStatusMessage(_("Downloading " .. article.title .. "…"))
                                                        end
                                                    end
                                                end
                                            end)
                                            ::continue::
                                        end
                                    else
                                        UIManager:show(ConfirmBox:new{
                                            text = _("Sync failed: " .. (error_message or "")),
                                            ok_text = _("OK"),
                                        })
                                    end
                                end)
                            else 
                                UIManager:show(ConfirmBox:new{
                                    text = _("Could not log in: " .. error_message),
                                    ok_text = _("OK"),
                                })
                            end
                        end)
                    end,
                },
            },
        },
    }
    UIManager:show(self.login_dialog)
    self.login_dialog:onShowKeyboard()
end

-- Create a custom article item widget
local ArticleItem = InputContainer:extend{
    name = "article_item",
    article = nil,
    width = nil,
    height = nil,
    background = nil,
    callback = nil,
}

function ArticleItem:init()
    self.dimen = Geom:new{x = 0, y = 0, w = self.width, h = self.height}
    
    -- Create article content
    local title_text = self.article.title or "Untitled"
    local domain = self.instapaperManager.getDomain(self.article.url) or "No URL"
    
    -- Download status indicator
    local download_icon = nil
    local is_downloaded = self.article.html_size and self.article.html_size > 0
    if is_downloaded then
        download_icon = TextWidget:new{
            alignment = "left",
            text = "⇩",
            face = Font:getFace("infont", 20),
            max_width = Screen:scaleBySize(20),
        }
    end
    
    -- Thumbnail widget
    local thumbnail_size = Screen:scaleBySize(60)
    local thumbnail_path = self.instapaperManager:getArticleThumbnail(self.article.bookmark_id)
    local thumbnail_widget
    
    if thumbnail_path then
        -- Create image widget with actual thumbnail
        thumbnail_widget = ImageWidget:new{
            file = thumbnail_path,
            width = thumbnail_size,
            height = thumbnail_size,
            scale_factor = nil, -- Scale to fit
        }
    elseif is_downloaded then
        -- Create placeholder with grey background
        thumbnail_widget = Button:new{
            icon = "notice-question",
            bordersize = 3,
            border_color = Blitbuffer.COLOR_DARK_GRAY,
            background = Blitbuffer.COLOR_WHITE,
            width = thumbnail_size,
            height = thumbnail_size,
        }
    else
        -- Creat an empty placeholder with grey background
        thumbnail_widget = Button:new{
            text = "",
            bordersize = 3,
            border_color = Blitbuffer.COLOR_DARK_GRAY,
            background = Blitbuffer.COLOR_GRAY_E,
            width = thumbnail_size,
            height = thumbnail_size,
        } 
    end
    
    -- Title widget
    local title_widget = TextWidget:new{
        text = title_text,
        fgcolor = is_downloaded and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
        face = Font:getFace("x_smalltfont", 16),
        max_width = self.width - thumbnail_size - Screen:scaleBySize(60), -- Leave space for thumbnail and download icon
        width = self.width - thumbnail_size - Screen:scaleBySize(60),
    }
    
    -- Domain widget
    local domain_widget = TextWidget:new{
        text = domain,
        fgcolor = is_downloaded and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK,
        face = Font:getFace("infont", 14),
        max_width = self.width - thumbnail_size - Screen:scaleBySize(60), -- Leave space for thumbnail and download icon
        width = self.width - thumbnail_size - Screen:scaleBySize(60),
    }
    
    -- Layout: title and domain stacked vertically
    local text_group = VerticalGroup:new{
        align = "left",
        title_widget,
        VerticalSpan:new{ height = Screen:scaleBySize(4) },
        domain_widget,
    }
    
    -- Main content with thumbnail on the left and download icon on the right
    local content_group
    if download_icon then
        content_group = OverlapGroup:new {
            dimen = self.dimen:copy(),
            HorizontalGroup:new{
                align = "top",
                thumbnail_widget,
                HorizontalSpan:new{ width = Screen:scaleBySize(10) },
                text_group,
            },
            RightContainer:new{
                align = "center",
                dimen = Geom:new{ w = self.width - Screen:scaleBySize(20), h = self.height },
                download_icon,
            },
        }
    else
        content_group = HorizontalGroup:new{
            align = "top",
            thumbnail_widget,
            HorizontalSpan:new{ width = Screen:scaleBySize(10) },
            text_group,
        }
    end
    
    -- Container with background and padding
    self[1] = FrameContainer:new{
        background = self.background or Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        width = self.width,
        height = self.height,
        content_group,
    }
    
    -- Register touch events - only handle taps, not swipes
    if Device:isTouchDevice() then
        self.ges_events.TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            }
        }
        -- Don't register swipe events to avoid blocking ListView swipes
    end
end

function ArticleItem:onTapSelect(arg, ges_ev)
    if self.callback then
        self.callback()
    end
    return true
end

-- Don't handle swipe events - let them pass through to ListView
function ArticleItem:onSwipe(arg, ges_ev)
    return false -- Let the event bubble up to parent
end

function Ereader:showArticles()
    local current_list_page = 1
    local current_subtitle = ""
    if self.list_view then
        current_list_page = self.list_view.show_page
        current_subtitle = self.title_bar.subtitle_widget.text
        UIManager:close(self.main_view)
    end

    -- Get articles from database store
    local articles = self.instapaperManager:getArticles()
    
    logger.dbg("ereader: Got", #articles, "articles from database")
    
    -- Create article item widgets
    local items = {}
    local item_height = Screen:scaleBySize(80) -- Fixed height for all items
    local width = Screen:getWidth()
    
    if articles and #articles > 0 then
        for i = 1, #articles do
            local article = articles[i]
            local background = (i % 2 == 0) and Blitbuffer.COLOR_GRAY_E or Blitbuffer.COLOR_WHITE
            
            local item = ArticleItem:new{
                width = width,
                height = item_height,
                background = background,
                article = article,
                instapaperManager = self.instapaperManager,
                callback = function()
                    self:loadArticleContent(article)
                end,
            }
            table.insert(items, item)
        end
    else
        -- Show "no articles" message
        local no_articles_item = FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = Screen:scaleBySize(20),
            CenterContainer:new{
                dimen = Geom:new{ w = width, h = item_height },
                TextWidget:new{
                    text = self.has_not_synced and "" or "No articles synced yet",
                    face = Font:getFace("cfont"),
                },
            },
        }
        table.insert(items, no_articles_item)
    end
    
    -- Create title bar with title and menu button
    local title_bar_height = Screen:scaleBySize(50)
    self.title_bar = TitleBar:new{
        width = width,
        align = "left",
        title = _("eReader"),
        subtitle = current_subtitle, -- used for status messages
        subtitle_face = Font:getFace("xx_smallinfofont", 14),
        title_top_padding = Screen:scaleBySize(4),
        title_bottom_padding = Screen:scaleBySize(4),
        title_subtitle_v_padding = Screen:scaleBySize(0),
        button_padding = Screen:scaleBySize(10),
        left_icon_size_ratio = 1,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function()
            self:showMenu()
        end,
        right_icon = "close",
        right_icon_tap_callback = function()
            UIManager:show(ConfirmBox:new{
                text = _("Quit eReader and return to Kobo?"),
                icon = "notice-question",
                ok_text = _("Quit"),
                cancel_text = _("Cancel"),
                ok_callback = function()
                    -- Exit KOReader entirely
                    os.exit(0)
                end,
            })
        end,
        show_parent = self,
    }
    
    -- Create ListView
    local list_height = Screen:getHeight() - title_bar_height
    self.list_view = ListView:new{
        width = width,
        height = list_height,
        items = items,
        padding = 0,
        margin = 0,
        bordersize = 0,
        page_update_cb = function(curr_page, total_pages)
            -- Trigger screen refresh when page changes
            UIManager:setDirty(self.main_view, function()
                return "ui", self.main_view.dimen
            end)
        end,
    }
    
    -- Create main container
    self.main_view = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        width = width,
        VerticalGroup:new{
            align = "left",
            self.title_bar,
            self.list_view,
        },
    }
    
    -- Forward key events for dev shortcuts and page navigation
    self.main_view.onKeyPress = function(widget, key, mods, is_repeat)
        -- Handle page navigation
        if key.key == "Left" or key.key == "Up" or key.key == "RPgBack" then
            self.list_view:prevPage()
            return true
        elseif key.key == "Right" or key.key == "Down" or key.key == "RPgFwd" then
            self.list_view:nextPage()
            return true
        end
        
        -- Handle dev shortcuts
        if self.onKeyPress then
            return self:onKeyPress(key, mods, is_repeat)
        end
        return false
    end
    
    self.main_view.onSetRotationMode = function(widget, mode)
        Screen:setRotationMode(mode)
        UIManager:nextTick(function()
            self:showArticles()
        end)
        return true
    end


    if current_list_page > 1 then
        self.list_view.show_page = current_list_page
        self.list_view:_populateItems()
    end
    UIManager:show(self.main_view)
end

function Ereader:showMenu()
    local last_sync = self.instapaperManager:getLastSyncTime()
    local sync_string = "Sync"
    if last_sync then
        local sync_time = os.date("%m-%d %H:%M", tonumber(last_sync))
        sync_string = ("Sync (last: " .. sync_time .. ")")
    end
    local Menu = require("ui/widget/menu")
    local menu_container = Menu:new{
        width = Screen:getWidth() * 0.8,
        height = Screen:getHeight() * 0.8,
        is_enable_shortcut = false,
        item_table = {
            {
                text = sync_string,
                callback = function()
                    -- Use runWhenOnline to ensure Wi-Fi, then run task out of process
                    NetworkMgr:runWhenOnline(function()
                        TaskManager.run(function()
                            self:setStatusMessage(_("Syncing…"))
                            return self.instapaperManager:synchWithAPI()
                        end, function(success, error_message)
                            if success then
                                self:setStatusMessage(_("Sync complete"), 2)
                                self:showArticles()
                            else
                                UIManager:show(ConfirmBox:new{
                                    text = _("Sync failed: " .. (error_message or "")),
                                    ok_text = _("OK"),
                                })
                            end
                        end)
                    end)
                end,
            },
            {
                text = _("Log out (" .. (self.instapaperManager.instapaper_api_manager.username or "unknown user") .. ")"),
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Logout of Instapaper?"),
                        ok_text = _("Logout"),
                        cancel_text = _("Cancel"),
                        ok_callback = function()
                            self.instapaperManager:logout()
                            self.has_not_synced = true
                            self:showArticles() -- force refresh
                            self:showLoginDialog()
                        end,
                    })
                end,
            },
            {
                text = _("Exit to KOReader"),
                callback = function()
                    UIManager:close(menu_container)
                    -- Close the current Ereader UI
                    if self.main_view then
                        UIManager:close(self.main_view)
                    end
                    -- Open the File Manager
                    local FileManager = require("apps/filemanager/filemanager")
                    FileManager:showFiles()
                end,
            },
        },
    }
    UIManager:show(menu_container)
end

function Ereader:setStatusMessage(message, timeout)
    if not self.title_bar.subtitle_widget then
        return
    end

    self.title_bar.subtitle_widget:setText(message)
    UIManager:setDirty(self.main_view, function() -- not sure why this is needed, titlebar will sometimes not update without it
        return "ui", self.main_view.dimen
    end)

    if timeout then
        UIManager:scheduleIn(timeout, function()
            self.title_bar.subtitle_widget:setText("")
            UIManager:setDirty(self.main_view, function()
                return "ui", self.main_view.dimen
            end)
        end)
    end
end

function Ereader:loadArticleContent(article)
    local filepath = self.instapaperManager:getCachedArticleFilePath(article.bookmark_id)
    if filepath then
        self:showReaderForArticle(article, filepath)
    else
        NetworkMgr:runWhenOnline(function()
            local info = InfoMessage:new{ text = _("Downloading " .. article.title .. "…") }
            UIManager:show(info)
            info.onTapClose = function()
                logger.dbg("ereader: download info window closed")
                self:setStatusMessage(_("Downloading " .. article.title .. "…"))
                UIManager:close(info)
            end

            TaskManager.run(function()
                return self.instapaperManager:downloadArticle(article.bookmark_id)
            end, function(success, error_message)
                if success then
                    if UIManager:isSubwidgetShown(info) then -- if the user dismissed the download info window, don't launch it automatically
                        UIManager:close(info)
                        local filepath = self.instapaperManager:getCachedArticleFilePath(article.bookmark_id)
                        if filepath then
                            self:showReaderForArticle(article, filepath)
                        end
                    else 
                        self:setStatusMessage("Download complete", 2)
                    end
            
                    -- update the article list to show the downloaded article
                    self:showArticles()
                else 
                    UIManager:show(ConfirmBox:new{
                        text = _("Failed to load article: ") .. (error_message or _("Unknown error")),
                        ok_text = _("OK"),
                    })
                end
            end)
        end)
    end
end

function Ereader:showReaderForArticle(article, filepath)
    -- Store the current article for the ReaderEreader module
    self.current_article = article
        
    -- Open the stored HTML file directly in KOReader
    local ReaderUI = require("apps/reader/readerui")
    local doc_settings = DocSettings:open(filepath)
    local current_rotation = Screen:getRotationMode()
    doc_settings:saveSetting("kopt_rotation_mode", current_rotation)
    doc_settings:saveSetting("copt_rotation_mode", current_rotation)
    doc_settings:flush()
    ReaderUI:showReader(filepath)

    -- Register our Ereader module after ReaderEreader is created
    UIManager:scheduleIn(0.1, function()
        if ReaderUI.instance then
            local ReaderEreader = require("readerereader")
            local module_instance = ReaderEreader:new{
                ui = ReaderUI.instance,
                dialog = ReaderUI.instance,
                view = ReaderUI.instance.view,
                document = ReaderUI.instance.document,
                refresh_callback = function()
                    -- Refresh the Ereader list view when returning from reader
                    self:showArticles()
                end,
            }
            ReaderUI.instance:registerModule("readerereader", module_instance)
            UIManager:nextTick(function()
                -- get article highlights, load async
                TaskManager.run(function()
                    return self.instapaperManager:getArticleHighlights(article.bookmark_id)
                end, function(success, error_message)
                    if not success then
                        logger.dbg("ereader: get highlights failed:", result)
                    end
                    -- loadHighlights, will fall back on local cache if getArticleHighlights fails
                    module_instance:reloadHighlights()
                end)
            end)
        end
    end)
end

--- Handler for our button in the ReaderEreader's link menu
function Ereader:onAddToInstapaper(url)
    local success, error_message, did_enqueue = self.instapaperManager:addArticle(url)

    if success then
        UIManager:show(InfoMessage:new{
            text = (did_enqueue and "Article will be saved in next sync") or "Saved to Instapaper",
            icon = "check",
            timeout = 2,
        })
    else
        UIManager:show(InfoMessage:new{
            text = "Error saving to Instapaper: " .. error_message,
            icon = "notice-error",
        })
    end
    return true
end

function Ereader:onKeyPress(key, mods, is_repeat)

    if Device:isEmulator() and (key.key == "F4") then
        for l, v in pairs(key.modifiers) do
            if v then
                return false
            end
        end
        local current = Screen:getRotationMode()
        local new_mode = (current + 1) % 4
        self.main_view.onSetRotationMode(self.main_view, new_mode)
        return true
    end
    return false
end

return Ereader
