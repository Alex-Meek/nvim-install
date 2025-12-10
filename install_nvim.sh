#!/bin/bash
#
# This script performs a full, clean installation of Neovim and a custom configuration.
# Uses the neovim-releases repository and installs dependencies locally without sudo.

# Exit on any error, on unset variables, and if any command in a pipeline fails.
set -euo pipefail

# --- Configuration ---
REPO_URL="https://github.com/arturgoms/nvim"
LOCAL_INSTALL_DIR="$HOME/.local"
BIN_DIR="$LOCAL_INSTALL_DIR/bin"
NVIM_CMD="$BIN_DIR/nvim"
NVIM_VERSION="v0.11.5"
NODE_VERSION="v20.18.3"
FZF_VERSION="0.67.0"
RG_VERSION="15.1.0"

###############################################################################
# Define OS-specific paths for Neovim config and data
###############################################################################

UNAME_STR=$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')
if [[ "$UNAME_STR" == *"mingw"* ]] || [[ "$UNAME_STR" == *"msys"* ]]; then
    NVIM_CONFIG_DIR="$HOME/AppData/Local/nvim"
    NVIM_DATA_DIR="$HOME/AppData/Local/nvim-data"
    NVIM_STATE_DIR="$HOME/AppData/Local/nvim-data"
else
    NVIM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
    NVIM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
    NVIM_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nvim"
fi

###############################################################################
# Cleanup Function
###############################################################################

perform_full_cleanup() {
    echo "--- PERFORMING FULL CLEANUP ---"
    echo "WARNING: This will permanently delete existing Neovim configs and local installations."
    echo "This includes: $NVIM_CONFIG_DIR, $NVIM_DATA_DIR, and any nvim install in $LOCAL_INSTALL_DIR"
    echo "Continuing in 3 seconds... (Press Ctrl+C to cancel)"
    sleep 3

    rm -rf "$NVIM_CONFIG_DIR" "$NVIM_DATA_DIR" "$NVIM_STATE_DIR" \
           "$LOCAL_INSTALL_DIR/nvim-linux-x86_64" "$LOCAL_INSTALL_DIR/nvim-linux-arm64" \
           "$LOCAL_INSTALL_DIR/nvim-win64" "$LOCAL_INSTALL_DIR/nvim" "$LOCAL_INSTALL_DIR/squashfs-root"
    rm -f "$BIN_DIR/nvim"

    echo "Cleanup complete."
    echo "---------------------------"
}

###############################################################################
# Helper function for PATH
###############################################################################

ensure_local_bin_on_path() {
    mkdir -p "$BIN_DIR"
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "!!! WARNING: Your PATH does not seem to include $BIN_DIR"
        echo "!!! Please add the following line to your shell profile (e.g., ~/.bashrc):"
        echo "!!!   export PATH=\"$BIN_DIR:\$PATH\""
        echo "!!! You must source the file or open a new terminal for this to take effect."
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        export PATH="$BIN_DIR:$PATH"
    fi
}

###############################################################################
# Install Node.js locally
###############################################################################

install_nodejs() {
    if command -v node &>/dev/null && command -v npm &>/dev/null; then
        echo "Node.js is already installed: $(node --version)"
        return
    fi

    echo "Installing Node.js ${NODE_VERSION} locally..."
    
    local arch
    arch=$(uname -m)
    
    local node_arch
    if [[ "$arch" == "x86_64" ]]; then
        node_arch="x64"
    elif [[ "$arch" == "aarch64" ]] || [[ "$arch" == "arm64" ]]; then
        node_arch="arm64"
    else
        echo "Unsupported architecture for Node.js: $arch" && exit 1
    fi
    
    local node_file="node-${NODE_VERSION}-linux-${node_arch}.tar.xz"
    local node_url="https://nodejs.org/dist/${NODE_VERSION}/${node_file}"
    local temp_file
    temp_file=$(mktemp --suffix=.tar.xz)
    trap 'rm -f "$temp_file"' EXIT
    
    echo "Downloading Node.js from $node_url..."
    if ! curl -fL -o "$temp_file" "$node_url"; then
        echo "Failed to download Node.js" && exit 1
    fi
    
    echo "Extracting Node.js..."
    tar -xJf "$temp_file" -C "$LOCAL_INSTALL_DIR" --strip-components=1
    
    rm -f "$temp_file"
    trap - EXIT
    
    echo "Node.js installed: $(node --version)"
    echo "npm installed: $(npm --version)"
}

###############################################################################
# Install fzf locally
###############################################################################

install_fzf() {
    if command -v fzf &>/dev/null; then
        echo "fzf is already installed: $(fzf --version)"
        return
    fi

    echo "Installing fzf locally..."
    
    local arch
    arch=$(uname -m)
    
    local fzf_arch
    if [[ "$arch" == "x86_64" ]]; then
        fzf_arch="amd64"
    elif [[ "$arch" == "aarch64" ]] || [[ "$arch" == "arm64" ]]; then
        fzf_arch="arm64"
    else
        echo "Unsupported architecture for fzf: $arch" && exit 1
    fi
    
    local fzf_file="fzf-${FZF_VERSION}-linux_${fzf_arch}.tar.gz"
    local fzf_url="https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/${fzf_file}"
    local temp_file
    temp_file=$(mktemp --suffix=.tar.gz)
    trap 'rm -f "$temp_file"' EXIT
    
    echo "Downloading fzf from $fzf_url..."
    if ! curl -fL -o "$temp_file" "$fzf_url"; then
        echo "Failed to download fzf" && exit 1
    fi
    
    echo "Extracting fzf..."
    tar -xzf "$temp_file" -C "$BIN_DIR"
    chmod +x "$BIN_DIR/fzf"
    
    rm -f "$temp_file"
    trap - EXIT
    
    echo "fzf installed: $(fzf --version)"
}

###############################################################################
# Install ripgrep locally
###############################################################################

install_ripgrep() {
    if command -v rg &>/dev/null; then
        echo "ripgrep is already installed: $(rg --version | head -n 1)"
        return
    fi

    echo "Installing ripgrep locally..."
    
    local rg_file
    local is_zip=false
    
    if [[ "$UNAME_STR" == *"mingw"* ]] || [[ "$UNAME_STR" == *"msys"* ]]; then
        # Windows/MSYS2
        local arch
        arch=$(uname -m)
        
        if [[ "$arch" == "x86_64" ]]; then
            rg_file="ripgrep-${RG_VERSION}-x86_64-pc-windows-msvc.zip"
        elif [[ "$arch" == "i686" ]] || [[ "$arch" == "i386" ]]; then
            rg_file="ripgrep-${RG_VERSION}-i686-pc-windows-msvc.zip"
        elif [[ "$arch" == "aarch64" ]] || [[ "$arch" == "arm64" ]]; then
            rg_file="ripgrep-${RG_VERSION}-aarch64-pc-windows-msvc.zip"
        else
            echo "Unsupported architecture for ripgrep on Windows: $arch" && exit 1
        fi
        is_zip=true
    else
        # Linux
        local arch
        arch=$(uname -m)
        
        if [[ "$arch" == "x86_64" ]]; then
            rg_file="ripgrep-${RG_VERSION}-x86_64-unknown-linux-musl.tar.gz"
        elif [[ "$arch" == "aarch64" ]] || [[ "$arch" == "arm64" ]]; then
            rg_file="ripgrep-${RG_VERSION}-aarch64-unknown-linux-gnu.tar.gz"
        elif [[ "$arch" == "i686" ]] || [[ "$arch" == "i386" ]]; then
            rg_file="ripgrep-${RG_VERSION}-i686-unknown-linux-gnu.tar.gz"
        else
            echo "Unsupported architecture for ripgrep: $arch" && exit 1
        fi
    fi
    
    local rg_url="https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/${rg_file}"
    local temp_file
    
    if [[ "$is_zip" == true ]]; then
        temp_file=$(mktemp --suffix=.zip)
    else
        temp_file=$(mktemp --suffix=.tar.gz)
    fi
    
    trap 'rm -f "$temp_file"' EXIT
    
    echo "Downloading ripgrep from $rg_url..."
    if ! curl -fL -o "$temp_file" "$rg_url"; then
        echo "Failed to download ripgrep" && exit 1
    fi
    
    echo "Extracting ripgrep..."
    local temp_dir
    temp_dir=$(mktemp -d)
    
    if [[ "$is_zip" == true ]]; then
        unzip -q "$temp_file" -d "$temp_dir"
    else
        tar -xzf "$temp_file" -C "$temp_dir"
    fi
    
    # Find and copy the rg binary
    find "$temp_dir" -name "rg" -o -name "rg.exe" | while read -r rg_path; do
        if [[ -f "$rg_path" ]]; then
            cp "$rg_path" "$BIN_DIR/"
            chmod +x "$BIN_DIR/$(basename "$rg_path")"
            break
        fi
    done
    
    rm -rf "$temp_file" "$temp_dir"
    trap - EXIT
    
    echo "ripgrep installed: $(rg --version | head -n 1)"
}

###############################################################################
# Install Neovim Application
###############################################################################

install_neovim() {
    echo "Proceeding with Neovim application installation..."
    
    if [[ "$UNAME_STR" == "linux" ]]; then
        local arch
        arch=$(uname -m)
        
        local archive_name
        local extracted_dir
        if [[ "$arch" == "x86_64" ]]; then
            archive_name="nvim-linux-x86_64.tar.gz"
            extracted_dir="nvim-linux-x86_64"
        elif [[ "$arch" == "aarch64" ]] || [[ "$arch" == "arm64" ]]; then
            archive_name="nvim-linux-arm64.tar.gz"
            extracted_dir="nvim-linux-arm64"
        else
            echo "Unsupported architecture: $arch" && exit 1
        fi
        
        local download_url="https://github.com/neovim/neovim-releases/releases/download/${NVIM_VERSION}/${archive_name}"
        echo "Downloading Neovim from neovim-releases: $download_url..."
        
        local temp_archive
        temp_archive=$(mktemp --suffix=.tar.gz)
        trap 'rm -f "$temp_archive"' EXIT

        if ! curl -fL -o "$temp_archive" "$download_url"; then
            echo "Failed to download Neovim tarball." && exit 1
        fi

        echo "Extracting to $LOCAL_INSTALL_DIR..."
        tar -xzf "$temp_archive" -C "$LOCAL_INSTALL_DIR"
        
        echo "Creating symbolic link..."
        ln -sf "$LOCAL_INSTALL_DIR/$extracted_dir/bin/nvim" "$NVIM_CMD"
        
        rm -f "$temp_archive"
        trap - EXIT

    elif [[ "$UNAME_STR" == *"mingw"* ]] || [[ "$UNAME_STR" == *"msys"* ]]; then
        local archive_name="nvim-win64.zip"
        local download_url="https://github.com/neovim/neovim/releases/latest/download/${archive_name}"
        
        echo "Downloading Neovim for Windows from $download_url..."
        local temp_archive
        temp_archive=$(mktemp -p "" "${archive_name}.XXXXXX")
        trap 'rm -f "$temp_archive"' EXIT

        if ! curl -fL -o "$temp_archive" "$download_url"; then
            echo "Failed to download Neovim for Windows." && exit 1
        fi

        echo "Extracting..."
        unzip -q "$temp_archive" -d "$LOCAL_INSTALL_DIR"
        
        echo "Creating symbolic link..."
        ln -sf "$LOCAL_INSTALL_DIR/nvim-win64/bin/nvim" "$NVIM_CMD"
        
        rm -f "$temp_archive"
        trap - EXIT
    else
        echo "Unsupported OS: $UNAME_STR. Please install Neovim manually." && exit 1
    fi

    echo "Neovim application installation complete."
}

# --- Main Script Execution Starts Here ---

perform_full_cleanup
ensure_local_bin_on_path

# Install dependencies locally
echo "=== Installing dependencies locally ==="
install_nodejs
install_fzf
install_ripgrep

# Check for git and curl (required, no alternatives)
for cmd in git curl; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is required but not installed."
        echo "Please ask your system administrator to install $cmd"
        exit 1
    fi
done

install_neovim

if ! "$NVIM_CMD" --version >/dev/null 2>&1; then
    echo "Neovim installation failed. Command not found or not executable at: $NVIM_CMD" && exit 1
fi

echo "Using Neovim: $($NVIM_CMD --version | head -n 1)"
echo "Neovim config dir: $NVIM_CONFIG_DIR"

###############################################################################
# Helper Functions for Configuration
###############################################################################

create_directory() { mkdir -p "$1" && echo "Directory \"$1\" created."; }
create_file() { >"$1" && echo "File \"$1\" created."; }
add_to_file() {
    cat >>"$1" <<EOF
$2
EOF
}

###############################################################################
# Clone and Configure Neovim
###############################################################################

echo "Cloning Neovim config from $REPO_URL into $NVIM_CONFIG_DIR"
mkdir -p "$NVIM_CONFIG_DIR"
git clone --depth 1 "$REPO_URL" "$NVIM_CONFIG_DIR"

INIT_LUA="$NVIM_CONFIG_DIR/init.lua"
tmp_file=$(mktemp)
trap 'rm -f "$tmp_file"' EXIT

# Force sessionoptions
{
    echo 'vim.o.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"'
    awk 'NR>1 && $0 !~ /sessionoptions/' "$INIT_LUA"
} >"$tmp_file" && mv "$tmp_file" "$INIT_LUA"

# Disable upstream lsp.lsp-setup
tmp_file=$(mktemp)
awk '/require.*lsp\.lsp-setup/ {$0="-- "$0} 1' "$INIT_LUA" >"$tmp_file" && mv "$tmp_file" "$INIT_LUA"

# Disable auto-session plugin
for f in $(grep -rl 'rmagatti/auto-session' "$NVIM_CONFIG_DIR/lua" 2>/dev/null || true); do
    echo "Disabling auto-session in $f"
    tmp_file=$(mktemp)
    awk '1; /"rmagatti\/auto-session"/ {print "    enabled = false,"}' "$f" >"$tmp_file" && mv "$tmp_file" "$f"
done

# Patch lazy-plugins.lua to add extra plugins
LAZY_PLUGINS_FILE="$NVIM_CONFIG_DIR/lua/lazy-plugins.lua"
if ! grep -q 'shaunsingh/moonlight.nvim' "$LAZY_PLUGINS_FILE" 2>/dev/null; then
    tmp_file=$(mktemp)
    awk '
      /require .custom.plugins.debug/ && !done {
        print
        print "    {\"shaunsingh/moonlight.nvim\", lazy = false, priority = 1000, config = function() vim.g.moonlight_italic_comments = true; vim.g.moonlight_italic_keywords = true; vim.g.moonlight_italic_functions = true; vim.g.moonlight_contrast = true; require(\"moonlight\").set() end,},"
        print "    { \"nvim-neotest/nvim-nio\" }, { \"theprimeagen/harpoon\" }, { \"mbbill/undotree\" },"
        print "    { \"tpope/vim-fugitive\" }, { \"hrsh7th/nvim-cmp\" }, { \"hrsh7th/cmp-nvim-lsp\" },"
        print "    { \"hrsh7th/cmp-buffer\" }, { \"hrsh7th/cmp-path\" }, { \"saadparwaiz1/cmp_luasnip\" },"
        print "    { \"hrsh7th/cmp-nvim-lua\" }, { \"L3MON4D3/LuaSnip\" }, { \"rafamadriz/friendly-snippets\" },"
        done=1
      }
      { print }
    ' "$LAZY_PLUGINS_FILE" >"$tmp_file" && mv "$tmp_file" "$LAZY_PLUGINS_FILE"
fi

# Create custom override files for remaps and LSP
A_SUB_DIR="$NVIM_CONFIG_DIR/lua/a_sub_directory"
create_directory "$A_SUB_DIR"
REMAP_FILEPATH="$A_SUB_DIR/remap.lua"
LSP_CUSTOM_FILE="$A_SUB_DIR/lsp.lua"
create_file "$REMAP_FILEPATH"
create_file "$LSP_CUSTOM_FILE"

# Add custom remaps
add_to_file "$REMAP_FILEPATH" 'vim.g.mapleader = " "
vim.keymap.set("n", "<leader>pv", ":Ex<CR>")
vim.keymap.set("v", "J", ":m '\''>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '\''<-2<CR>gv=gv")
vim.keymap.set("n", "J", "mzJ`z")
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")
vim.keymap.set("x", "<leader>p", "\"_dP")
vim.keymap.set({"n", "v"}, "<leader>y", "\"+y")
vim.keymap.set("n", "<leader>Y", "\"+Y")
vim.keymap.set({"n", "v"}, "<leader>d", "\"_d")
vim.keymap.set("n", "Q", "<nop>")
vim.keymap.set("n", "<leader>s", [[:%s/\\<<C-r><C-w>\\>/<C-r><C-w>/gI<Left><Left><Left>]])
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })
'

# Add custom LSP setup
add_to_file "$LSP_CUSTOM_FILE" '
local capabilities = require("cmp_nvim_lsp").default_capabilities()
local on_attach = function(client, bufnr)
  local nmap = function(keys, func, desc)
    if desc then desc = "LSP: " .. desc end
    vim.keymap.set("n", keys, func, { buffer = bufnr, desc = desc })
  end
  nmap("gd", vim.lsp.buf.definition, "Goto Definition")
  nmap("K", vim.lsp.buf.hover, "Hover")
  nmap("<leader>vca", vim.lsp.buf.code_action, "Code Action")
  nmap("<leader>vrn", vim.lsp.buf.rename, "Rename")
  nmap("[d", vim.diagnostic.goto_prev, "Prev Diagnostic")
  nmap("]d", vim.diagnostic.goto_next, "Next Diagnostic")
end

local servers = { "lua_ls", "pyright", "rust_analyzer", "elixirls" }
for _, server in ipairs(servers) do
  vim.lsp.config[server] = vim.tbl_deep_extend("force", vim.lsp.config[server] or {}, {
    capabilities = capabilities,
    on_attach = on_attach
  })
end

require("mason").setup()
require("mason-lspconfig").setup { ensure_installed = servers }
'

# Ensure our overrides are required last from init.lua
add_to_file "$INIT_LUA" "
-- Load personal overrides last
require('a_sub_directory.remap')
require('a_sub_directory.lsp')
"

# Pre-install plugins via lazy.nvim
echo "Running Lazy! sync to install plugins..."
"$NVIM_CMD" --headless "+Lazy! sync" +qa

trap - EXIT
echo "Done. A fresh Neovim environment and custom configuration have been installed."
echo "Node.js version: $(node --version)"
echo "npm version: $(npm --version)"
echo "fzf version: $(fzf --version)"
echo "ripgrep version: $(rg --version | head -n 1)"
