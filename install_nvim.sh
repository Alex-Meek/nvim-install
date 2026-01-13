#!/bin/bash

set -e

REPO_URL="https://github.com/arturgoms/nvim"

###############################################################################
# Detect Neovim
###############################################################################

NVIM_CMD="nvim"
if [ -x "$HOME/.local/nvim-win64/bin/nvim.exe" ]; then
    NVIM_CMD="$HOME/.local/nvim-win64/bin/nvim.exe"
fi

if ! "$NVIM_CMD" --version >/dev/null 2>&1; then
    echo "Neovim not found"
    exit 1
fi

###############################################################################
# Dirs
###############################################################################

UNAME_STR=$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')

if [[ "$UNAME_STR" == *"mingw"* ]] || [[ "$UNAME_STR" == *"msys"* ]]; then
    NVIM_CONFIG_DIR="$HOME/AppData/Local/nvim"
    NVIM_DATA_DIR="$HOME/AppData/Local/nvim-data"
    NVIM_CACHE_DIR="$HOME/AppData/Local/Temp/nvim"
    IS_WINDOWS=1
else
    NVIM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
    NVIM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
    NVIM_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/nvim"
    IS_WINDOWS=0
fi

###############################################################################
# MSYS2 deps
###############################################################################

if [[ "$UNAME_STR" == *"mingw"* ]] || [[ "$UNAME_STR" == *"msys"* ]]; then
    if command -v pacman >/dev/null 2>&1; then
        PREFIX="mingw-w64-ucrt-x86_64"
        case "${MSYSTEM:-}" in
            CLANG64) PREFIX="mingw-w64-clang-x86_64" ;;
            MINGW64) PREFIX="mingw-w64-x86_64" ;;
        esac

        set +e
        pacman -Sy --needed --noconfirm \
            "${PREFIX}-nodejs" \
            "${PREFIX}-fzf" \
            "${PREFIX}-ripgrep" \
            "${PREFIX}-fd" \
            "${PREFIX}-gcc" \
            "${PREFIX}-make" \
            "${PREFIX}-python-pip" \
            git findutils
        set -e

        command -v npm && npm install -g neovim tree-sitter-cli
        command -v pip && pip install pynvim
    fi
fi

###############################################################################
# COMPLETE CLEAN
###############################################################################

echo "Performing complete clean..."

[[ -d "$NVIM_CONFIG_DIR" ]] && rm -rf "$NVIM_CONFIG_DIR"
[[ -d "$NVIM_DATA_DIR" ]] && rm -rf "$NVIM_DATA_DIR"
[[ -d "$NVIM_CACHE_DIR" ]] && rm -rf "$NVIM_CACHE_DIR"

if [ "$IS_WINDOWS" -eq 1 ]; then
    [[ -d "$HOME/AppData/Local/nvim" ]] && rm -rf "$HOME/AppData/Local/nvim"
    [[ -d "$HOME/AppData/Local/nvim-data" ]] && rm -rf "$HOME/AppData/Local/nvim-data"
    [[ -d "$TEMP/nvim" ]] && rm -rf "$TEMP/nvim" 2>/dev/null || true
fi

find /tmp -maxdepth 1 -name "tree-sitter-*" -type d -exec rm -rf {} \; 2>/dev/null || true
find "$HOME" -maxdepth 1 -name ".tree-sitter" -type d -exec rm -rf {} \; 2>/dev/null || true

sleep 1

###############################################################################
# Clone
###############################################################################

echo "Cloning config..."
mkdir -p "$NVIM_CONFIG_DIR"
git clone --depth 1 "$REPO_URL" "$NVIM_CONFIG_DIR"

INIT_LUA="$NVIM_CONFIG_DIR/init.lua"

###############################################################################
# Windows shell fix
###############################################################################

if [ "$IS_WINDOWS" -eq 1 ]; then
    tmp="${INIT_LUA}.tmp"
    cat > "$tmp" <<'EOF'
-- Windows shell compatibility
if vim.fn.has("win32") == 1 then
  vim.opt.shell = "cmd.exe"
  vim.opt.shellcmdflag = "/s /c"
  vim.opt.shellredir = ">%s 2>&1"
  vim.opt.shellpipe = "2>&1| tee"
  vim.opt.shellquote = ""
  vim.opt.shellxquote = '"'
end

EOF
    cat "$INIT_LUA" >> "$tmp"
    mv "$tmp" "$INIT_LUA"
fi

###############################################################################
# Remove conflicts
###############################################################################

echo "Removing treesitter-textobjects..."
find "$NVIM_CONFIG_DIR" -type f -name "*.lua" -print0 | xargs -0 sed -i.bak '/treesitter-textobjects/d'

[[ -f "$INIT_LUA" ]] && sed -i.bak 's/require.*lsp\.lsp-setup.*/-- &/' "$INIT_LUA"
[[ -f "$NVIM_CONFIG_DIR/lua/lsp/treesitter-setup.lua" ]] && echo "return {}" > "$NVIM_CONFIG_DIR/lua/lsp/treesitter-setup.lua"

find "$NVIM_CONFIG_DIR/lua" -type f -name "*.lua" -exec grep -l 'rmagatti/auto-session' {} \; 2>/dev/null | while read -r f; do
    sed -i.bak '/"rmagatti\/auto-session"/a\    enabled = false,' "$f"
done

find "$NVIM_CONFIG_DIR/lua" -type f -name "*.lua" -exec grep -l "zbirenbaum/copilot.lua" {} \; 2>/dev/null | while read -r f; do
    [[ "$(basename "$f")" != "lazy-plugins.lua" ]] && echo "return {}" > "$f"
done

###############################################################################
# Patch lazy-plugins.lua - FORCE EAGER LOADING for completion stack
###############################################################################

LAZY_PLUGINS_FILE="$NVIM_CONFIG_DIR/lua/lazy-plugins.lua"
if [[ -f "$LAZY_PLUGINS_FILE" ]]; then
    tmp="${LAZY_PLUGINS_FILE}.tmp"
    awk '
      /require .custom.plugins.debug/ && !done {
        print
        print "    { \"shaunsingh/moonlight.nvim\", lazy = false, priority = 1000 },"
        print "    { \"zbirenbaum/copilot.lua\", cmd = \"Copilot\", event = \"InsertEnter\" },"
        print "    { \"nvim-neotest/nvim-nio\" },"
        print "    { \"theprimeagen/harpoon\", branch = \"harpoon2\" },"
        print "    { \"mbbill/undotree\" },"
        print "    { \"tpope/vim-fugitive\" },"
        print "    { \"nvim-treesitter/nvim-treesitter\", commit = \"d5a5809\", build = \":TSUpdate\" },"
        print "    { \"L3MON4D3/LuaSnip\", lazy = false, dependencies = {\"rafamadriz/friendly-snippets\"} },"
        print "    { \"rafamadriz/friendly-snippets\", lazy = false },"
        print "    { \"hrsh7th/nvim-cmp\", lazy = false, event = \"InsertEnter\" },"
        print "    { \"hrsh7th/cmp-nvim-lsp\", lazy = false },"
        print "    { \"hrsh7th/cmp-buffer\", lazy = false },"
        print "    { \"hrsh7th/cmp-path\", lazy = false },"
        print "    { \"saadparwaiz1/cmp_luasnip\", lazy = false },"
        print "    { \"hrsh7th/cmp-nvim-lua\", lazy = false },"
        print "    { \"williamboman/mason.nvim\", lazy = false, config = function() require(\"mason\").setup() end },"
        print "    { \"williamboman/mason-lspconfig.nvim\", lazy = false, dependencies = {\"mason.nvim\"} },"
        print "    { \"neovim/nvim-lspconfig\", commit = \"9eff3cf\", lazy = false },"
        done=1
        next
      }
      { print }
    ' "$LAZY_PLUGINS_FILE" >"$tmp"
    mv "$tmp" "$LAZY_PLUGINS_FILE"
fi

###############################################################################
# Config files
###############################################################################

A_SUB_DIR="$NVIM_CONFIG_DIR/lua/a_sub_directory"
mkdir -p "$A_SUB_DIR"

cat > "$A_SUB_DIR/set.lua" <<'EOF'
vim.opt.nu = true
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.wrap = false
vim.opt.swapfile = false
vim.opt.backup = false

local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""
local undodir = home .. "/.vim/undodir"
vim.opt.undodir = undodir
vim.opt.undofile = true
if vim.fn.isdirectory(undodir) == 0 then vim.fn.mkdir(undodir, "p") end

vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.termguicolors = true
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 50
vim.opt.colorcolumn = "80"
vim.opt.completeopt = "menu,menuone,noselect"
EOF

cat > "$A_SUB_DIR/remap.lua" <<'EOF'
vim.g.mapleader = " "
vim.keymap.set("n", "<leader>pv", vim.cmd.Ex)

-- Telescope
local ok, builtin = pcall(require, 'telescope.builtin')
if ok then
  vim.keymap.set('n', '<leader>pe', builtin.find_files)
  vim.keymap.set('n', '<leader>pw', builtin.grep_string)
  vim.keymap.set('n', '<leader>ps', builtin.live_grep)
end

-- LSP/Diagnostics
vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float)
vim.keymap.set("n", "[d", vim.diagnostic.goto_prev)
vim.keymap.set("n", "]d", vim.diagnostic.goto_next)

-- Mason
vim.keymap.set("n", "<leader>pm", "<cmd>Mason<cr>", {desc = "Mason"})

-- Movement
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")
vim.keymap.set("n", "J", "mzJ`z")
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

-- Clipboard
vim.keymap.set("x", "<leader>p", [["_dP]])
vim.keymap.set({"n","v"}, "<leader>y", [["+y]])
vim.keymap.set("n", "<leader>Y", [["+Y]])
vim.keymap.set({"n","v"}, "<leader>d", [["_d]])

-- Format
vim.keymap.set("n", "<leader>f", vim.lsp.buf.format)
EOF

cat > "$A_SUB_DIR/treesitter.lua" <<'EOF'
local M = {}

function M.setup()
  local ok, ts = pcall(require, 'nvim-treesitter.configs')
  if not ok then return false end

  ts.setup({
    ensure_installed = {"lua","python","c"},
    sync_install = false,
    auto_install = true,
    highlight = {enable = true, additional_vim_regex_highlighting = false},
    indent = {enable = true},
  })
  return true
end

vim.api.nvim_create_autocmd("User", {
  pattern = "LazyDone",
  once = true,
  callback = function()
    vim.schedule(function()
      M.setup()
    end)
  end,
})

return M
EOF

cat > "$A_SUB_DIR/plugin_configs.lua" <<'EOF'
local function setup_moonlight()
  local ok, m = pcall(require, 'moonlight')
  if ok then
    vim.g.moonlight_italic_comments = true
    vim.g.moonlight_italic_keywords = true
    vim.g.moonlight_contrast = true
    m.set()
  end
end

local function setup_copilot()
  local ok, c = pcall(require, 'copilot')
  if ok then
    c.setup({
      suggestion = {
        enabled = true,
        auto_trigger = true,
        keymap = {accept = "<M-l>", next = "<M-]>", prev = "<M-[>", dismiss = "<C-]>"},
      },
      panel = {enabled = false},
    })
  end
end

vim.api.nvim_create_autocmd("User", {
  pattern = "LazyDone",
  once = true,
  callback = function()
    vim.schedule(function()
      setup_moonlight()
      setup_copilot()
    end)
  end,
})
EOF

cat > "$A_SUB_DIR/lsp.lua" <<'EOF'
local M = {}

local function get_capabilities()
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  local ok, cmp_lsp = pcall(require, 'cmp_nvim_lsp')
  if ok then
    capabilities = cmp_lsp.default_capabilities(capabilities)
  end
  return capabilities
end

local function on_attach(client, bufnr)
  local map = function(k, f, d)
    vim.keymap.set('n', k, f, {buffer=bufnr, desc='LSP: '..(d or '')})
  end
  map('gd', vim.lsp.buf.definition, 'Goto Definition')
  map('gr', vim.lsp.buf.references, 'References')
  map('gI', vim.lsp.buf.implementation, 'Implementation')
  map('K', vim.lsp.buf.hover, 'Hover')
  map('<leader>vca', vim.lsp.buf.code_action, 'Code Action')
  map('<leader>vrn', vim.lsp.buf.rename, 'Rename')
  map('<C-k>', vim.lsp.buf.signature_help, 'Signature Help')
end

function M.setup_lsp()
  local mason_ok = pcall(require, 'mason')
  local mason_lsp_ok = pcall(require, 'mason-lspconfig')
  local lspconfig_ok, lspconfig = pcall(require, 'lspconfig')

  if not (mason_ok and mason_lsp_ok and lspconfig_ok) then
    return false
  end

  require('mason-lspconfig').setup({
    ensure_installed = {'lua_ls','pyright','rust_analyzer'},
    automatic_installation = true,
  })

  local capabilities = get_capabilities()

  lspconfig['lua_ls'].setup({
    capabilities = capabilities,
    on_attach = on_attach,
    settings = {
      Lua = {
        diagnostics = {globals = {'vim'}},
        workspace = {checkThirdParty = false},
        telemetry = {enable = false},
      }
    }
  })

  lspconfig['pyright'].setup({
    capabilities = capabilities,
    on_attach = on_attach,
  })

  lspconfig['rust_analyzer'].setup({
    capabilities = capabilities,
    on_attach = on_attach,
    settings = {
      ['rust-analyzer'] = {
        checkOnSave = {command = "clippy"},
      }
    }
  })

  return true
end

function M.setup_cmp()
  local cmp_ok, cmp = pcall(require, 'cmp')
  local ls_ok, luasnip = pcall(require, 'luasnip')

  if not (cmp_ok and ls_ok) then
    print("CMP or LuaSnip not available")
    return false
  end

  -- Load snippets
  require('luasnip.loaders.from_vscode').lazy_load()

  cmp.setup({
    snippet = {
      expand = function(args)
        luasnip.lsp_expand(args.body)
      end,
    },
    window = {
      completion = cmp.config.window.bordered(),
      documentation = cmp.config.window.bordered(),
    },
    mapping = cmp.mapping.preset.insert({
      ['<C-b>'] = cmp.mapping.scroll_docs(-4),
      ['<C-f>'] = cmp.mapping.scroll_docs(4),
      ['<C-Space>'] = cmp.mapping.complete(),
      ['<C-e>'] = cmp.mapping.abort(),
      ['<CR>'] = cmp.mapping.confirm({select = true}),
      ['<Tab>'] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_next_item()
        elseif luasnip.expand_or_locally_jumpable() then
          luasnip.expand_or_jump()
        else
          fallback()
        end
      end, {'i', 's'}),
      ['<S-Tab>'] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_prev_item()
        elseif luasnip.locally_jumpable(-1) then
          luasnip.jump(-1)
        else
          fallback()
        end
      end, {'i', 's'}),
    }),
    sources = cmp.config.sources({
      { name = 'nvim_lsp' },
      { name = 'luasnip' },
      { name = 'nvim_lua' },
    }, {
      { name = 'buffer' },
      { name = 'path' },
    })
  })

  print("CMP setup complete!")
  return true
end

-- Setup immediately, not on LazyDone
M.setup_cmp()

-- Setup LSP after plugins load
vim.api.nvim_create_autocmd("User", {
  pattern = "LazyDone",
  once = true,
  callback = function()
    vim.schedule(function()
      M.setup_lsp()
      -- Retry CMP setup in case it failed first time
      if not M.setup_cmp() then
        vim.defer_fn(M.setup_cmp, 100)
      end
    end)
  end,
})

return M
EOF

cat >> "$INIT_LUA" <<'EOF'

require('a_sub_directory.set')
require('a_sub_directory.remap')
require('a_sub_directory.treesitter')
require('a_sub_directory.plugin_configs')
require('a_sub_directory.lsp')
EOF

###############################################################################
# Clean backups
###############################################################################

find "$NVIM_CONFIG_DIR" -name "*.bak" -delete 2>/dev/null || true

###############################################################################
# Install
###############################################################################

echo "Installing plugins..."
set +e
"$NVIM_CMD" --headless "+Lazy! sync" +qa
set -e

echo ""
echo "✅ Done!"
echo ""
echo "Neovim 0.9.x setup complete with autocompletion!"
echo ""
echo "Autocompletion keys:"
echo "  <C-Space>  - Trigger completion"
echo "  <CR>       - Confirm selection"
echo "  <Tab>      - Next item / expand snippet"
echo "  <S-Tab>    - Previous item"
echo "  <C-e>      - Close completion menu"
echo ""
echo "Other keys:"
echo "  <Space>pm  - Open Mason"
echo "  <Space>pe  - Find files"
echo "  <Space>ps  - Live grep"
echo "  gd         - Go
