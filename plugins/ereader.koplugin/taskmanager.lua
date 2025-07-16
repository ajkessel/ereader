-- TaskManager: background runner for eReader plugin without blocking UI
-- Runs a function inside an OS subprocess, periodically polling until it
-- completes.  We do NOT capture or cancel on user input, so the rest of the
-- UI stays usable while the task is running.

local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ffiutil = require("ffi/util")
local buffer = require("string.buffer")
local logger = require("logger")

local TaskManager = {}

--- Run a long task in the background.
-- @param task          function() returning (success, ...)
-- @param callback      function(success, ...) called on completion
function TaskManager.run(task, callback)
    Trapper:wrap(function()
        -- We skip visible overlays to keep UI completely unobstructed.
        local info = nil -- no overlay
        logger.dbg("ereader: began background task…")

        -- Launch the task in a subprocess with a pipe.
        local pid, parent_fd = ffiutil.runInSubProcess(function(_, child_fd)
            local ok, r1, r2 = pcall(task)
            local tbl = { ok, r1, r2 }
            local str = buffer.encode(tbl)
            ffiutil.writeToFD(child_fd, str, true) -- closes fd in child
        end, true)
        if not pid then
            logger.dbg("ereader: background task failed to start")
            if info then UIManager:close(info) end
            if callback then callback(false, parent_fd) end -- parent_fd contains error string on failure here
            return
        end

        -- Poll helper
        local function poll()
            local done = ffiutil.isSubProcessDone(pid)
            local ready = parent_fd and ffiutil.getNonBlockingReadSize(parent_fd) ~= 0
            if done or ready then
                local data = parent_fd and ffiutil.readAllFromFD(parent_fd) or ""
                if info then UIManager:close(info) end
                local ok, r1, r2
                if #data > 0 then
                    local dec_ok, tbl = pcall(buffer.decode, data)
                    if dec_ok and tbl then
                        ok, r1, r2 = tbl[1], tbl[2], tbl[3]
                    end
                end
                logger.dbg("ereader: background task completed")
                if callback then callback(ok, r1, r2) end
            else
                UIManager:scheduleIn(0.2, poll)
            end
        end
        poll()
    end)
end

return TaskManager
