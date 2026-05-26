--[[
    obsidian-sync.koplugin/main.lua  — revision 3

    Changes from r2:
      • Auto-sync every N pages (onPageUpdate / onPosUpdate hooks)
      • Auto-sync on device sleep (onSuspend hook)
      • Both settings toggled directly from the reader menu
      • Silent auto-sync (no blocking dialogs) — only shows a brief toast

    Changes from r1:
      • Pure-Lua MD5 replaces ffi/sha2 (FFI not reliable on Android)
      • All optional requires (socket, ltn12, json) are lazy + pcall-wrapped
      • socket.http.TIMEOUT set to prevent Android ANR
      • Sequential InputDialogs replace MultiInputDialog (wider compatibility)
      • pcall around all document-API calls in buildPayload

    Install: copy the obsidian-sync.koplugin/ folder into
             <koreader>/plugins/   (restart KOReader afterwards)
--]]

-- =========================================================================
-- 1. Pure-Lua MD5  ── no FFI, no external library, works everywhere
--    Uses LuaJIT's built-in "bit" library (always available in KOReader)
-- =========================================================================
local function makeMD5()
    local bit    = require("bit")           -- LuaJIT built-in, always present
    local band   = bit.band
    local bor    = bit.bor
    local bxor   = bit.bxor
    local bnot   = bit.bnot
    local rshift = bit.rshift               -- logical (unsigned) right-shift
    local rol    = bit.rol
    local tobit  = bit.tobit

    -- MD5 T-table: floor(2^32 × |sin(i)|)  for i = 1..64
    -- Values pre-computed to avoid floating-point rounding issues.
    local T = {
        tobit(0xd76aa478), tobit(0xe8c7b756), tobit(0x242070db), tobit(0xc1bdceee),
        tobit(0xf57c0faf), tobit(0x4787c62a), tobit(0xa8304613), tobit(0xfd469501),
        tobit(0x698098d8), tobit(0x8b44f7af), tobit(0xffff5bb1), tobit(0x895cd7be),
        tobit(0x6b901122), tobit(0xfd987193), tobit(0xa679438e), tobit(0x49b40821),
        tobit(0xf61e2562), tobit(0xc040b340), tobit(0x265e5a51), tobit(0xe9b6c7aa),
        tobit(0xd62f105d), tobit(0x02441453), tobit(0xd8a1e681), tobit(0xe7d3fbc8),
        tobit(0x21e1cde6), tobit(0xc33707d6), tobit(0xf4d50d87), tobit(0x455a14ed),
        tobit(0xa9e3e905), tobit(0xfcefa3f8), tobit(0x676f02d9), tobit(0x8d2a4c8a),
        tobit(0xfffa3942), tobit(0x8771f681), tobit(0x6d9d6122), tobit(0xfde5380c),
        tobit(0xa4beea44), tobit(0x4bdecfa9), tobit(0xf6bb4b60), tobit(0xbebfbc70),
        tobit(0x289b7ec6), tobit(0xeaa127fa), tobit(0xd4ef3085), tobit(0x04881d05),
        tobit(0xd9d4d039), tobit(0xe6db99e5), tobit(0x1fa27cf8), tobit(0xc4ac5665),
        tobit(0xf4292244), tobit(0x432aff97), tobit(0xab9423a7), tobit(0xfc93a039),
        tobit(0x655b59c3), tobit(0x8f0ccc92), tobit(0xffeff47d), tobit(0x85845dd1),
        tobit(0x6fa87e4f), tobit(0xfe2ce6e0), tobit(0xa3014314), tobit(0x4e0811a1),
        tobit(0xf7537e82), tobit(0xbd3af235), tobit(0x2ad7d2bb), tobit(0xeb86d391),
    }

    -- Per-operation left-rotation amounts (RFC 1321 §3.4)
    local S = {
         7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
         5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
         4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
         6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,
    }

    -- Encode 32-bit word as 4 little-endian hex bytes
    local function u32le_hex(n)
        local s = ""
        for _ = 1, 4 do
            s = s .. string.format("%02x", band(n, 0xFF))
            n = rshift(n, 8)        -- logical shift: zero-fills from left
        end
        return s
    end

    -- The actual MD5 function
    return function(message)
        -- Padding (RFC 1321 §3.1 & §3.2)
        local orig_len = #message
        local pad = 56 - (orig_len + 1) % 64
        if pad < 0 then pad = pad + 64 end
        message = message .. "\x80" .. string.rep("\0", pad)
        -- Original length in bits as 64-bit little-endian (§3.2)
        local bits = orig_len * 8
        for _ = 1, 8 do
            message = message .. string.char(bits % 256)
            bits = math.floor(bits / 256)
        end

        -- Initial hash state (§3.3)
        local h0 = tobit(0x67452301)
        local h1 = tobit(0xEFCDAB89)
        local h2 = tobit(0x98BADCFE)
        local h3 = tobit(0x10325476)

        -- Process 64-byte (512-bit) blocks (§3.4)
        for blk = 1, #message, 64 do
            local M = {}
            for w = 0, 15 do
                local p = blk + w * 4
                M[w] = tobit(
                    message:byte(p)
                    + message:byte(p + 1) * 0x100
                    + message:byte(p + 2) * 0x10000
                    + message:byte(p + 3) * 0x1000000
                )
            end

            local a, b, c, d = h0, h1, h2, h3
            for k = 0, 63 do
                local f, g
                if k < 16 then
                    f = bor(band(b, c), band(bnot(b), d))
                    g = k
                elseif k < 32 then
                    f = bor(band(d, b), band(bnot(d), c))
                    g = (5 * k + 1) % 16
                elseif k < 48 then
                    f = bxor(b, bxor(c, d))
                    g = (3 * k + 5) % 16
                else
                    f = bxor(c, bor(b, bnot(d)))
                    g = (7 * k) % 16
                end
                local tmp = d
                d = c
                c = b
                b = tobit(b + rol(tobit(a + f + M[g] + T[k + 1]), S[k + 1]))
                a = tmp
            end
            h0 = tobit(h0 + a)
            h1 = tobit(h1 + b)
            h2 = tobit(h2 + c)
            h3 = tobit(h3 + d)
        end

        return u32le_hex(h0) .. u32le_hex(h1) .. u32le_hex(h2) .. u32le_hex(h3)
    end
end

local md5hex = makeMD5()   -- md5hex(str) → 32-char lowercase hex string

-- =========================================================================
-- 2. Core KOReader modules — guaranteed present on all platforms
-- =========================================================================
local DocSettings     = require("docsettings")
local InfoMessage     = require("ui/widget/infomessage")
local InputDialog     = require("ui/widget/inputdialog")
local NetworkMgr      = require("ui/network/manager")
local UIManager       = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger          = require("logger")
local _               = require("gettext")

-- =========================================================================
-- 3. Plugin class
-- =========================================================================
local ObsidianSync = WidgetContainer:extend{
    name          = "obsidiansync",
    fullname      = _("Obsidian Sync"),
    is_doc_plugin = true,
}

-- -------------------------------------------------------------------------
-- Init
-- -------------------------------------------------------------------------
function ObsidianSync:init()
    -- Merge saved settings over defaults so new keys always exist.
    local defaults = {
        server_url         = "http://192.168.1.100:7777",
        username           = "koreader",
        password           = "koreader",
        auto_sync_pages    = 0,     -- 0 = disabled; N = sync every N pages
        auto_sync_on_sleep = false, -- sync when the device goes to sleep
    }
    local saved = G_reader_settings:readSetting("obsidiansync") or {}
    for k, v in pairs(defaults) do
        if saved[k] == nil then saved[k] = v end
    end
    self.settings = saved

    self.last_sync_page   = nil   -- set on first page event
    self._pendingAutoSync = nil   -- scheduled-callback reference for unschedule
    self._is_syncing      = false -- guard against concurrent syncs
    self.ui.menu:registerToMainMenu(self)
end

-- -------------------------------------------------------------------------
-- Menu
-- -------------------------------------------------------------------------
function ObsidianSync:addToMainMenu(menu_items)
    menu_items.obsidian_sync = {
        text         = _("Obsidian Sync"),
        sorting_hint = "more_tools",
        sub_item_table = {
            -- Manual sync
            {
                text     = _("Sync this book now"),
                callback = function() self:syncCurrentBook() end,
                separator = true,
            },
            -- Auto-sync every N pages (shows current value in the label)
            {
                text_func = function()
                    local n = tonumber(self.settings.auto_sync_pages) or 0
                    if n > 0 then
                        return string.format(_("Auto-sync: every %d pages"), n)
                    else
                        return _("Auto-sync by pages: off")
                    end
                end,
                callback = function()
                    self:askAutoSyncPages()
                end,
            },
            -- Sleep trigger (checkbox-style toggle)
            {
                text = _("Auto-sync on sleep"),
                checked_func = function()
                    return self.settings.auto_sync_on_sleep == true
                end,
                callback = function()
                    self.settings.auto_sync_on_sleep =
                        not self.settings.auto_sync_on_sleep
                    self:_saveSettings()
                    UIManager:show(InfoMessage:new{
                        text = self.settings.auto_sync_on_sleep
                            and _("Sleep sync: ON")
                            or  _("Sleep sync: OFF"),
                        timeout = 2,
                    })
                end,
                separator = true,
            },
            -- Server settings
            {
                text     = _("Configure server…"),
                callback = function() self:askServerUrl() end,
            },
        },
    }
end

-- =========================================================================
-- 4. Settings — sequential InputDialogs (robust on Android)
--    Server settings: 3 steps (URL → user → pass)
--    Page-threshold: separate single dialog, opened from the menu
-- =========================================================================

function ObsidianSync:askServerUrl()
    local d
    d = InputDialog:new{
        title      = _("Obsidian Sync  (1/3) — Server URL"),
        input      = self.settings.server_url,
        input_hint = "http://192.168.x.x:7777",
        buttons    = {{
            {
                text     = _("Cancel"),
                callback = function() UIManager:close(d) end,
            },
            {
                text             = _("Next ›"),
                is_enter_default = true,
                callback         = function()
                    local v = d:getInputText()
                    UIManager:close(d)
                    if v ~= "" then self.settings.server_url = v end
                    self:askUsername()
                end,
            },
        }},
    }
    UIManager:show(d)
end

function ObsidianSync:askUsername()
    local d
    d = InputDialog:new{
        title      = _("Obsidian Sync  (2/3) — Username"),
        input      = self.settings.username,
        input_hint = "koreader",
        buttons    = {{
            {
                text     = _("‹ Back"),
                callback = function() UIManager:close(d); self:askServerUrl() end,
            },
            {
                text             = _("Next ›"),
                is_enter_default = true,
                callback         = function()
                    local v = d:getInputText()
                    UIManager:close(d)
                    if v ~= "" then self.settings.username = v end
                    self:askPassword()
                end,
            },
        }},
    }
    UIManager:show(d)
end

function ObsidianSync:askPassword()
    local d
    d = InputDialog:new{
        title      = _("Obsidian Sync  (3/3) — Password"),
        input      = self.settings.password,
        input_hint = "koreader",
        -- NOTE: do NOT set input_type = "password" here;
        -- that key is "text_type" in some builds and crashes others.
        buttons    = {{
            {
                text     = _("‹ Back"),
                callback = function() UIManager:close(d); self:askUsername() end,
            },
            {
                text             = _("Save"),
                is_enter_default = true,
                callback         = function()
                    local v = d:getInputText()
                    UIManager:close(d)
                    if v ~= "" then self.settings.password = v end
                    self:_saveSettings()
                    UIManager:show(InfoMessage:new{
                        text    = _("Settings saved."),
                        timeout = 2,
                    })
                end,
            },
        }},
    }
    UIManager:show(d)
end

-- Auto-sync page-threshold dialog (opened from the menu item)
function ObsidianSync:askAutoSyncPages()
    local current = tostring(self.settings.auto_sync_pages or 0)
    local d
    d = InputDialog:new{
        title       = _("Auto-sync every N pages"),
        description = _("Enter the number of pages between automatic syncs.\nSet to 0 to disable page-based auto-sync."),
        input       = current,
        input_type  = "number",
        buttons     = {{
            {
                text     = _("Cancel"),
                callback = function() UIManager:close(d) end,
            },
            {
                text             = _("Save"),
                is_enter_default = true,
                callback         = function()
                    local raw = d:getInputText()
                    UIManager:close(d)
                    local n = math.max(0, math.floor(tonumber(raw) or 0))
                    self.settings.auto_sync_pages = n
                    -- Reset tracker so the new threshold starts from now
                    self.last_sync_page = nil
                    self:_saveSettings()
                    UIManager:show(InfoMessage:new{
                        text = n > 0
                            and string.format(_("Auto-sync every %d pages: ON"), n)
                            or  _("Auto-sync by pages: OFF"),
                        timeout = 2,
                    })
                end,
            },
        }},
    }
    UIManager:show(d)
end

-- =========================================================================
-- 5. Sync
-- =========================================================================

function ObsidianSync:syncCurrentBook()
    NetworkMgr:runWhenOnline(function()
        -- Build payload
        local payload, build_err = self:buildPayload()
        if not payload then
            UIManager:show(InfoMessage:new{
                text = _("Could not read book data:\n") .. tostring(build_err),
            })
            return
        end

        -- Authenticate
        local auth_ok, auth_err = self:authenticate()
        if not auth_ok then
            UIManager:show(InfoMessage:new{
                text = _("Auth failed: ") .. tostring(auth_err)
                     .. "\n" .. _("Check server URL & credentials."),
            })
            return
        end

        -- Post annotations
        local code, resp_err = self:postAnnotations(payload)
        if code == 200 then
            UIManager:show(InfoMessage:new{
                text    = string.format(
                    _("✓ Synced %d annotations\nfor \"%s\""),
                    #(payload.annotations or {}),
                    payload.title
                ),
                timeout = 3,
            })
        else
            UIManager:show(InfoMessage:new{
                text = string.format(
                    _("Sync failed (HTTP %s)\n%s"),
                    tostring(code), tostring(resp_err)
                ),
            })
        end
    end)
end

-- =========================================================================
-- 6. Build payload
-- =========================================================================

function ObsidianSync:buildPayload()
    if not self.ui or not self.ui.document then
        return nil, "no document open"
    end

    local ok, result = pcall(function()
        local doc      = self.ui.document
        local doc_file = doc.file
        if not doc_file then error("doc.file is nil") end

        -- Prefer the LIVE in-memory DocSettings (self.ui.doc_settings) so
        -- that highlights added during the current reading session are
        -- included even before KOReader flushes them to disk.
        local doc_settings
        if self.ui.doc_settings then
            doc_settings = self.ui.doc_settings
        else
            doc_settings = DocSettings:open(doc_file)
        end

        -- Book properties (getProps may not exist on all doc types)
        local props = {}
        local ok2, p = pcall(function() return doc:getProps() end)
        if ok2 and type(p) == "table" then props = p end

        local percentage = doc_settings:readSetting("percent_finished") or 0
        local last_xptr  = doc_settings:readSetting("last_xpointer")    or ""
        local doc_hash   = doc_settings:readSetting("partial_md5_checksum") or ""

        -- ------------------------------------------------------------------
        -- Collect from all annotation sources with de-duplication.
        -- Key: datetime string (unique per annotation). Fallback key is a
        -- composite of page + first 30 chars of text.
        -- ------------------------------------------------------------------
        local seen = {}   -- dedup key → true
        local all  = {}

        local function makeKey(entry)
            if entry.datetime and entry.datetime ~= "" then
                return entry.datetime
            end
            return tostring(entry.page or 0)
                .. "|"
                .. (entry.highlighted_text or entry.note or ""):sub(1, 30)
        end

        local function add(entry)
            -- Normalise text field: KOReader uses "text" internally
            if not entry.highlighted_text or entry.highlighted_text == "" then
                entry.highlighted_text = entry._raw_text
            end
            entry._raw_text = nil

            local key = makeKey(entry)
            if seen[key] then return end
            seen[key] = true
            table.insert(all, entry)
        end

        -- SOURCE 1: Old per-page highlight table  highlight[pageno] = {list}
        -- Use pairs() not ipairs() — ipairs stops at the first gap in keys.
        local old_h = doc_settings:readSetting("highlight") or {}
        if type(old_h) == "table" then
            for pageno, page_list in pairs(old_h) do
                if type(page_list) == "table" then
                    for _, h in pairs(page_list) do
                        if type(h) == "table" then
                            add({
                                chapter          = h.chapter,
                                datetime         = h.datetime,
                                highlighted_text = h.text or h.highlighted_text,
                                note             = h.note,
                                -- prefer the stored pageno field; fall back to the table key
                                page             = h.pageno or tonumber(pageno),
                            })
                        end
                    end
                end
            end
        end

        -- SOURCE 2: New flat annotations array (KOReader 2022+)
        local new_a = doc_settings:readSetting("annotations") or {}
        if type(new_a) == "table" then
            for _, a in pairs(new_a) do
                if type(a) == "table" then
                    add({
                        chapter          = a.chapter,
                        datetime         = a.datetime,
                        highlighted_text = a.text or a.highlighted_text,
                        note             = a.note,
                        page             = a.pageno or a.page,
                    })
                end
            end
        end

        -- SOURCE 3: In-memory highlights written to self.ui.view.highlight.saved
        -- These are created immediately on selection but may not yet be in
        -- doc_settings if the sidecar hasn't been flushed this session.
        local saved_ok, saved = pcall(function()
            return self.ui.view.highlight.saved
        end)
        if saved_ok and type(saved) == "table" then
            for pageno, page_list in pairs(saved) do
                if type(page_list) == "table" then
                    for _, h in pairs(page_list) do
                        if type(h) == "table" then
                            add({
                                chapter          = h.chapter,
                                datetime         = h.datetime,
                                highlighted_text = h.text or h.highlighted_text,
                                note             = h.note,
                                page             = h.pageno or tonumber(pageno),
                            })
                        end
                    end
                end
            end
        end

        -- SOURCE 4: Bookmarks that carry a user note
        -- (pure page-marker bookmarks without notes are skipped)
        local bookmarks = doc_settings:readSetting("bookmarks") or {}
        if type(bookmarks) == "table" then
            for _, bm in pairs(bookmarks) do
                if type(bm) == "table" and bm.notes and bm.notes ~= "" then
                    add({
                        chapter          = bm.chapter,
                        datetime         = bm.datetime,
                        -- "text" is the auto-extracted context; "notes" is the user note
                        highlighted_text = bm.text,
                        note             = bm.notes,
                        page             = bm.page or bm.pageno,
                    })
                end
            end
        end

        -- Sort by page number (stable within each page by insertion order)
        table.sort(all, function(x, y)
            return (x.page or 0) < (y.page or 0)
        end)

        return {
            title         = props.title   or "",
            author        = props.authors or props.author or "",
            series        = props.series  or "",
            language      = props.language or "",
            document_hash = doc_hash,
            progress      = last_xptr,
            percentage    = percentage,
            last_device   = "KOReader",
            annotations   = all,
        }
    end)

    if ok then
        return result
    else
        logger.err("ObsidianSync buildPayload:", result)
        return nil, tostring(result)
    end
end

-- =========================================================================
-- 7. Auto-sync event hooks & helpers
-- =========================================================================

-- Called by KOReader on every page turn in page-based documents (PDF, CBZ…)
function ObsidianSync:onPageUpdate(pageno)
    self:_checkAutoSyncByPage(pageno)
end

-- Called by KOReader on every position update in reflowable documents (EPUB)
-- pageno is a virtual page number calculated from the scroll position
function ObsidianSync:onPosUpdate(pos, pageno)  -- luacheck: ignore pos
    if pageno then
        self:_checkAutoSyncByPage(pageno)
    end
end

-- Called by KOReader just before the device goes to sleep / screen off
function ObsidianSync:onSuspend()
    if self.settings.auto_sync_on_sleep then
        -- IMPORTANT: never call socket.http synchronously from onSuspend —
        -- it causes a native SIGSEGV on Android.  Schedule for the next
        -- event-loop tick so the HTTP work runs off the suspend call stack.
        -- silent=true suppresses the success toast (screen may be off already).
        UIManager:scheduleIn(0, function()
            self:_autoSync(true)
        end)
    end
end

-- Check whether enough pages have been read to trigger an auto-sync
function ObsidianSync:_checkAutoSyncByPage(pageno)
    local threshold = tonumber(self.settings.auto_sync_pages) or 0
    if threshold <= 0 then return end   -- feature disabled

    if self.last_sync_page == nil then
        -- First page event this session — record starting point, don't sync yet
        self.last_sync_page = pageno
        return
    end

    if math.abs(pageno - self.last_sync_page) >= threshold then
        self.last_sync_page = pageno

        -- Cancel any previously scheduled auto-sync (debounce rapid page flips)
        if self._pendingAutoSync then
            UIManager:unschedule(self._pendingAutoSync)
            self._pendingAutoSync = nil
        end

        -- IMPORTANT: never call socket.http directly from an event handler on
        -- Android — it triggers a native SIGSEGV in the C socket library.
        -- Schedule the actual HTTP work 2 seconds from now, safely off the
        -- event-handler call stack.
        self._pendingAutoSync = function()
            self._pendingAutoSync = nil
            self:_autoSync()
        end
        UIManager:scheduleIn(2, self._pendingAutoSync)
    end
end

-- Silent auto-sync: no blocking dialogs, only a brief success toast.
-- Only runs when the network is already connected — never prompts for WiFi.
-- silent=true suppresses the success toast (used for the sleep trigger).
function ObsidianSync:_autoSync(silent)
    -- Guard: never run two concurrent syncs (e.g. rapid page flips that
    -- somehow slip past the debounce, or sleep + page trigger at the same time)
    if self._is_syncing then return end
    self._is_syncing = true

    -- Wrap entire body so self._is_syncing is always reset, even on errors
    local ok, err = pcall(function()
        -- Check connectivity without prompting (pcall handles missing API)
        local connected = false
        pcall(function() connected = NetworkMgr:isConnected() end)
        if not connected then return end

        local payload = self:buildPayload()
        if not payload then return end

        local auth_ok = self:authenticate()
        if not auth_ok then return end

        local code = self:postAnnotations(payload)
        if code == 200 and not silent then
            UIManager:show(InfoMessage:new{
                text    = string.format(
                    _("✓ Auto-synced \"%s\""),
                    payload.title ~= "" and payload.title or _("book")
                ),
                timeout = 2,
            })
        end
    end)

    self._is_syncing = false
    if not ok then
        logger.err("ObsidianSync _autoSync:", err)
    end
end

-- Persist settings to G_reader_settings
function ObsidianSync:_saveSettings()
    G_reader_settings:saveSetting("obsidiansync", self.settings)
end

-- =========================================================================
-- 8. HTTP helpers  — lazy require + pcall so missing modules don't crash
-- =========================================================================

local HTTP_TIMEOUT = 10   -- seconds; prevents Android ANR

local function lazyRequire(mod)
    local ok, m = pcall(require, mod)
    return ok and m or nil, not ok and ("cannot load " .. mod) or nil
end

function ObsidianSync:_authHeaders()
    return {
        ["x-auth-user"] = self.settings.username,
        -- md5hex() always returns a 32-char lowercase hex string
        ["x-auth-key"]  = md5hex(self.settings.password),
    }
end

function ObsidianSync:authenticate()
    local ltn12, e1 = lazyRequire("ltn12")
    if not ltn12 then return false, e1 end
    local http, e2 = lazyRequire("socket.http")
    if not http  then return false, e2 end

    http.TIMEOUT = HTTP_TIMEOUT

    local url     = self.settings.server_url .. "/users/auth"
    local headers = self:_authHeaders()
    local resp    = {}

    local call_ok, result = pcall(function()
        local _, code = http.request{
            url     = url,
            method  = "GET",
            headers = headers,
            sink    = ltn12.sink.table(resp),
        }
        return code
    end)

    if not call_ok then
        logger.err("ObsidianSync authenticate:", result)
        return false, tostring(result)
    end

    if result == 200 then
        return true
    elseif result == 401 then
        return false, "wrong credentials (401)"
    else
        return false, "HTTP " .. tostring(result)
    end
end

function ObsidianSync:postAnnotations(payload)
    local ltn12, e1 = lazyRequire("ltn12")
    if not ltn12 then return nil, e1 end
    local http, e2 = lazyRequire("socket.http")
    if not http  then return nil, e2 end

    -- Try the standard json module, fall back to json.lua path
    local json = lazyRequire("json") or lazyRequire("json.lua")
    if not json then return nil, "json library not found" end

    http.TIMEOUT = HTTP_TIMEOUT

    local url     = self.settings.server_url .. "/api/annotations"
    local body    = json.encode(payload)
    local headers = self:_authHeaders()
    headers["Content-Type"]   = "application/json"
    headers["Content-Length"] = tostring(#body)

    local resp = {}
    local call_ok, result = pcall(function()
        local _, code = http.request{
            url     = url,
            method  = "POST",
            headers = headers,
            source  = ltn12.source.string(body),
            sink    = ltn12.sink.table(resp),
        }
        return code
    end)

    if not call_ok then
        logger.err("ObsidianSync postAnnotations:", result)
        return nil, tostring(result)
    end

    return result, table.concat(resp)
end

-- =========================================================================
return ObsidianSync
