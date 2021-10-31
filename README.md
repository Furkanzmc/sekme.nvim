# sekme.nvim

`sekme.nvim` is a chain-completion plugin that complements Neovim's own completion functions. (See
`:help ins-completion`)

`sekme.nvim` uses a list of `:help ins-completion` keys to rotate the completion source. If one
source doesn't provide any completion items, it switches to the next one until a completion is
found. It also leverages `:help completefunc`, but it's just a source in the chain instead of a new
one.

I initially copied this idea from [completion-nvim](https://github.com/nvim-lua/completion-nvim)
and later found out that there's also [supertab.vim](https://github.com/ervandew/supertab).

Please note that this is **not** a completion plugin. It only allows you to make use of all the
`:help ins-completion` sources with just one key map.

[![asciicast](https://asciinema.org/a/ugewPsEXqPWi9KnklL1mhR9yv.svg)](https://asciinema.org/a/ugewPsEXqPWi9KnklL1mhR9yv)

# Why?

Common choices for completion is [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) and
[coq_nvim](https://github.com/ms-jpq/coq_nvim). They are perfectly good plugins with thousands of
users and development hours. Feel free to check them out.

The reason for this plugin is my personal preferences. I could never get a smooth experience from
those completion plugins, and I prefer to use Vim built-in features wherever I can. I've been using
this plugin for as long as I can remember and every time I try to switch to any completion plugin I
find myself coming back to this.

This plugin will not blow out in size, or add unnecessary features. It's meant to be very bare
bones. All it does is rotate the current `:help ins-completion` sources. It also exposes a function
to add a custom completion source that will be invoked when `:help completefunc` is the current
source.

I also prefer to use `:help completefunc` and add sources using a general purpose language server
(See [null-ls](https://github.com/jose-elias-alvarez/null-ls.nvim) and
[efm-langserver](https://github.com/mattn/efm-langserver)). See
[here](https://github.com/Furkanzmc/dotfiles/blob/master/vim/lua/vimrc/lsp.lua) if you are
interested in seeing how I use it.

# Dependencies

It has no required dependencies. Optionally, you can install
[options.nvim](https://github.com/Furkanzmc/options.nvim) for configuration. If you don't want to
install it, you can still use Vim variables for configuration.

# Configuration

Always check out `:help sekme.nvim` for up to date information. Currently, you can only configure
the timeout duration for each completion source.

```lua
function complete_work_days(lines, base)
    -- lines is a list of lines in the current buffer. You
    -- don't have to use it.
    return {
        { word = "Monday", kind = "Days" },
        { word = "Tuesday", kind = "Days" },
        { word = "Wednesday", kind = "Days" },
        { word = "Thursday", kind = "Days" },
        { word = "Friday", kind = "Days" },
    }
end

require("sekme").setup({
    completion_key = "<Tab>",
    completion_rkey = "<S-Tab>",
    custom_sources = {
        {
            complete = complete_work_days,
            filetypes = { "markdown" },
        },
    },
})
```

# Installation

Use your favorite plugin manager to install.

# Related Projects

- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
- [coq_nvim](https://github.com/ms-jpq/coq_nvim)
- [null-ls](https://github.com/jose-elias-alvarez/null-ls.nvim)
- [efm-langserver](https://github.com/mattn/efm-langserver)
- [supertab.vim](https://github.com/ervandew/supertab)
- [options.nvim](https://github.com/Furkanzmc/options.nvim)
- [completion-nvim](https://github.com/nvim-lua/completion-nvim)

# TODO

- [ ] Ability to re-use the last completion method the first time after the completion is
      dismissed. Useful for when `<C-x><C-f>` was the last completion source used.
- [ ] Add debug logs.
