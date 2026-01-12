#!/bin/bash

set -e

REPO_URL="https://github.com/arturgoms/nvim"

###############################################################################
# Detect Neovim binary
###############################################################################

NVIM_CMD="nvim"
if [ -x "$HOME/.local/nvim-win64/bin/nvim.exe" ]; then
    NVIM_CMD="$HOME/.local/nvim-win64/bin/nvim.exe"
fi

if ! "$NVIM_CMD" --version >/dev/null 2>&1; then
    echo "Neovim not found or not executable at: $NVIM_CMD"
    echo "Install Neovim (e.g. to ~/.local/nvim-win64) and re-run this script."
    exit 1
fi

echo "Using Neovim: $NVIM_CMD"

###############################################################################
# Choose config/data dirs to match Neovim on this OS
###############################################################################

UNAME_STR=$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')

if [[ "$UNAME_STR" == *"mingw"* ]] || [[ "$UNAME_STR" == *"msys"* ]]; then
    # Windows (MSYS/Git Bash)
    NVIM_CONFIG_DIR="$HOME/AppData/Local/nvim"
    NVIM_DATA_DIR="$HOME/AppData/Local/nvim-data"
    IS_WINDOWS=1
else
    NVIM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
    NVIM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
    IS_WINDOWS=0
fi

echo "Neovim config dir: $NVIM_CONFIG_DIR"
echo "Neovim data dir:   $NVIM_DATA_DIR"

###############################################################################
# Install Node.js, CLI tools, and Compilers on MSYS2
###############################################################################

install_node_for_msys2() {
    echo "=== Installing Node.js (and npm) via MSYS2 pacman ==="
    echo "MSYSTEM=${MSYSTEM:-<empty>}"

    if ! command -v pacman >/dev/null 2>&1; then
        echo "'pacman' not found. This function is intended for MSYS2."
        return 1
    fi

    local UNAME_MACH
    UNAME_MACH=$(uname -m 2>/dev/null || echo unknown)

    local PREFIX="mingw-w64-x86_64" # Default fallback

    case "${MSYSTEM:-}" in
        UCRT64)     PREFIX="mingw-w64-ucrt-x86_64" ;;
        CLANG64)    PREFIX="mingw-w64-clang-x86_64" ;;
        MINGW64)    PREFIX="mingw-w64-x86_64" ;;
        MINGW32)    PREFIX="mingw-w64-i686" ;;
        CLANGARM64) PREFIX="mingw-w64-clang-aarch64" ;;
        *)
             if [ "$UNAME_MACH" = "x86_64" ]; then
                 PREFIX="mingw-w64-ucrt-x86_64"
             fi
             ;;
    esac

    local NODE_PKG="${PREFIX}-nodejs"

    local TOOLS_PKGS=(
        "${PREFIX}-fzf"
        "${PREFIX}-ripgrep"
        "${PREFIX}-fd"
        "${PREFIX}-7zip"
        "${PREFIX}-toolchain"
        "${PREFIX}-python-pip"
        "${PREFIX}-go"
        "${PREFIX}-rust"
        findutils
    )

    echo "Installing Node and Tools with prefix: $PREFIX"

    set +e
    pacman -Sy --needed --noconfirm "$NODE_PKG" "${TOOLS_PKGS[@]}"
    status=$?
    set -e

    if [ $status -ne 0 ]; then
        echo "pacman failed to install some packages. Continuing..."
    fi

    echo "Node.js install complete. Detected versions (if on PATH):"
    command -v node && node --version || echo "node not on PATH"
    command -v npm && npm --version || echo "npm not on PATH"
}

if [[ "$UNAME_STR" == *"mingw"* ]] || [[ "$UNAME_STR" == *"msys"* ]]; then
    install_node_for_msys2

    echo "=== Installing Neovim Providers ==="
    if command -v npm >/dev/null 2>&1; then
        echo "Installing neovim npm provider..."
        npm install -g neovim || echo "Failed to install npm neovim provider"
    fi

    if command -v pip >/dev/null 2>&1; then
        echo "Installing pynvim python provider..."
        pip install pynvim || echo "Failed to install pynvim"
    fi
fi

###############################################################################
# Helper functions
###############################################################################

create_directory() {
    local directory="$1"
    if ! mkdir -p "$directory"; then
        echo "Failed to create directory \"$directory\"."
        return 1
    else
        echo "Directory \"$directory\" created successfully."
    fi
}

create_file() {
    local file="$1"
    if ! echo "" >"$file"; then
        echo "Failed to create file \"$file\"."
        return 1
    else
        echo "File \"$file\" created successfully."
    fi
}

add_to_file() {
    local file="$1"
    local edits="$2"

    if ! {
        cat >>"$file" <<EOF
$edits
EOF
    }; then
        echo "Failed to append to file \"$file\"."
        return 1
    fi
}

###############################################################################
# Clone arturgoms/nvim as config
###############################################################################

echo "Cloning Neovim config from $REPO_URL into $NVIM_CONFIG_DIR"

if [[ -d "$NVIM_CONFIG_DIR" ]]; then
    echo "Removing existing config dir: $NVIM_CONFIG_DIR"
    rm -rf "$NVIM_CONFIG_DIR"
fi

create_directory "$NVIM_CONFIG_DIR"
git clone --depth 1 "$REPO_URL" "$NVIM_CONFIG_DIR"

INIT_LUA="$NVIM_CONFIG_DIR/init.lua"

###############################################################################
# FIX: Force Shell to PowerShell/CMD on Windows
###############################################################################

if [ "$IS_WINDOWS" -eq 1 ]; then
    echo "Applying Windows Shell Fix to init.lua..."
    tmp="${INIT_LUA}.tmp"
    cat > "$tmp" <<EOF
-- [[ WINDOWS COMPATIBILITY FIX ]]
if vim.fn.has("win32") == 1 then
  if vim.fn.executable("pwsh") == 1 then
    vim.opt.shell = "pwsh"
    vim.opt.shellcmdflag = "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command [Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;"
    vim.opt.shellredir = "2>&1 | Out-File -Encoding UTF8 %s; exit \$LastExitCode"
    vim.opt.shellpipe = "2>&1 | Out-File -Encoding UTF8 %s; exit \$LastExitCode"
    vim.opt.shellquote = ""
    vim.opt.shellxquote = ""
  else
    vim.opt.shell = "cmd.exe"
    vim.opt.shellcmdflag = "/s /c"
  end
end

EOF
    cat "$INIT_LUA" >> "$tmp"
    mv "$tmp" "$INIT_LUA"
fi

###############################################################################
# Force sessionoptions to the recommended value for auto-session
###############################################################################

if [[ -f "$INIT_LUA" ]]; then
    tmp="${INIT_LUA}.tmp"
    {
        awk 'NR>1 && $0 !~ /sessionoptions/ { print }' "$INIT_LUA"
        echo 'vim.o.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"'
    } >"$tmp"
    mv "$tmp" "$INIT_LUA"
fi

###############################################################################
# Disable upstream lsp.lsp-setup and use our own LSP config instead
###############################################################################

if [[ -f "$INIT_LUA" ]]; then
    tmp="${INIT_LUA}.tmp"
    awk '
      /require.*lsp\.lsp-setup/ && !done {
        print "-- " $0  # comment out the upstream LSP setup
        done=1
        next
      }
      { print }
    ' "$INIT_LUA" >"$tmp"
    mv "$tmp" "$INIT_LUA"
fi

###############################################################################
# Disable auto-session plugin (set enabled = false in its lazy spec)
###############################################################################

AUTO_FILES=$(grep -rl 'rmagatti/auto-session' "$NVIM_CONFIG_DIR/lua" 2>/dev/null || true)
for f in $AUTO_FILES; do
    echo "Disabling auto-session in $f"
    tmp="${f}.tmp"
    awk '
      /"rmagatti\/auto-session"/ && !done {
        print $0
        print "    enabled = false,"
        done=1
        next
      }
      { print }
    ' "$f" >"$tmp"
    mv "$tmp" "$f"
done

###############################################################################
# NUKE Existing Copilot Configs
###############################################################################

echo "Disabling upstream Copilot configurations..."
grep -rl "zbirenbaum/copilot.lua" "$NVIM_CONFIG_DIR/lua" | while read -r file; do
    if [[ "$(basename "$file")" == "lazy-plugins.lua" ]]; then
        continue
    fi
    echo "  - Emptying conflicting file: $file"
    echo "return {}" > "$file"
done

###############################################################################
# Patch lazy-plugins.lua
###############################################################################

LAZY_PLUGINS_FILE="$NVIM_CONFIG_DIR/lua/lazy-plugins.lua"
if [[ -f "$LAZY_PLUGINS_FILE" ]]; then
    tmp="${LAZY_PLUGINS_FILE}.tmp"
    awk '
      /require .custom.plugins.debug/ && !done {
        print
        print "    -- [[ CUSTOM PLUGINS INJECTION ]]"
        print "    {"
        print "      \"shaunsingh/moonlight.nvim\","
        print "      lazy = false,"
        print "      priority = 1000,"
        print "      config = function()"
        print "        vim.g.moonlight_italic_comments = true"
        print "        vim.g.moonlight_italic_keywords = true"
        print "        vim.g.moonlight_italic_functions = true"
        print "        vim.g.moonlight_contrast = true"
        print "        vim.g.moonlight_disable_background = false"
        print "        require(\"moonlight\").set()"
        print "      end,"
        print "    },"

        print "    -- [[ COPILOT (Clean Single Config) ]]"
        print "    {"
        print "      \"zbirenbaum/copilot.lua\","
        print "      cmd = \"Copilot\","
        print "      event = \"InsertEnter\","
        print "      config = function()"
        print "        require(\"copilot\").setup({"
        print "          suggestion = {"
        print "            enabled = true,"
        print "            auto_trigger = true,"
        print "            keymap = {"
        print "              accept = \"<M-l>\","
        print "              next = \"<M-]>\","
        print "              prev = \"<M-[\","
        print "              dismiss = \"<C-]>\","
        print "            },"
        print "          },"
        print "          panel = { enabled = false },"
        print "        })"
        print "      end,"
        print "    },"

        print "    { \"nvim-neotest/nvim-nio\" },"
        print "    { \"theprimeagen/harpoon\" },"
        print "    { \"mbbill/undotree\" },"
        print "    { \"tpope/vim-fugitive\" },"
        print "    { \"hrsh7th/nvim-cmp\" },"
        print "    { \"hrsh7th/cmp-nvim-lsp\" },"
        print "    { \"hrsh7th/cmp-buffer\" },"
        print "    { \"hrsh7th/cmp-path\" },"
        print "    { \"saadparwaiz1/cmp_luasnip\" },"
        print "    { \"hrsh7th/cmp-nvim-lua\" },"
        print "    { \"L3MON4D3/LuaSnip\" },"
        print "    { \"rafamadriz/friendly-snippets\" },"
        done=1
        next
      }
      { print }
    ' "$LAZY_PLUGINS_FILE" >"$tmp"
    mv "$tmp" "$LAZY_PLUGINS_FILE"
fi

###############################################################################
# Create our overrides directory and files
###############################################################################

A_SUB_DIR="$NVIM_CONFIG_DIR/lua/a_sub_directory"
create_directory "$A_SUB_DIR"

REMAP_FILEPATH="$A_SUB_DIR/remap.lua"
SET_FILEPATH="$A_SUB_DIR/set.lua"
LSP_CUSTOM_FILE="$A_SUB_DIR/lsp.lua"

create_file "$REMAP_FILEPATH"
create_file "$SET_FILEPATH"
create_file "$LSP_CUSTOM_FILE"

# [[ PRIMEAGEN SET CONFIG ]]
CONTENT="
vim.opt.guicursor = \"\"

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

local home = os.getenv(\"HOME\") or os.getenv(\"USERPROFILE\") or \"\"
local undodir = home .. \"/.vim/undodir\"

vim.opt.undodir = undodir
vim.opt.undofile = true

if vim.fn.isdirectory(undodir) == 0 then
    vim.fn.mkdir(undodir, \"p\")
end

vim.opt.hlsearch = false
vim.opt.incsearch = true

vim.opt.termguicolors = true

vim.opt.scrolloff = 8
vim.opt.signcolumn = \"yes\"
vim.opt.isfname:append(\"@-@\")

vim.opt.updatetime = 50

vim.opt.colorcolumn = \"80\"
"
add_to_file "$SET_FILEPATH" "$CONTENT"

# [[ PRIMEAGEN REMAP CONFIG (Updated with <leader>vd) ]]
CONTENT="
vim.g.mapleader = \" \"
vim.keymap.set(\"n\", \"<leader>pv\", vim.cmd.Ex)

-- [[ TELESCOPE ]]
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>pe', builtin.find_files, { desc = 'Find Files' })
vim.keymap.set('n', '<leader>pw', builtin.grep_string, { desc = 'Search Word' })
vim.keymap.set('n', '<leader>ps', builtin.live_grep, { desc = 'Live Grep' })

-- [[ DIAGNOSTICS (Added to fix <leader>vd splitting terminal) ]]
vim.keymap.set(\"n\", \"<leader>vd\", function() vim.diagnostic.open_float() end, { desc = \"View Diagnostic\" })
vim.keymap.set(\"n\", \"[d\", function() vim.diagnostic.goto_next() end, { desc = \"Next Diagnostic\" })
vim.keymap.set(\"n\", \"]d\", function() vim.diagnostic.goto_prev() end, { desc = \"Prev Diagnostic\" })

-- [[ PRIMEAGEN MAPS ]]
vim.keymap.set(\"v\", \"J\", \":m '>+1<CR>gv=gv\")
vim.keymap.set(\"v\", \"K\", \":m '<-2<CR>gv=gv\")

vim.keymap.set(\"n\", \"J\", \"mzJ\`z\")
vim.keymap.set(\"n\", \"<C-d>\", \"<C-d>zz\")
vim.keymap.set(\"n\", \"<C-u>\", \"<C-u>zz\")
vim.keymap.set(\"n\", \"n\", \"nzzzv\")
vim.keymap.set(\"n\", \"N\", \"Nzzzv\")

vim.keymap.set(\"n\", \"<leader>vwm\", function()
    require(\"vim-with-me\").StartVimWithMe()
end)
vim.keymap.set(\"n\", \"<leader>svwm\", function()
    require(\"vim-with-me\").StopVimWithMe()
end)

vim.keymap.set(\"x\", \"<leader>p\", [[\"_dP]])

vim.keymap.set({ \"n\", \"v\" }, \"<leader>y\", [[\"+y]])
vim.keymap.set(\"n\", \"<leader>Y\", [[\"+Y]])

vim.keymap.set({ \"n\", \"v\" }, \"<leader>d\", \"\\\"_d\")

vim.keymap.set(\"i\", \"<C-c>\", \"<Esc>\")

vim.keymap.set(\"n\", \"Q\", \"<nop>\")
vim.keymap.set(\"n\", \"<C-f>\", \"<cmd>silent !tmux neww tmux-sessionizer<CR>\")
vim.keymap.set(\"n\", \"<leader>f\", vim.lsp.buf.format)

vim.keymap.set(\"n\", \"<C-k>\", \"<cmd>cnext<CR>zz\")
vim.keymap.set(\"n\", \"<C-j>\", \"<cmd>cprev<CR>zz\")
vim.keymap.set(\"n\", \"<leader>k\", \"<cmd>lnext<CR>zz\")
vim.keymap.set(\"n\", \"<leader>j\", \"<cmd>lprev<CR>zz\")

vim.keymap.set(\"n\", \"<leader>s\", [[:%s/\\<<C-r><C-w>\\>/<C-r><C-w>/gI<Left><Left><Left>]])
vim.keymap.set(\"n\", \"<leader>x\", \"<cmd>!chmod +x %<CR>\", { silent = true })

vim.keymap.set(
    \"n\",
    \"<leader>ee\",
    \"oif err != nil {<CR>}<Esc>Oreturn err<Esc>\"
)

vim.keymap.set(\"n\", \"<leader>mr\", function()
    require(\"cellular-automaton\").start_animation(\"make_it_rain\")
end)

vim.keymap.set(\"n\", \"<leader><leader>\", function()
    vim.cmd(\"so\")
end)
"
add_to_file "$REMAP_FILEPATH" "$CONTENT"

# Modern LSP setup
CONTENT="
local capabilities = vim.lsp.protocol.make_client_capabilities()
local status_ok, cmp_nvim_lsp = pcall(require, 'cmp_nvim_lsp')
if status_ok then
    capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
end

local function on_attach(client, bufnr)
  local nmap = function(keys, func, desc)
    if desc then desc = 'LSP: ' .. desc end
    vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
  end

  nmap('gd', vim.lsp.buf.definition, 'Goto Definition')
  nmap('K', vim.lsp.buf.hover, 'Hover')
  nmap('<leader>vca', vim.lsp.buf.code_action, 'Code Action')
  nmap('<leader>vrn', vim.lsp.buf.rename, 'Rename')
  -- We now set [d and ]d globally in remap.lua, but setting here locally is fine too (redundancy is okay)
end

vim.lsp.config.lua_ls = {
  capabilities = capabilities,
  on_attach = on_attach,
  settings = {
    Lua = {
      workspace = { checkThirdParty = false },
      telemetry = { enable = false },
    },
  },
}

vim.lsp.config.pyright = { capabilities = capabilities, on_attach = on_attach }
vim.lsp.config.rust_analyzer = { capabilities = capabilities, on_attach = on_attach }
vim.lsp.config.elixirls = { capabilities = capabilities, on_attach = on_attach }

require('mason').setup()
require('mason-lspconfig').setup {
  ensure_installed = { 'lua_ls', 'pyright', 'rust_analyzer', 'elixirls' },
  automatic_installation = true,
}

vim.lsp.enable({ 'lua_ls', 'pyright', 'rust_analyzer', 'elixirls' })
"
add_to_file "$LSP_CUSTOM_FILE" "$CONTENT"

###############################################################################
# Ensure our overrides are required last from init.lua
###############################################################################

if [[ -f "$INIT_LUA" ]]; then
    add_to_file "$INIT_LUA" "
require('a_sub_directory.set')
require('a_sub_directory.remap')
require('a_sub_directory.lsp')
"
fi

###############################################################################
# Pre-install plugins via lazy.nvim
###############################################################################

echo "Running Lazy! sync to install plugins and updating TreeSitter..."
set +e
"$NVIM_CMD" --headless "+Lazy! sync" "+TSUpdate" +qa
lazy_status=$?
set -e

if [ $lazy_status -ne 0 ]; then
    echo "Lazy! sync exited with status $lazy_status."
    echo "You can open Neovim and run :Lazy sync manually if anything is missing."
fi

echo "Done. <leader>vd now correctly opens diagnostic float (instead of splitting)."
