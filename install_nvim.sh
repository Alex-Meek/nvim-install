#!/bin/bash

set -e

REPO_URL="https://github.com/arturgoms/nvim"

###############################################################################
# Environment & Checks
###############################################################################

echo "=== Environment Context ==="
echo "User: $USER"
echo "Home: $HOME"
echo "Current Dir: $(pwd)"
echo "==========================="

if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1; then
    echo "CRITICAL ERROR: No C compiler found (gcc/cc). Install gcc to continue."
    exit 1
fi

NVIM_CMD="nvim"
if [ -x "./nvim" ]; then NVIM_CMD="./nvim"; fi

if ! "$NVIM_CMD" --version >/dev/null 2>&1; then
    echo "Neovim not found. Please check PATH."
    exit 1
fi

# Paths
NVIM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
NVIM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
NVIM_BIN_DIR="$NVIM_DATA_DIR/bin"

###############################################################################
# STEP 1: Wipe Data Directory (Mandatory for clean install)
###############################################################################
if [[ -d "$NVIM_DATA_DIR" ]]; then
    echo "Cleaning existing Neovim data directory..."
    rm -rf "$NVIM_DATA_DIR"
fi
mkdir -p "$NVIM_DATA_DIR"
mkdir -p "$NVIM_BIN_DIR"

###############################################################################
# STEP 2: Install Standalone Node.js v22 (For Copilot)
###############################################################################
echo "Checking/Installing standalone Node.js v22..."
ARCH=$(uname -m)
case $ARCH in
    x86_64) NODE_ARCH="x64" ;;
    aarch64) NODE_ARCH="arm64" ;;
    *) echo "Unsupported architecture for auto-node install: $ARCH"; exit 1 ;;
esac

NODE_VER="v22.12.0"
NODE_DIR="$NVIM_DATA_DIR/node-v22"
if [[ ! -x "$NODE_DIR/bin/node" ]]; then
    echo "Downloading Node.js..."
    curl -fLo "/tmp/node.tar.gz" "https://nodejs.org/dist/${NODE_VER}/node-${NODE_VER}-linux-${NODE_ARCH}.tar.gz"
    mkdir -p "$NODE_DIR"
    tar -xzf "/tmp/node.tar.gz" -C "$NODE_DIR" --strip-components=1
    rm "/tmp/node.tar.gz"
fi

###############################################################################
# STEP 3: Install Standalone Ripgrep (For Telescope Files)
###############################################################################
echo "Checking/Installing standalone Ripgrep (rg)..."
RG_BIN="$NVIM_BIN_DIR/rg"
if [[ ! -x "$RG_BIN" ]]; then
    echo "Downloading Ripgrep..."
    RG_VER="14.1.0"
    RG_URL="https://github.com/BurntSushi/ripgrep/releases/download/${RG_VER}/ripgrep-${RG_VER}-${ARCH}-unknown-linux-musl.tar.gz"
    
    curl -fLo "/tmp/rg.tar.gz" "$RG_URL"
    mkdir -p "/tmp/rg_extract"
    tar -xzf "/tmp/rg.tar.gz" -C "/tmp/rg_extract" --strip-components=1
    cp "/tmp/rg_extract/rg" "$RG_BIN"
    rm -rf "/tmp/rg.tar.gz" "/tmp/rg_extract"
    chmod +x "$RG_BIN"
    echo "Ripgrep installed to $RG_BIN"
fi

###############################################################################
# STEP 4: Clone Config
###############################################################################
echo "Cloning configuration..."
if [[ -d "$NVIM_CONFIG_DIR" ]]; then rm -rf "$NVIM_CONFIG_DIR"; fi
mkdir -p "$NVIM_CONFIG_DIR"
git clone --depth 1 "$REPO_URL" "$NVIM_CONFIG_DIR"

###############################################################################
# STEP 5: REPLACE init.lua
###############################################################################
echo "Replacing init.lua..."

cat > "$NVIM_CONFIG_DIR/init.lua" <<EOF
-- [[ PATH INJECTION ]]
local bin_dir = vim.fn.stdpath("data") .. "/bin"
vim.env.PATH = bin_dir .. ":" .. vim.env.PATH

-- [[ BOOTSTRAP LAZY.NVIM ]]
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  print("Bootstrapping lazy.nvim...")
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- [[ LOAD CORE OPTIONS ]]
require("a_sub_directory.set")
require("a_sub_directory.remap")

-- [[ SETUP PLUGINS ]]
require("lazy").setup("lazy-plugins", {
    install = { missing = true },
    checker = { enabled = false },
    change_detection = { notify = false },
})

-- [[ LOAD LSP CONFIG ]]
pcall(require, "a_sub_directory.lsp")
EOF

###############################################################################
# STEP 6: OVERWRITE lazy-plugins.lua (Disable Telescope TS Preview)
###############################################################################
echo "Generating fresh plugin list..."

LAZY_PLUGINS_FILE="$NVIM_CONFIG_DIR/lua/lazy-plugins.lua"

cat > "$LAZY_PLUGINS_FILE" <<EOF
return {
    -- [[ MOONLIGHT THEME ]]
    {
      "shaunsingh/moonlight.nvim",
      lazy = false,
      priority = 1000,
      config = function()
        vim.g.moonlight_italic_comments = true
        vim.g.moonlight_italic_keywords = true
        vim.g.moonlight_italic_functions = true
        vim.g.moonlight_contrast = true
        vim.g.moonlight_disable_background = false
        require("moonlight").set()
      end,
    },

    -- [[ TREESITTER ]]
    {
        "nvim-treesitter/nvim-treesitter",
        lazy = false,
        priority = 900,
        config = function()
            local status_ok, configs = pcall(require, "nvim-treesitter.configs")
            if not status_ok then return end
            configs.setup({
                ensure_installed = {}, 
                sync_install = false,
                auto_install = false,
                highlight = { enable = true },
            })
        end,
    },

    -- [[ TELESCOPE ]]
    {
        "nvim-telescope/telescope.nvim",
        branch = "0.1.x",
        dependencies = { "nvim-lua/plenary.nvim", "nvim-treesitter/nvim-treesitter" },
        config = function()
            local telescope = require("telescope")
            
            telescope.setup({
                defaults = {
                    file_ignore_patterns = { ".git/", "node_modules" },
                    preview = {
                        -- CRITICAL: Disable Telescope's own treesitter previewer.
                        -- It uses broken functions (is_enabled).
                        -- We fall back to standard syntax highlighting, which 
                        -- is safe and still colorful.
                        treesitter = false
                    },
                },
            })
        end
    },

    -- [[ COPILOT ]]
    {
      "zbirenbaum/copilot.lua",
      cmd = "Copilot",
      event = "InsertEnter",
      config = function()
        local node_bin = vim.fn.stdpath("data") .. "/node-v22/bin/node"
        require("copilot").setup({
          copilot_node_command = vim.fn.executable(node_bin) == 1 and node_bin or "node",
          suggestion = {
            enabled = true,
            auto_trigger = true,
            keymap = {
              accept = "<M-l>",
              next = "<M-]>",
              prev = "<M-[>",
              dismiss = "<C-]>",
            },
          },
          panel = { enabled = false },
        })
      end,
    },

    -- [[ STANDARD PLUGINS ]]
    { "nvim-neotest/nvim-nio" },
    { "theprimeagen/harpoon" },
    { "mbbill/undotree" },
    { "tpope/vim-fugitive" },

    -- [[ LSP STACK ]]
    { "williamboman/mason.nvim" },
    { "williamboman/mason-lspconfig.nvim" },
    { "neovim/nvim-lspconfig" },
    { "hrsh7th/nvim-cmp" },
    { "hrsh7th/cmp-nvim-lsp" },
    { "hrsh7th/cmp-buffer" },
    { "hrsh7th/cmp-path" },
    { "saadparwaiz1/cmp_luasnip" },
    { "hrsh7th/cmp-nvim-lua" },
    { "L3MON4D3/LuaSnip" },
    { "rafamadriz/friendly-snippets" },
}
EOF

###############################################################################
# STEP 7: Inject Overrides
###############################################################################

A_SUB_DIR="$NVIM_CONFIG_DIR/lua/a_sub_directory"
mkdir -p "$A_SUB_DIR"
REMAP_FILEPATH="$A_SUB_DIR/remap.lua"
SET_FILEPATH="$A_SUB_DIR/set.lua"
LSP_CUSTOM_FILE="$A_SUB_DIR/lsp.lua"

# [[ SET CONFIG ]]
cat > "$SET_FILEPATH" <<EOF
vim.opt.guicursor = ""
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
local undodir = vim.fn.stdpath("data") .. "/undodir"
vim.opt.undodir = undodir
vim.opt.undofile = true
if vim.fn.isdirectory(undodir) == 0 then vim.fn.mkdir(undodir, "p") end
vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.termguicolors = true
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")
vim.opt.updatetime = 50
vim.opt.colorcolumn = "80"
EOF

# [[ REMAP CONFIG ]]
cat > "$REMAP_FILEPATH" <<EOF
vim.g.mapleader = " "
vim.keymap.set("n", "<leader>pv", vim.cmd.Ex)

-- Telescope lazy load
vim.keymap.set('n', '<leader>pe', function() require('telescope.builtin').find_files() end, { desc = 'Find Files' })
vim.keymap.set('n', '<leader>pw', function() require('telescope.builtin').grep_string() end, { desc = 'Search Word' })
vim.keymap.set('n', '<leader>ps', function() require('telescope.builtin').live_grep() end, { desc = 'Live Grep' })

vim.keymap.set("n", "<leader>vd", function() vim.diagnostic.open_float() end, { desc = "View Diagnostic" })
vim.keymap.set("n", "[d", function() vim.diagnostic.goto_next() end, { desc = "Next Diagnostic" })
vim.keymap.set("n", "]d", function() vim.diagnostic.goto_prev() end, { desc = "Prev Diagnostic" })

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")
vim.keymap.set("n", "J", "mzJ\`z")
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")
vim.keymap.set("x", "<leader>p", [["_dP]])
vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]])
vim.keymap.set("n", "<leader>Y", [["+Y]])
vim.keymap.set({ "n", "v" }, "<leader>d", "\"_d")
vim.keymap.set("i", "<C-c>", "<Esc>")
vim.keymap.set("n", "Q", "<nop>")
vim.keymap.set("n", "<C-f>", "<cmd>silent !tmux neww tmux-sessionizer<CR>")
vim.keymap.set("n", "<leader>f", vim.lsp.buf.format)
vim.keymap.set("n", "<C-k>", "<cmd>cnext<CR>zz")
vim.keymap.set("n", "<C-j>", "<cmd>cprev<CR>zz")
vim.keymap.set("n", "<leader>k", "<cmd>lnext<CR>zz")
vim.keymap.set("n", "<leader>j", "<cmd>lprev<CR>zz")
vim.keymap.set("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]])
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })
vim.keymap.set("n", "<leader><leader>", function() vim.cmd("so") end)
EOF

# [[ LSP CONFIG ]]
cat > "$LSP_CUSTOM_FILE" <<EOF
local capabilities = vim.lsp.protocol.make_client_capabilities()
local status_ok, cmp_nvim_lsp = pcall(require, 'cmp_nvim_lsp')
if status_ok then capabilities = cmp_nvim_lsp.default_capabilities(capabilities) end
local function on_attach(client, bufnr)
  local nmap = function(keys, func, desc)
    if desc then desc = 'LSP: ' .. desc end
    vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
  end
  nmap('gd', vim.lsp.buf.definition, 'Goto Definition')
  nmap('K', vim.lsp.buf.hover, 'Hover')
  nmap('<leader>vca', vim.lsp.buf.code_action, 'Code Action')
  nmap('<leader>vrn', vim.lsp.buf.rename, 'Rename')
end
vim.lsp.config.lua_ls = { capabilities = capabilities, on_attach = on_attach, settings = { Lua = { workspace = { checkThirdParty = false }, telemetry = { enable = false } } } }
vim.lsp.config.pyright = { capabilities = capabilities, on_attach = on_attach }
vim.lsp.config.rust_analyzer = { capabilities = capabilities, on_attach = on_attach }
vim.lsp.config.elixirls = { capabilities = capabilities, on_attach = on_attach }
require('mason').setup()
require('mason-lspconfig').setup { ensure_installed = { 'lua_ls', 'pyright', 'rust_analyzer', 'elixirls' }, automatic_installation = true }
vim.lsp.enable({ 'lua_ls', 'pyright', 'rust_analyzer', 'elixirls' })
EOF

###############################################################################
# STEP 8: Automated Install Execution
###############################################################################

echo "========================================="
echo "PHASE 1: Plugin Installation (Lazy.nvim)"
echo "========================================="
set +e
"$NVIM_CMD" --headless "+Lazy! sync" +qa
set -e

echo "========================================="
echo "PHASE 2: Synchronous Treesitter Compilation"
echo "========================================="

TS_BOOTSTRAP_FILE="$NVIM_CONFIG_DIR/ts_bootstrap.lua"
cat > "$TS_BOOTSTRAP_FILE" <<EOF
local ts_path = "$NVIM_DATA_DIR/lazy/nvim-treesitter"
if vim.fn.isdirectory(ts_path) == 0 then vim.cmd("q") else vim.opt.runtimepath:prepend(ts_path) end

local status_ok, ts_install = pcall(require, "nvim-treesitter.install")
if not status_ok then
    vim.cmd("packadd nvim-treesitter")
    ts_install = require("nvim-treesitter.install")
end

local langs = { "c", "lua", "vim", "vimdoc", "query", "python", "go", "rust" }
print("Installing parsers synchronously: " .. table.concat(langs, ", "))
require("nvim-treesitter.install").compilers = { "cc", "gcc", "clang", "cl" }
pcall(function() ts_install.ensure_installed_sync(langs) end)
print("Installation done.")
vim.cmd("q")
EOF

"$NVIM_CMD" --headless -c "luafile $TS_BOOTSTRAP_FILE"
rm "$TS_BOOTSTRAP_FILE"

echo "========================================="
echo "INSTALLATION SUCCESSFULLY COMPLETED"
echo "========================================="
