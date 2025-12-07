#!/bin/bash

set -e

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
    # Windows (MSYS/Git Bash): match what you observed
    NVIM_CONFIG_DIR="$HOME/AppData/Local/nvim"
    NVIM_DATA_DIR="$HOME/AppData/Local/nvim-data"
else
    # Linux/Unix default
    NVIM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
    NVIM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
fi

echo "Neovim config dir: $NVIM_CONFIG_DIR"
echo "Neovim data dir:   $NVIM_DATA_DIR"

###############################################################################
# Install Node.js + npm on MSYS2 (for language servers)
###############################################################################

install_node_for_msys2() {
    echo "=== Installing Node.js (and npm) via MSYS2 pacman ==="
    echo "MSYSTEM=${MSYSTEM:-<empty>}"

    if ! command -v pacman >/dev/null 2>&1; then
        echo "'pacman' not found. This function is intended for MSYS2."
        return 1
    fi

    # Detect architecture (x86_64 vs aarch64)
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
            # Running from plain MSYS shell.
            # Prefer UCRT64 on x86_64, CLANGARM64 on aarch64.
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
            echo "Unrecognised MSYSTEM='${MSYSTEM}'. Trying UCRT64/CLANG64-style Node."
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

# Only run this on MSYS2 / Git Bash
if [[ "$UNAME_STR" == *"mingw"* ]] || [[ "$UNAME_STR" == *"msys"* ]]; then
    install_node_for_msys2
fi

###############################################################################
# Helper functions
###############################################################################

create_file() {
    local file="$1"
    if ! echo "" >"$file"; then
        echo "Failed to create file \"$file\"."
        return 1
    else
        echo "File \"$file\" created successfully."
    fi
}

delete_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        if ! rm "$file"; then
            echo "Failed to remove file \"$file\"."
            return 1
        fi
    fi
}

create_directory() {
    local directory="$1"
    if ! mkdir -p "$directory"; then
        echo "Failed to create directory \"$directory\"."
        return 1
    else
        echo "Directory \"$directory\" created successfully."
    fi
}

delete_directory() {
    local directory="$1"
    if [[ -d "$directory" ]]; then
        if ! yes | rm -r "$directory"; then
            echo "Failed to remove directory \"$directory\"."
            return 1
        fi
    fi
}

create_fresh_file() {
    local file="$1"
    delete_file "$file"
    create_file "$file"
}

create_fresh_directory() {
    local directory="$1"
    delete_directory "$directory"
    create_directory "$directory"
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

packer_sync() {
    "$NVIM_CMD" --headless \
        -c "autocmd User PackerComplete quitall" \
        -c "PackerSync"
}

call_lua_function() {
    local lua_function="$1"
    "$NVIM_CMD" --headless -c "lua $lua_function()" -c "quitall"
}

to_nvim_path() {
    local p="$1"
    # On MSYS2 / Git Bash, convert /c/... to C:/...
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$p"
    else
        printf '%s\n' "$p"
    fi
}

nvim_source_lua_file() {
    local filepath="$1"
    local nvim_path
    nvim_path=$(to_nvim_path "$filepath")
    "$NVIM_CMD" --headless -c "luafile $nvim_path" +qa
}

###############################################################################
# Create config directories and base files
###############################################################################

LUA_DIRECTORY="$NVIM_CONFIG_DIR/lua"

SUB_LUA_DIR_NAME="a_sub_directory"
LUA_SUB_DIRECTORY="$LUA_DIRECTORY/$SUB_LUA_DIR_NAME"

AFTER_PLUGIN_DIRECTORY="$NVIM_CONFIG_DIR/after/plugin"

for d in "$NVIM_CONFIG_DIR" "$LUA_DIRECTORY" "$LUA_SUB_DIRECTORY" \
    "$AFTER_PLUGIN_DIRECTORY"; do
    create_fresh_directory "$d"
done

BASE_LUA_FILEPATH="$NVIM_CONFIG_DIR/init.lua"
SUB_LUA_FILEPATH="$LUA_SUB_DIRECTORY/init.lua"
REMAP_FILEPATH="$LUA_SUB_DIRECTORY/remap.lua"
PACKER_FILEPATH="$LUA_SUB_DIRECTORY/packer.lua"
SET_FILEPATH="$LUA_SUB_DIRECTORY/set.lua"

TELESCOPE_FILEPATH="$AFTER_PLUGIN_DIRECTORY/telescope.lua"
HARPOON_FILEPATH="$AFTER_PLUGIN_DIRECTORY/harpoon.lua"
UNDOTREE_FILEPATH="$AFTER_PLUGIN_DIRECTORY/undotree.lua"
FUGITIVE_FILEPATH="$AFTER_PLUGIN_DIRECTORY/fugitive.lua"
LSP_FILEPATH="$AFTER_PLUGIN_DIRECTORY/lsp.lua"

for f in "$BASE_LUA_FILEPATH" "$SUB_LUA_FILEPATH" "$REMAP_FILEPATH" \
    "$PACKER_FILEPATH" "$TELESCOPE_FILEPATH" "$HARPOON_FILEPATH" \
    "$UNDOTREE_FILEPATH" "$LSP_FILEPATH" "$SET_FILEPATH"; do
    create_fresh_file "$f"
done

# init.lua: load our Lua subdir and its modules
add_to_file "$BASE_LUA_FILEPATH" "require(\"$SUB_LUA_DIR_NAME\")"
add_to_file "$BASE_LUA_FILEPATH" "require(\"$SUB_LUA_DIR_NAME.remap\")"
add_to_file "$BASE_LUA_FILEPATH" "require(\"$SUB_LUA_DIR_NAME.packer\")"

# subdir init.lua: load remap + set
add_to_file "$SUB_LUA_FILEPATH" "require(\"$SUB_LUA_DIR_NAME.remap\")"
add_to_file "$SUB_LUA_FILEPATH" "require(\"$SUB_LUA_DIR_NAME.set\")"

###############################################################################
# Remaps
###############################################################################

echo "Remaps"

CONTENT="
vim.g.mapleader = ' '
vim.keymap.set('n', '<leader>pv', ':Ex<CR>')

vim.keymap.set('v', 'J', ':m \'>+1<CR>gv=gv')
vim.keymap.set('v', 'K', ':m \'<-2<CR>gv=gv')

vim.keymap.set('n', 'J', 'mzJ\`z')

vim.keymap.set('n', '<C-d>', '<C-d>zz')
vim.keymap.set('n', '<C-u>', '<C-u>zz')

vim.keymap.set('n', 'n', 'nzzzv')
vim.keymap.set('n', 'N', 'Nzzzv')

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

echo "Remaps End"

###############################################################################
# Packer install: use Neovim's data dir, as a *start* plugin
###############################################################################

echo "Packer install"

PACKER_DIR="$NVIM_DATA_DIR/site/pack/packer/start/packer.nvim"

if [[ -d "$PACKER_DIR" ]]; then
    yes | rm -r "$PACKER_DIR"
fi
mkdir -p "$PACKER_DIR"

git clone --depth 1 https://github.com/wbthomason/packer.nvim "$PACKER_DIR"

CONTENT="
    local packer = require('packer')

    return packer.startup(function(use)

        use('wbthomason/packer.nvim')

        use({
            'nvim-telescope/telescope.nvim',
            tag = '0.1.8',
            requires = {
                { 'nvim-lua/plenary.nvim' }
            },
        })

        use({
            'rose-pine/neovim',
            as = 'rose-pine',
            config = function()
                vim.cmd('colorscheme rose-pine')
            end,
        })

        use({ 'nvim-treesitter/nvim-treesitter' })
        use('nvim-treesitter/playground')
        use('theprimeagen/harpoon')
        use('mbbill/undotree')
        use('tpope/vim-fugitive')

        use({ 'williamboman/mason.nvim', tag = 'v1.8.1' })
        use({
            'williamboman/mason-lspconfig.nvim',
            branch = 'v1.x',
            requires = {
                'williamboman/mason.nvim',
            },
        })

        use({ 'neovim/nvim-lspconfig', tag = 'v0.1.7' })

        use({
            'VonHeikemen/lsp-zero.nvim',
            branch = 'v1.x',
            requires = {
                { 'hrsh7th/nvim-cmp' },
                { 'hrsh7th/cmp-nvim-lsp' },
                { 'hrsh7th/cmp-buffer' },
                { 'hrsh7th/cmp-path' },
                { 'saadparwaiz1/cmp_luasnip' },
                { 'hrsh7th/cmp-nvim-lua' },
                { 'L3MON4D3/LuaSnip' },
                { 'rafamadriz/friendly-snippets' },
            },
        })

    end)
"
add_to_file "$PACKER_FILEPATH" "$CONTENT"

# Install / sync plugins
packer_sync

echo "Packer install end"

###############################################################################
# Telescope config
###############################################################################

echo "telescope config"

CONTENT="
    local builtin = require('telescope.builtin')
    vim.keymap.set(
        'n',
        '<leader>pf',
        builtin.find_files,
        { desc = 'Telescope find files' }
    )
    vim.keymap.set(
        'n',
        '<C-p>',
        builtin.git_files,
        {}
    )
    vim.keymap.set(
        'n',
        '<leader>ps',
        function()
            builtin.grep_string({
                search = vim.fn.input('Grep > '),
                cwd = vim.loop.cwd(),
            })
        end
    )
    vim.keymap.set('n', '<leader>pw', function()
        builtin.live_grep({
            cwd = vim.loop.cwd(),
        })
    end, { desc = 'Live grep from current files dir' })
"
add_to_file "$TELESCOPE_FILEPATH" "$CONTENT"

echo "telescope config end"

###############################################################################
# Colour config
###############################################################################

echo "colour config"

COLOURS_LUA_FILEPATH="$AFTER_PLUGIN_DIRECTORY/colours.lua"
create_fresh_file "$COLOURS_LUA_FILEPATH"

CONTENT="
    function ColourMyPencils(colour)
        colour = colour or 'rose-pine'
        vim.cmd.colorscheme(colour)

        vim.api.nvim_set_hl(0, 'Normal', { bg = 'NONE' })
        vim.api.nvim_set_hl(0, 'NormalFloat', { bg = 'NONE' })
    end

    vim.api.nvim_create_autocmd('ColorScheme', {
        pattern = '*',
        callback = function()
            vim.api.nvim_set_hl(0, 'Normal', { bg = 'NONE' })
            vim.api.nvim_set_hl(0, 'NormalFloat', { bg = 'NONE' })
        end,
    })

    ColourMyPencils()
"
add_to_file "$COLOURS_LUA_FILEPATH" "$CONTENT"

echo "Colour config end"

###############################################################################
# Treesitter config
###############################################################################

echo "treesitter config"

TREESITTER_LUA_FILEPATH="$AFTER_PLUGIN_DIRECTORY/treesitter.lua"
create_fresh_file "$TREESITTER_LUA_FILEPATH"

LANG_FILE="./treesitter_language_flags.ini"
lua_content="local language_flags = {
"
if [[ -f "$LANG_FILE" ]]; then
    while IFS='=' read -r key value; do
        lua_content+="    $key = $value,
    "
    done <"$LANG_FILE"
fi
lua_content+="}
"

CONTENT="
    $lua_content

    local ensure_list = {}

    for lang, enabled in pairs(language_flags) do
        if enabled then
            table.insert(ensure_list, lang)
        end
    end

    require('nvim-treesitter.configs').setup {
        ensure_installed = ensure_list,
        sync_install = false,
        auto_install = true,
        highlight = {
            enable = true,
        },
    }
"
add_to_file "$TREESITTER_LUA_FILEPATH" "$CONTENT"

echo "treesitter config end"

###############################################################################
# Harpoon config
###############################################################################

echo "harpoon config"

CONTENT="
    local mark = require('harpoon.mark')
    local ui = require('harpoon.ui')

    vim.keymap.set('n', '<leader>a', mark.add_file)
    vim.keymap.set('n', '<C-e>', ui.toggle_quick_menu)

    vim.keymap.set('n', '<C-h>', function() ui.nav_file(1) end)
    vim.keymap.set('n', '<C-t>', function() ui.nav_file(2) end)
    vim.keymap.set('n', '<C-n>', function() ui.nav_file(3) end)
    vim.keymap.set('n', '<C-s>', function() ui.nav_file(4) end)
"
add_to_file "$HARPOON_FILEPATH" "$CONTENT"

echo "harpoon config end"

###############################################################################
# Undotree config
###############################################################################

echo "undotree config"

CONTENT="
    vim.keymap.set('n', '<leader>u', vim.cmd.UndotreeToggle)
"
add_to_file "$UNDOTREE_FILEPATH" "$CONTENT"

echo "undotreeconfig end"

###############################################################################
# Fugitive config
###############################################################################

echo "Fugitive config"

CONTENT="
    vim.keymap.set('n', '<leader>gs', vim.cmd.Git)
"
add_to_file "$FUGITIVE_FILEPATH" "$CONTENT"

echo "Fugitive config end"

###############################################################################
# LSP config
###############################################################################

echo "LSP config"

CONTENT="
    local lsp = require('lsp-zero')

    lsp.preset('recommended')

    require('mason').setup()

    require('mason-lspconfig').setup {
        ensure_installed = {
            'lua_ls',
            'rust_analyzer',
            'pyright',
        },
    }

    lsp.ensure_installed({
        'lua_ls',
        'rust_analyzer',
        'pyright',
    })

    local cmp = require('cmp')
    local cmp_select = { behavior = cmp.SelectBehavior.Select }
    local cmp_mappings = lsp.defaults.cmp_mappings({
        ['<C-p>'] = cmp.mapping.select_prev_item(cmp_select),
        ['<C-n>'] = cmp.mapping.select_next_item(cmp_select),
        ['<C-y>'] = cmp.mapping.confirm({ select = true }),
        ['<C-Space>'] = cmp.mapping.complete(),
    })

    cmp.setup({
        mapping = cmp_mappings,
        sources = {
            { name = 'nvim_lsp' },
            { name = 'buffer' },
        },
    })

    lsp.set_preferences({
        sign_icons = {},
    })

    lsp.on_attach(function(client, bufnr)
        local opts = { buffer = bufnr, remap = false }

        vim.keymap.set('n', 'gd', function() vim.lsp.buf.definition() end, opts)
        vim.keymap.set('n', 'K', function() vim.lsp.buf.hover() end, opts)
        vim.keymap.set('n', '<leader>vws', function() vim.lsp.buf.workspace_symbol() end, opts)
        vim.keymap.set('n', '<leader>vd', function() vim.diagnostic.open_float() end, opts)
        vim.keymap.set('n', '[d', function() vim.diagnostic.goto_next() end, opts)
        vim.keymap.set('n', ']d', function() vim.diagnostic.goto_prev() end, opts)
        vim.keymap.set('n', '<leader>vca', function() vim.lsp.buf.code_action() end, opts)
        vim.keymap.set('n', '<leader>vrr', function() vim.lsp.buf.references() end, opts)
        vim.keymap.set('n', '<leader>vrn', function() vim.lsp.buf.rename() end, opts)
    end)

    lsp.setup()
"
add_to_file "$LSP_FILEPATH" "$CONTENT"

echo "LSP config end"

###############################################################################
# Options
###############################################################################

echo "options"

CONTENT="
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
    vim.opt.undodir = os.getenv('HOME') .. '/.vim/undodir'
    vim.opt.undofile = true

    vim.opt.hlsearch = false
    vim.opt.incsearch = true

    vim.opt.termguicolors = true

    vim.opt.scrolloff = 8
    vim.opt.signcolumn = 'yes'
    vim.opt.isfname:append('@-@')

    vim.opt.updatetime = 50

    vim.opt.colorcolumn = '80'

    vim.g.mapleader = ' '
"
add_to_file "$SET_FILEPATH" "$CONTENT"

echo "options end"
