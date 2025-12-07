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
else
    NVIM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
    NVIM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
fi

echo "Neovim config dir: $NVIM_CONFIG_DIR"
echo "Neovim data dir:   $NVIM_DATA_DIR"

###############################################################################
# Install Node.js + CLI tools on MSYS2 (for language servers, fzf, rg, etc.)
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

    local NODE_PKG=""

    case "${MSYSTEM:-}" in
        UCRT64)
            NODE_PKG="mingw-w64-ucrt-x86_64-nodejs"
            ;;
        CLANG64)
            NODE_PKG="mingw-w64-clang-x86_64-nodejs"
            ;;
        MINGW64)
            NODE_PKG="mingw-w64-x86_64-nodejs"
            ;;
        MINGW32)
            NODE_PKG="mingw-w64-i686-nodejs"
            ;;
        CLANGARM64)
            NODE_PKG="mingw-w64-clang-aarch64-nodejs"
            ;;
        MSYS|"")
            echo "MSYSTEM=MSYS: installing a MinGW/UCRT Node.js package anyway."
            if [ "$UNAME_MACH" = "x86_64" ]; then
                NODE_PKG="mingw-w64-ucrt-x86_64-nodejs"
            elif [ "$UNAME_MACH" = "aarch64" ]; then
                NODE_PKG="mingw-w64-clang-aarch64-nodejs"
            else
                echo "Unknown architecture '$UNAME_MACH'; falling back to 'nodejs'."
                NODE_PKG="nodejs"
            fi
            ;;
        *)
            echo "Unrecognised MSYSTEM='${MSYSTEM}'. Trying UCRT64/CLANG-style Node."
            if [ "$UNAME_MACH" = "x86_64" ]; then
                NODE_PKG="mingw-w64-ucrt-x86_64-nodejs"
            elif [ "$UNAME_MACH" = "aarch64" ]; then
                NODE_PKG="mingw-w64-clang-aarch64-nodejs"
            else
                NODE_PKG="nodejs"
            fi
            ;;
    esac

    echo "Installing package '$NODE_PKG'..."
    set +e
    pacman -Sy --needed --noconfirm "$NODE_PKG"
    status=$?
    set -e

    if [ $status -ne 0 ]; then
        echo "pacman failed to install '$NODE_PKG' (exit $status)."
        echo "Check available Node packages with:"
        echo "  pacman -Ss nodejs"
        return $status
    fi

    echo "Node.js install complete. Detected versions (if on PATH):"
    command -v node && node --version || echo "node not on PATH"
    command -v npm && npm --version || echo "npm not on PATH"
}

install_cli_tools_for_msys2() {
    echo "=== Installing CLI tools (fzf, ripgrep, findutils) via MSYS2 pacman ==="

    if ! command -v pacman >/dev/null 2>&1; then
        echo "'pacman' not found. This function is intended for MSYS2."
        return 1
    fi

    local pkgs=(
        mingw-w64-ucrt-x86_64-fzf
        mingw-w64-ucrt-x86_64-ripgrep
        findutils
    )

    pacman -Sy --needed --noconfirm "${pkgs[@]}"
}

if [[ "$UNAME_STR" == *"mingw"* ]] || [[ "$UNAME_STR" == *"msys"* ]]; then
    install_node_for_msys2
    install_cli_tools_for_msys2
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
# Force sessionoptions to the recommended value for auto-session
###############################################################################

if [[ -f "$INIT_LUA" ]]; then
    tmp="${INIT_LUA}.tmp"
    {
        echo 'vim.o.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"'
        awk 'NR>1 && $0 !~ /sessionoptions/ { print }' "$INIT_LUA"
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
# Patch lazy-plugins.lua: add nvim-nio and moonlight colorscheme
###############################################################################

LAZY_PLUGINS_FILE="$NVIM_CONFIG_DIR/lua/lazy-plugins.lua"
if [[ -f "$LAZY_PLUGINS_FILE" ]]; then
    tmp="${LAZY_PLUGINS_FILE}.tmp"
    awk '
      # After custom.plugins.debug, inject moonlight + nvim-nio (if not already there)
      /require .custom.plugins.debug/ && !done {
        print
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
        print "    { \"nvim-neotest/nvim-nio\" },"
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
LSP_CUSTOM_FILE="$A_SUB_DIR/lsp.lua"

create_file "$REMAP_FILEPATH"
create_file "$LSP_CUSTOM_FILE"

# Your existing remaps
CONTENT="
vim.g.mapleader = ' '

vim.keymap.set('n', '<leader>pv', ':Ex<CR>')

vim.keymap.set('v', 'J', ':m \'>+1<CR>gv=gv')
vim.keymap.set('v', 'K', ':m \'<-2<CR>gv=gv')

vim.keymap.set('n', 'J', 'mzJ\`z')

vim.keymap.set('n', '<C-d>', '<C-d>zz')
vim.keymap.set('n', '<C-u>', '<C-u>zz')

vim.keymap.set('n', 'n', 'nzzzv')
vim.keymap.set('n', 'N', 'nzzzv')

vim.keymap.set('x', '<leader>p', '\"_dP')

vim.keymap.set('n', '<leader>y', '\"+y')
vim.keymap.set('v', '<leader>y', '\"+y')
vim.keymap.set('n', '<leader>Y', '\"+y')

vim.keymap.set('n', '<leader>d', '\"_d')
vim.keymap.set('v', '<leader>d', '\"_d')

vim.keymap.set('n', 'Q', '<nop>')

vim.keymap.set('n', '<C-k>', '<cmd>cnext<CR>zz')
vim.keymap.set('n', '<C-j>', '<cmd>cprev<CR>zz')
vim.keymap.set('n', '<leader>k', '<cmd>lnext<CR>zz')
vim.keymap.set('n', '<leader>j', '<cmd>lprev<CR>zz')

vim.keymap.set('n', '<leader>s', [[:%s/\\<<C-r><C-w>\\>/<C-r><C-w>/gI<Left><Left><Left>]])
vim.keymap.set('n', '<leader>x', '<cmd>!chmod +x %<CR>', { silent = true })
"
add_to_file "$REMAP_FILEPATH" "$CONTENT"

# Modern LSP setup using vim.lsp.config + mason-lspconfig v2
CONTENT="
-- Minimal modern LSP setup using vim.lsp.config and mason-lspconfig v2

local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

local function on_attach(client, bufnr)
  local nmap = function(keys, func, desc)
    if desc then desc = 'LSP: ' .. desc end
    vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
  end

  nmap('gd', vim.lsp.buf.definition, 'Goto Definition')
  nmap('K', vim.lsp.buf.hover, 'Hover')
  nmap('<leader>vca', vim.lsp.buf.code_action, 'Code Action')
  nmap('<leader>vrn', vim.lsp.buf.rename, 'Rename')
  nmap('[d', vim.diagnostic.goto_prev, 'Prev Diagnostic')
  nmap(']d', vim.diagnostic.goto_next, 'Next Diagnostic')
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

vim.lsp.config.pyright = {
  capabilities = capabilities,
  on_attach = on_attach,
}

vim.lsp.config.rust_analyzer = {
  capabilities = capabilities,
  on_attach = on_attach,
}

vim.lsp.config.elixirls = {
  capabilities = capabilities,
  on_attach = on_attach,
}

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
-- Load my personal overrides
require('a_sub_directory.remap')
require('a_sub_directory.lsp')
"
fi

###############################################################################
# Pre-install plugins via lazy.nvim
###############################################################################

echo "Running Lazy! sync to install plugins..."
set +e
"$NVIM_CMD" --headless "+Lazy! sync" +qa
lazy_status=$?
set -e

if [ $lazy_status -ne 0 ]; then
    echo "Lazy! sync exited with status $lazy_status."
    echo "You can open Neovim and run :Lazy sync manually if anything is missing."
fi

echo "Done. Config from $REPO_URL with your keymaps and LSP layered on top (auto-session disabled)."
