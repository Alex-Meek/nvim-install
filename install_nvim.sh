#!/bin/bash

set -e

REPO_URL="https://github.com/arturgoms/nvim"

###############################################################################
# Setup Local Binary Paths (No Root Required)
###############################################################################

# Ensure ~/.local/bin exists and is in PATH for this script execution
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/share"
export PATH="$HOME/.local/bin:$PATH"

###############################################################################
# Detect Neovim binary
###############################################################################

NVIM_CMD="nvim"

# Cleanup broken install if detected (the "Not: command not found" issue)
if [ -f "$HOME/.local/bin/nvim" ]; then
    # Check if it's a binary or a text file (error page)
    if grep -q "Not Found" "$HOME/.local/bin/nvim" 2>/dev/null || \
       grep -q "DOCTYPE html" "$HOME/.local/bin/nvim" 2>/dev/null; then
        echo "Detected broken Neovim download. Removing..."
        rm "$HOME/.local/bin/nvim"
    fi
fi

###############################################################################
# Choose config/data dirs to match Neovim on this OS
###############################################################################

UNAME_STR=$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')
UNAME_MACH=$(uname -m 2>/dev/null || echo unknown)

if [[ "$UNAME_STR" == *"mingw"* ]] || [[ "$UNAME_STR" == *"msys"* ]]; then
    # Windows (MSYS/Git Bash)
    NVIM_CONFIG_DIR="$HOME/AppData/Local/nvim"
    NVIM_DATA_DIR="$HOME/AppData/Local/nvim-data"
else
    # Linux / MacOS / BSD
    NVIM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
    NVIM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
fi

###############################################################################
# Dependency Installation Functions
###############################################################################

install_deps_linux_local() {
    echo "=== Checking Dependencies for Linux (Local Install) ==="

    # 1. Neovim AppImage (Install if missing)
    if ! command -v nvim >/dev/null 2>&1; then
        echo "Neovim not found. Downloading AppImage to ~/.local/bin..."
        
        # Determine architecture for correct URL
        if [ "$UNAME_MACH" = "aarch64" ]; then
            NVIM_URL="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-arm64.appimage"
        else
            NVIM_URL="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage"
        fi

        echo "Downloading from: $NVIM_URL"
        
        # -f fails silently on 404 (prevents downloading error pages)
        # -L follows redirects
        if curl -f -L -o "$HOME/.local/bin/nvim" "$NVIM_URL"; then
            chmod u+x "$HOME/.local/bin/nvim"
            NVIM_CMD="$HOME/.local/bin/nvim"
            echo "Neovim installed locally."
        else
            echo "Error: Failed to download Neovim. Please check your internet connection or architecture."
            rm -f "$HOME/.local/bin/nvim"
            exit 1
        fi
    else
        echo "Neovim found: $(command -v nvim)"
    fi

    # 2. Node.js (Verify existence)
    if ! command -v node >/dev/null 2>&1; then
        echo "Node.js not found. Installing locally (v20.18.0 LTS)..."
        local NODE_VER="v20.18.0"
        local NODE_DIST="node-$NODE_VER-linux-x64"
        local NODE_URL="https://nodejs.org/dist/$NODE_VER/$NODE_DIST.tar.xz"
        
        curl -L -o "/tmp/$NODE_DIST.tar.xz" "$NODE_URL"
        tar -xf "/tmp/$NODE_DIST.tar.xz" -C "$HOME/.local/share"
        
        ln -sf "$HOME/.local/share/$NODE_DIST/bin/node" "$HOME/.local/bin/node"
        ln -sf "$HOME/.local/share/$NODE_DIST/bin/npm" "$HOME/.local/bin/npm"
        ln -sf "$HOME/.local/share/$NODE_DIST/bin/npx" "$HOME/.local/bin/npx"
        
        rm "/tmp/$NODE_DIST.tar.xz"
        echo "Node.js installed locally."
    else
        echo "Node.js found: $(command -v node)"
    fi

    # 3. Ripgrep (Verify existence)
    if ! command -v rg >/dev/null 2>&1; then
        echo "Ripgrep (rg) not found. Installing locally..."
        local RG_VER="14.1.0"
        local RG_DIST="ripgrep-$RG_VER-x86_64-unknown-linux-musl"
        local RG_URL="https://github.com/BurntSushi/ripgrep/releases/download/$RG_VER/$RG_DIST.tar.gz"
        
        curl -L -o "/tmp/rg.tar.gz" "$RG_URL"
        tar -xf "/tmp/rg.tar.gz" -C "/tmp"
        mv "/tmp/$RG_DIST/rg" "$HOME/.local/bin/rg"
        rm -rf "/tmp/rg.tar.gz" "/tmp/$RG_DIST"
        echo "Ripgrep installed locally."
    else
        echo "Ripgrep found: $(command -v rg)"
    fi

    # 4. FZF (Verify existence)
    if ! command -v fzf >/dev/null 2>&1; then
        echo "FZF not found. Installing locally..."
        if [ -d "$HOME/.fzf" ]; then rm -rf "$HOME/.fzf"; fi
        git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
        "$HOME/.fzf/install" --bin --no-key-bindings --no-completion --no-update-rc
        ln -sf "$HOME/.fzf/bin/fzf" "$HOME/.local/bin/fzf"
        echo "FZF installed locally."
    else
        echo "FZF found: $(command -v fzf)"
    fi
}

###############################################################################
# Run Environment Setup
###############################################################################

if [[ "$UNAME_STR" == "linux" ]]; then
    install_deps_linux_local
fi

# Final Check
if ! command -v nvim >/dev/null 2>&1; then
    echo "Critical: Neovim binary still not found in PATH."
    exit 1
fi

###############################################################################
# Clone arturgoms/nvim as config
###############################################################################

echo "Cloning Neovim config from $REPO_URL into $NVIM_CONFIG_DIR"

if [[ -d "$NVIM_CONFIG_DIR" ]]; then
    echo "Removing existing config dir: $NVIM_CONFIG_DIR"
    rm -rf "$NVIM_CONFIG_DIR"
fi

# Helper functions
create_directory() { mkdir -p "$1"; }
create_file() { echo "" >"$1"; }
add_to_file() { cat >>"$1" <<EOF
$2
EOF
}

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
# Patch lazy-plugins.lua: add moonlight, nvim-nio, and extra plugins
###############################################################################

LAZY_PLUGINS_FILE="$NVIM_CONFIG_DIR/lua/lazy-plugins.lua"
if [[ -f "$LAZY_PLUGINS_FILE" ]] && ! grep -q 'shaunsingh/moonlight.nvim' "$LAZY_PLUGINS_FILE" 2>/dev/null; then
    tmp="${LAZY_PLUGINS_FILE}.tmp"
    awk '
      # After custom.plugins.debug, inject moonlight, nvim-nio, and extra plugins
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

# Modern LSP setup
CONTENT="
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
require('a_sub_directory.remap')
require('a_sub_directory.lsp')
"
fi

###############################################################################
# Pre-install plugins via lazy.nvim
###############################################################################

echo "Running Lazy! sync..."
set +e
"$NVIM_CMD" --headless "+Lazy! sync" +qa
status=$?
set -e

echo "Done. Config installed. Ensure $HOME/.local/bin is in your PATH."
