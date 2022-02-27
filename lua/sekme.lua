local M = {}
local vim = vim
local opt = vim.opt
local opt_local = vim.opt_local
local fn = vim.fn
local api = vim.api
local cmd = vim.cmd
local option_loaded, options = pcall(require, "options")

if option_loaded then
    options.register_option({
        name = "completion_timeout",
        default = 150,
        type_info = "number",
        source = "sekme",
        buffer_local = true,
        target_variable = "sekme_completion_timeout",
    })

    options.register_option({
        name = "completion_key",
        default = "<Tab>",
        type_info = "string",
        source = "sekme",
        global = true,
        target_variable = "sekme_completion_key",
    })

    options.register_option({
        name = "completion_rkey",
        default = "<S-Tab>",
        type_info = "string",
        source = "sekme",
        global = true,
        target_variable = "sekme_completion_rkey",
    })

    options.register_option({
        name = "abbvr_trigger_char",
        default = "@",
        type_info = "string",
        source = "sekme",
        global = true,
        target_variable = "sekme_abbvr_trigger_char",
    })
end

-- Variables {{{

local s_last_cursor_position = nil
local s_completion_timer = nil
local s_vim_sources = {
    {
        keys = "<c-x><c-o>",
        name = "omni",
        prediciate = function()
            return opt_local.omnifunc:get() ~= "" or opt.omnifunc:get() ~= ""
        end,
    },
    {
        keys = "<c-x><c-u>",
        name = "user",
        prediciate = function()
            return opt_local.completefunc:get() ~= "" or opt.completefunc:get() ~= ""
        end,
    },
    { keys = "<c-x><c-n>", name = "keywords" },
    { keys = "<c-n>", name = "complete" },
    {
        keys = "<c-x><c-]>",
        name = "tags",
        prediciate = function()
            return #fn.tagfiles() > 0
        end,
    },
    { keys = "<c-x><c-v>", filetypes = { "vim" }, name = "vim-commands" },
    { keys = "<c-x><c-f>", name = "file" },
    {
        keys = "<c-x><c-k>",
        name = "dictionary",
        prediciate = function()
            return #opt.dictionary:get() > 0 or #opt_local.dictionary:get() > 0
        end,
    },
    {
        keys = "<c-x><c-s>",
        name = "spell",
        prediciate = function()
            return opt_local.spell:get()
        end,
    },
    { keys = "<c-x><c-l>", name = "lines" },
}

local s_custom_sources = {}
local s_completion_index = nil
local s_is_completion_dispatched = false
local s_buffer_completion_sources_cache = {}

-- }}}

-- Local Functions {{{

local function tbl_extend(source, target)
    for _, v in ipairs(target) do
        table.insert(source, v)
    end

    return source
end

local function tbl_index_of(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return index
        end
    end

    return -1
end

local function get_completion_sources(bufnr)
    if s_buffer_completion_sources_cache[bufnr] ~= nil then
        return s_buffer_completion_sources_cache[bufnr]
    end

    s_buffer_completion_sources_cache[bufnr] = s_vim_sources
    return s_buffer_completion_sources_cache[bufnr]
end

local function timer_handler()
    if s_completion_index == -1 then
        return
    end

    if api.nvim_get_mode().mode == "n" then
        s_completion_index = -1
        return
    end

    local bufnr = vim.fn.bufnr()
    local filetype = api.nvim_buf_get_option(bufnr, "filetype")
    local completion_sources = get_completion_sources(bufnr)

    if vim.fn.pumvisible() == 0 then
        if s_completion_index == #completion_sources + 1 then
            s_is_completion_dispatched = false
        else
            local source = completion_sources[s_completion_index]
            if
                (source.prediciate ~= nil and source.prediciate() == false)
                or (source.filetype ~= nil and source.filetype ~= filetype)
                or (source.keys == nil or source.keys == "")
            then
                s_completion_index = s_completion_index + 1
                timer_handler()
                return
            end

            local mode_keys = api.nvim_replace_termcodes(source.keys, true, false, true)
            api.nvim_feedkeys(
                api.nvim_replace_termcodes("<c-g><c-g>", true, false, true),
                "n",
                true
            )
            api.nvim_feedkeys(mode_keys, "n", true)
            s_is_completion_dispatched = true
            s_completion_index = s_completion_index + 1
        end
    end

    if s_completion_timer ~= nil then
        s_completion_timer:stop()
        s_completion_timer:close()
        s_completion_timer = nil
    end
end

-- Completion Functions {{{

local function complete_custom(_, base)
    if base == "" then
        local pos = api.nvim_win_get_cursor(0)
        local line = api.nvim_get_current_line()
        local line_to_cursor = line:sub(1, pos[2])
        return vim.fn.match(line_to_cursor, "\\k*$")
    end

    local completions = {}
    local bufnr = api.nvim_get_current_buf()
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local filetype = opt_local.filetype

    for _, source in ipairs(s_custom_sources) do
        assert(source.complete, "complete() function is required.")
        if
            (type(source.filetypes) == "table" and tbl_index_of(source.filetypes, filetype) > -1)
            or source.filetypes == nil
        then
            local items = source.complete(lines, base)
            tbl_extend(completions, items)
        end
    end

    return completions
end

-- }}}

_G.trigger_sekme = function(find_start, base)
    return complete_custom(find_start, base)
end

-- }}}

-- Public API {{{

-- Event Handlers {{{

function M.on_complete_done_pre()
    if api.nvim_get_mode().mode == "n" then
        s_completion_index = -1
        return
    end

    if s_completion_index == -1 or vim.fn.pumvisible() == 1 then
        return
    end

    local info = vim.fn.complete_info()
    if #info.items > 0 then
        api.nvim_feedkeys(api.nvim_replace_termcodes("<c-y>", true, false, true), "n", true)
        s_completion_index = -1
        return
    end

    if s_completion_timer ~= nil then
        return
    end

    s_completion_timer = vim.loop.new_timer()
    local bufnr = api.nvim_get_current_buf()
    local timeout = 0
    if option_loaded then
        timeout = options.get_option_value("completion_timeout", bufnr)
    else
        timeout = api.nvim_buf_get_var(bufnr, "sekme_completion_timeout")
    end

    s_completion_timer:start(timeout, 0, vim.schedule_wrap(timer_handler))
end

function M.on_complete_done(bufnr)
    if s_is_completion_dispatched == true then
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
        api.nvim_feedkeys(api.nvim_replace_termcodes("<c-y>", true, false, true), "n", true)
        s_completion_index = -1
    end
end

-- }}}

function M.trigger_completion()
    s_last_cursor_position = api.nvim_win_get_cursor(0)
    s_completion_index = 1
    timer_handler()
    s_completion_timer = vim.loop.new_timer()
    -- Run this first because otherwise the completion is not triggered when
    -- it is done the first time.
    s_completion_timer:start(
        10,
        0,
        vim.schedule_wrap(function()
            s_completion_timer:stop()
            s_completion_timer:close()
            s_completion_timer = nil

            M.on_complete_done_pre()
        end)
    )
end

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

    cmd("augroup sekme_completion_buf_" .. bufnr)
    cmd([[au!]])
    cmd(
        "autocmd CompleteDonePre <buffer="
            .. bufnr
            .. ">"
            .. " lua require'sekme'.on_complete_done_pre()"
    )

    cmd(
        "autocmd CompleteDone <buffer="
            .. bufnr
            .. ">"
            .. " lua require'sekme'.on_complete_done("
            .. bufnr
            .. ")"
    )
    cmd([[augroup END]])

    api.nvim_buf_set_var(bufnr, "sekme_is_completion_configured", true)
end

function M.setup(opts)
    cmd([[augroup sekme_completion]])
    cmd([[autocmd!]])
    cmd([[autocmd BufEnter * lua require'sekme'.setup_completion(vim.api.nvim_get_current_buf())]])
    cmd([[augroup END]])

    if opts == nil then
        opts = {}
    end

    opts.completion_key = opts.completion_key or "<Tab>"
    opts.completion_rkey = opts.completion_rkey or "<S-Tab>"
    opts.abbvr_trigger_char = opts.abbvr_trigger_char or "@"

    if opts ~= nil and opts.custom_sources ~= nil then
        for _, source in ipairs(opts.custom_sources) do
            table.insert(s_custom_sources, source)
        end
    end

    vim.g.sekme_completion_key = opts.completion_key
    vim.g.sekme_completion_rkey = opts.completion_rkey
    vim.g.sekme_abbvr_trigger_char = opts.abbvr_trigger_char

    cmd([[call sekme#setup_keymap()]])
end

function M.register_custom_source(source)
    table.insert(s_custom_sources, source)
end

-- }}}

return M

-- vim: foldmethod=marker
