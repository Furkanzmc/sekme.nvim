local M = {}
local vim = vim
local opt = vim.opt
local opt_local = vim.opt_local
local fn = vim.fn
local api = vim.api
local option_loaded, options = pcall(require, "options")

if option_loaded then
    options.register_option {
        name = "completion_timeout",
        default = 150,
        type_info = "number",
        source = "sekme",
        buffer_local = true,
        target_variable = "sekme_completion_timeout",
    }

    options.register_option {
        name = "completion_key",
        default = "<Tab>",
        type_info = "string",
        source = "sekme",
        global = true,
        target_variable = "sekme_completion_key",
    }

    options.register_option {
        name = "completion_rkey",
        default = "<S-Tab>",
        type_info = "string",
        source = "sekme",
        global = true,
        target_variable = "sekme_completion_rkey",
    }

    options.register_option {
        name = "abbvr_trigger_char",
        default = "@",
        type_info = "string",
        source = "sekme",
        global = true,
        target_variable = "sekme_abbvr_trigger_char",
    }

    options.register_option {
        name = "debug",
        default = false,
        type_info = "boolean",
        source = "sekme",
        global = true,
        target_variable = "sekme_debug",
    }
end

M.debug = false

local function log(message, level)
    if not M.debug then
        return
    end

    local final_level = level or vim.log.levels.INFO
    vim.notify("sekme: " .. message, final_level)
end

-- Variables {{{

local s_last_cursor_position = nil
local s_completion_timer = nil
local s_vim_sources = {
    {
        keys = "<c-x><c-o>",
        name = "omni",
        predicate = function()
            return opt_local.omnifunc:get() ~= "" or opt.omnifunc:get() ~= ""
        end,
    },
    {
        keys = "<c-x><c-u>",
        name = "user",
        predicate = function()
            return opt_local.completefunc:get() ~= "" or opt.completefunc:get() ~= ""
        end,
    },
    { keys = "<c-x><c-n>", name = "keywords" },
    { keys = "<c-n>", name = "complete" },
    {
        keys = "<c-x><c-]>",
        name = "tags",
        predicate = function()
            return #fn.tagfiles() > 0
        end,
    },
    { keys = "<c-x><c-v>", filetypes = { "vim" }, name = "vim-commands" },
    { keys = "<c-x><c-f>", name = "file" },
    {
        keys = "<c-x><c-k>",
        name = "dictionary",
        predicate = function()
            return #opt.dictionary:get() > 0 or #opt_local.dictionary:get() > 0
        end,
    },
    {
        keys = "<c-x><c-s>",
        name = "spell",
        predicate = function()
            return opt_local.spell:get()
        end,
    },
    { keys = "<c-x><c-l>", name = "lines" },
}

local s_custom_sources = {}
local s_completion_index = -1
local s_is_completion_dispatched = false

-- }}}

-- Local Functions {{{

--- @param source table
--- @param target table
local function tbl_extend(source, target)
    for _, v in ipairs(target) do
        table.insert(source, v)
    end

    return source
end

--- @param tab table
--- @param val any
local function tbl_index_of(tab, val)
    if tab == nil or type(tab) ~= "table" then
        return -1
    end
    for index, value in ipairs(tab) do
        if value == val then
            return index
        end
    end

    return -1
end

--- @param filetypes table|nil
--- @param filetype string
local function matches_filetype(filetypes, filetype)
    if filetypes == nil then
        return true
    end
    if type(filetypes) == "string" then
        return filetypes == filetype
    end
    if type(filetypes) == "table" then
        return tbl_index_of(filetypes, filetype) > -1
    end
    return false
end

--- @param bufnr integer
local function get_completion_timeout(bufnr)
    local timeout = 150 -- default
    if option_loaded then
        timeout = options.get_option_value("completion_timeout", bufnr) or timeout
    else
        local success, value = pcall(api.nvim_buf_get_var, bufnr, "sekme_completion_timeout")
        if success and type(value) == "number" then
            timeout = value
        end
    end

    -- Ensure timeout is a valid positive number
    if type(timeout) ~= "number" or timeout < 0 then
        timeout = 150
    end

    return timeout
end

--- @param bufnr integer
local function get_completion_sources(bufnr)
    -- Cache is per-buffer but sources are global, so we just return the sources
    -- The cache mechanism could be improved to filter sources per buffer/filetype
    -- but currently sources are filtered dynamically in timer_handler
    return s_vim_sources
end

--- @param opts table
local function setup_keymap(opts)
    vim.keymap.set("i", opts.completion_key, "<plug>(SekmeCompleteFwd)", { nowait = true })
    vim.keymap.set("i", opts.completion_rkey, "<plug>(SekmeCompleteBack)", { nowait = true })
end

--- @param bufnr integer
local function timer_handler(bufnr)
    log("timer_handler called, index: " .. s_completion_index)
    if s_completion_index == -1 then
        return
    end

    -- Clean up timer first to avoid leaks
    if s_completion_timer ~= nil then
        s_completion_timer:stop()
        s_completion_timer:close()
        s_completion_timer = nil
    end

    if api.nvim_get_mode().mode == "n" then
        log("timer_handler: mode is normal, resetting index")
        s_completion_index = -1
        return
    end

    local completion_sources = get_completion_sources(bufnr)

    if vim.fn.pumvisible() == 0 then
        if s_completion_index == #completion_sources + 1 then
            log("timer_handler: reached end of sources")
            s_is_completion_dispatched = false
        else
            local filetype = api.nvim_get_option_value("filetype", { buf = bufnr }) or ""
            local source = completion_sources[s_completion_index]
            log(
                string.format(
                    "timer_handler: testing source %d/%d (%s)",
                    s_completion_index,
                    #completion_sources,
                    source.name or "unnamed"
                )
            )
            if
                source == nil
                or (source.predicate ~= nil and not source.predicate())
                or not matches_filetype(source.filetypes, filetype)
                or (source.keys == nil or source.keys == "")
            then
                log("timer_handler: source skipped, jumping to next")
                s_completion_index = s_completion_index + 1
                timer_handler(bufnr)
                return
            end

            log("timer_handler: dispatching source keys: " .. source.keys)
            api.nvim_feedkeys(
                api.nvim_replace_termcodes("<c-g><c-g>", true, false, true),
                "n",
                true
            )
            s_is_completion_dispatched = true
            s_completion_index = s_completion_index + 1
            local mode_keys = api.nvim_replace_termcodes(source.keys, true, false, true)
            api.nvim_feedkeys(mode_keys, "n", true)

            -- If the popup menu doesn't show up after feeding keys, we should
            -- try the next source after a short delay.
            local timeout = get_completion_timeout(bufnr)
            vim.defer_fn(function()
                if vim.fn.pumvisible() == 0 and s_completion_index ~= -1 then
                    log("timer_handler: pum not visible after dispatch, scheduling fallback")
                    M.on_complete_done_pre(bufnr)
                end
            end, timeout)
        end
    else
        log("timer_handler: pum is visible, doing nothing")
    end
end

-- Completion Functions {{{

--- @param find_start integer
--- @param base string
local function complete_custom(find_start, base)
    log(string.format("complete_custom called, find_start: %d, base: '%s'", find_start, base))
    if find_start == 1 and base == "" then
        local pos = api.nvim_win_get_cursor(0)
        local line = api.nvim_get_current_line()
        local line_to_cursor = line:sub(1, pos[2])
        return vim.fn.match(line_to_cursor, "\\k*$")
    end

    local completions = {}
    local bufnr = api.nvim_get_current_buf()
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local filetype = opt_local.filetype:get() or ""

    for _, source in ipairs(s_custom_sources) do
        if source == nil or type(source) ~= "table" then
            goto continue
        end

        if source.complete == nil or type(source.complete) ~= "function" then
            vim.notify(
                "sekme.nvim: custom source missing 'complete' function",
                vim.log.levels.WARN
            )
            goto continue
        end

        if matches_filetype(source.filetypes, filetype) then
            local success, items = pcall(source.complete, lines, base)
            if success and items ~= nil then
                if type(items) == "table" then
                    tbl_extend(completions, items)
                else
                    vim.notify(
                        "sekme.nvim: custom source 'complete' must return a table",
                        vim.log.levels.WARN
                    )
                end
            elseif not success then
                vim.notify(
                    "sekme.nvim: error in custom source: " .. tostring(items),
                    vim.log.levels.ERROR
                )
            end
        end

        ::continue::
    end

    return completions
end

-- }}}

--- @param find_start integer
--- @param base string
_G.trigger_sekme = function(find_start, base)
    return complete_custom(find_start, base)
end

-- }}}

-- Public API {{{

-- Event Handlers {{{

--- @param bufnr integer
function M.on_complete_done_pre(bufnr)
    log("on_complete_done_pre, index: " .. s_completion_index)
    if api.nvim_get_mode().mode == "n" then
        s_completion_index = -1
        return
    end

    if s_completion_index == -1 or vim.fn.pumvisible() == 1 then
        log("on_complete_done_pre: inactive or pumvisible, skipping")
        return
    end

    local info = vim.fn.complete_info()
    if #info.items > 0 then
        api.nvim_feedkeys(api.nvim_replace_termcodes("<c-e>", true, false, true), "n", true)
        s_completion_index = -1
        return
    end

    if s_completion_timer ~= nil then
        return
    end

    local timeout = get_completion_timeout(bufnr)
    if not M.debug then
        if option_loaded then
            M.debug = options.get_option_value("debug", bufnr) or false
        else
            local success, value = pcall(api.nvim_buf_get_var, bufnr, "sekme_debug")
            if success and type(value) == "boolean" then
                M.debug = value
            end
        end
    end

    log("on_complete_done_pre: starting timer with timeout: " .. timeout)
    s_completion_timer = vim.uv.new_timer()
    if s_completion_timer == nil then
        vim.notify("sekme.nvim: failed to create timer", vim.log.levels.ERROR)
        return
    end

    local success, err = pcall(function()
        s_completion_timer:start(
            timeout,
            0,
            vim.schedule_wrap(function()
                timer_handler(bufnr)
            end)
        )
    end)

    if not success then
        vim.notify("sekme.nvim: failed to start timer: " .. tostring(err), vim.log.levels.ERROR)
        if s_completion_timer ~= nil then
            s_completion_timer:close()
            s_completion_timer = nil
        end
    end
end

--- @param bufnr integer
function M.on_complete_done(bufnr)
    log("on_complete_done, index: " .. s_completion_index)
    if s_is_completion_dispatched == true then
        log("on_complete_done: dispatched, resetting flag")
        return
    end

    if s_last_cursor_position == nil then
        s_completion_index = -1
        return
    end

    local completion_sources = get_completion_sources(bufnr)
    local cursor_position = api.nvim_win_get_cursor(0)
    if
        cursor_position[1] == s_last_cursor_position[1]
        and cursor_position[2] == s_last_cursor_position[2]
        and s_completion_index == #completion_sources + 1
    then
        api.nvim_feedkeys(api.nvim_replace_termcodes("<c-e>", true, false, true), "n", true)
        s_completion_index = -1
    end
end

function M.on_complete_changed(bufnr, event)
    if event.size ~= nil then
        return
    end

    M.on_complete_done_pre(bufnr)
    M.on_complete_done(bufnr)
    s_completion_index = -1
end

-- }}}

--- @param bufnr integer
function M.trigger_completion(bufnr)
    log("trigger_completion called")
    s_last_cursor_position = api.nvim_win_get_cursor(0)
    s_completion_index = 1
    timer_handler(bufnr)
end

--- @param bufnr integer
function M.setup_completion(bufnr)
    if vim.fn.exists("b:sekme_is_completion_configured") == 0 then
        api.nvim_buf_set_var(bufnr, "sekme_is_completion_configured", false)
    elseif api.nvim_buf_get_var(bufnr, "sekme_is_completion_configured") == true then
        return
    end

    if not option_loaded then
        local option_set, _ = pcall(api.nvim_buf_get_var, bufnr, "sekme_completion_timeout")
        if not option_set then
            api.nvim_buf_set_var(bufnr, "sekme_completion_timeout", 150)
        end
    end

    vim.bo[bufnr].completefunc = "v:lua.trigger_sekme"

    local group = api.nvim_create_augroup("sekme_completion_buf_" .. bufnr, { clear = true })
    api.nvim_create_autocmd({ "CompleteDonePre" }, {
        pattern = "*",
        group = group,
        callback = function(args)
            M.on_complete_done_pre(args.buf)
        end,
    })

    api.nvim_create_autocmd({ "CompleteDone" }, {
        pattern = "*",
        group = group,
        callback = function(args)
            M.on_complete_done(args.buf)
        end,
    })

    api.nvim_create_autocmd({ "CompleteChanged" }, {
        pattern = "*",
        group = group,
        callback = function(args)
            M.on_complete_changed(args.buf, vim.v.event)
        end,
    })

    api.nvim_buf_set_var(bufnr, "sekme_is_completion_configured", true)
end

--- @param opts table
function M.setup(opts)
    api.nvim_create_autocmd({ "BufEnter" }, {
        pattern = "*",
        group = api.nvim_create_augroup("sekme_completion", { clear = true }),
        callback = function(_)
            M.setup_completion(vim.api.nvim_get_current_buf())
        end,
    })

    if opts == nil then
        opts = {}
    end

    opts.completion_key = opts.completion_key or "<Tab>"
    opts.completion_rkey = opts.completion_rkey or "<S-Tab>"
    opts.abbvr_trigger_char = opts.abbvr_trigger_char or "@"
    M.debug = opts.debug or false

    if opts ~= nil and opts.custom_sources ~= nil then
        if type(opts.custom_sources) ~= "table" then
            vim.notify("sekme.nvim: custom_sources must be a table", vim.log.levels.WARN)
        else
            for _, source in ipairs(opts.custom_sources) do
                if source ~= nil and type(source) == "table" and type(source.complete) == "function" then
                    table.insert(s_custom_sources, source)
                else
                    vim.notify(
                        "sekme.nvim: skipping invalid custom source (must have 'complete' function)",
                        vim.log.levels.WARN
                    )
                end
            end
        end
    end

    vim.g.sekme_completion_key = opts.completion_key
    vim.g.sekme_completion_rkey = opts.completion_rkey
    vim.g.sekme_abbvr_trigger_char = opts.abbvr_trigger_char

    setup_keymap(opts)
end

--- @param source table
function M.register_custom_source(source)
    if source == nil or type(source) ~= "table" then
        vim.notify("sekme.nvim: register_custom_source requires a table", vim.log.levels.ERROR)
        return
    end
    if source.complete == nil or type(source.complete) ~= "function" then
        vim.notify("sekme.nvim: custom source must have a 'complete' function", vim.log.levels.ERROR)
        return
    end
    table.insert(s_custom_sources, source)
end

-- }}}

return M

-- vim: foldmethod=marker
