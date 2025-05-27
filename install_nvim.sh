#!/bin/bash

# To Do

# - [ ] Why is this better than just following the tutorial
    # 1. Using on multiple systems e.g. remote servers. (need to make this script robust, i.e. if curl is missing etc.)
# - [ ] Make it easer to change the configuration, e.g. the colorscheme.
# - [ ] Make sure each line is necessary, and we don't have a tonne of duplicate code 
# - [ ] Make sure the sections/layout makes sense.
# - [ ] If things should be in separate config files, move them there. 

# - [ ] .env file if it becomes necessary 

# - [ ] Add better lsp list for toggling 

# Status - working, but still more plugins to install and remaps to configure. 

# Stop script if any non-zero exit code is encountered.
set -e

create_file () {
    local file="$1"
    if ! echo "" > $file; then
        echo "Failed to create file \"$file\"."
        return 1
    else
        echo "File \"$file\" created successfully."
    fi
    return 0
}

delete_file () {
    local file="$1"
    if [[ -f "$file" ]]; then
        if rm $file; then
            echo "Failed to remove file \"$file\"."
            return 1
        fi
    fi
}

create_directory () {
    local directory="$1"
    if ! mkdir -p $directory; then
        echo "Failed to create directory \"$directory\"."
        return 1
    else
        echo "Directory \"$directory\" created successfully."
    fi
    return 0
}

delete_directory () {
    local directory="$1"
    if [[ -d $directory ]]; then
        if ! yes | rm -r $directory; then
            echo "Failed to remove directory \"$directory\"."
            return 1
        fi
    fi
}

create_fresh_file () {
    local file="$1"
    delete_file $file
    create_file $file
    return 0
}

create_fresh_directory () {
    local directory="$1"
    delete_directory $directory
    create_directory $directory
    return 0
}

add_to_file () {
    local file="$1"
    local edits="$2"

    if ! { cat >> "$file" <<EOF
$edits
EOF
    }; then
        echo "Failed to append to file \"$file\"."
        return 1
    fi

    return 0
}

packer_sync () {
    nvim --headless -c "autocmd User PackerComplete quitall" -c "PackerSync"
}

call_lua_function () {
    local lua_function="$1"
    nvim --headless -c "lua $lua_function()" -c "quitall"
}

nvim_source_lua_file () {
    local filepath="$1"
    nvim --headless -c "luafile $filepath" +qa
}

###############################################################################
############################### Install Neovim ################################
###############################################################################

# Install NeoVim

# export PATH="$HOME/.local/bin:$PATH"

# INSTALL_DIR="$HOME/.local"
# BIN_DIR="$INSTALL_DIR/bin"
# APPIMAGE_NAME="nvim.appimage"

# mkdir -p "$BIN_DIR"

# echo "Fetching latest Neovim AppImage URL..."
# DOWNLOAD_URL=$(curl -s https://api.github.com/repos/neovim/neovim/releases/tags/v0.9.5 \
#     | grep browser_download_url \
#     | grep "$APPIMAGE_NAME\"" \
#     | cut -d '"' -f4)

# if [ -z "$DOWNLOAD_URL" ]; then
#     echo "❌ Failed to find the AppImage download URL."
#     exit 1
# fi

# echo "Downloading Neovim AppImage from $DOWNLOAD_URL ..."
# curl -LO "$DOWNLOAD_URL"

# echo "Making AppImage executable..."
# chmod u+x "$APPIMAGE_NAME"

# echo "Extracting AppImage..."
# ./"$APPIMAGE_NAME" --appimage-extract

# echo "Installing Neovim to $INSTALL_DIR..."
# rm -rf "$INSTALL_DIR/nvim"
# mv squashfs-root "$INSTALL_DIR/nvim"

# echo "Creating symlink in $BIN_DIR..."
# ln -sf "$INSTALL_DIR/nvim/usr/bin/nvim" "$BIN_DIR/nvim"

# echo "Cleaning up..."
# rm "$APPIMAGE_NAME"

# echo "✅ Neovim installed! Make sure $BIN_DIR is in your PATH."

# "$BIN_DIR/nvim" --version

###############################################################################
######################## Create files and directories #########################
###############################################################################
NVIM_CONFIG_DIR="$HOME/.config/nvim"
LUA_DIRECTORY="$NVIM_CONFIG_DIR/lua"

SUB_LUA_DIR_NAME="a_sub_directory"
LUA_SUB_DIRECTORY="$LUA_DIRECTORY/$SUB_LUA_DIR_NAME"

AFTER_PLUGIN_DIRECTORY="$NVIM_CONFIG_DIR/after/plugin"

for i in $NVIM_CONFIG_DIR $LUA_DIRECTORY $LUA_SUB_DIRECTORY $AFTER_PLUGIN_DIRECTORY
do 
    create_fresh_directory $i
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

for i in $BASE_LUA_FILEPATH $SUB_LUA_FILEPATH $REMAP_FILEPATH \
$PACKER_FILEPATH $AFTER_INIT_LUA_FILEPATH $TELESCOPE_FILEPATH $HARPOON_FILEPATH \
$UNDOTREE_FILEPATH $LSP_FILEPATH $SET_FILEPATH
do
    create_fresh_file $i
done

# change this filename idk why its called what it is
add_to_file $BASE_LUA_FILEPATH "require(\"$SUB_LUA_DIR_NAME\")"

# Format this
add_to_file $SUB_LUA_FILEPATH "require(\"a_sub_directory.remap\")"
add_to_file $SUB_LUA_FILEPATH "require(\"a_sub_directory.set\")"
###############################################################################
###############################################################################
###############################################################################

###############################################################################
################################### Remaps ####################################
###############################################################################
CONTENT="
vim.g.mapleader = ' '
vim.keymap.set('n', '<leader>pv', ':Ex<CR>')

-- Allow moving of highlighted text up and down, automatically indenting
-- where needed.
vim.keymap.set('v', 'J', ':m \'>+1<CR>gv=gv')
vim.keymap.set('v', 'K', ':m \'<-2<CR>gv=gv')

-- Using J to append line below to this line, keeps cursor at start of 
-- line.
vim.keymap.set('n', 'J', 'mzJ\`z')

-- Half-page jumping while keeping cursor in the middle of page rather
-- than moving to the bottom or top.
vim.keymap.set('n', '<C-d>', '<C-d>zz')
vim.keymap.set('n', '<C-u>', '<C-u>zz')

-- Search for string will focus the found string at the center of the 
-- page rather than near the top or bottom, simialr to above.
vim.keymap.set('n', 'n', 'nzzzv')
vim.keymap.set('n', 'N', 'Nzzzv')

-- Delete over current highlight (p) while preserving buffer string
-- instead of replacing the buffer string with the deleted string.
vim.keymap.set('x', '<leader>p', '\"_dP')

-- Yank into system clipboard
vim.keymap.set('n', '<leader>y', '\"+y')
vim.keymap.set('v', '<leader>y', '\"+y')
vim.keymap.set('n', '<leader>Y', '\"+y')

-- Delete to void (prevent overwrite of the buffer string)
vim.keymap.set('n', '<leader>d', '\"_d')
vim.keymap.set('v', '<leader>d', '\"_d')

-- Prevent the accidental use of Ex mode
vim.keymap.set('n', 'Q', '<nop>')

-- Quick fix navigation
vim.keymap.set('n', '<C-k>', '<cmd>cnext<CR>zz')
vim.keymap.set('n', '<C-j>', '<cmd>cprev<CR>zz')
vim.keymap.set('n', '<leader>k', '<cmd>lnext<CR>zz')
vim.keymap.set('n', '<leader>j', '<cmd>lprev<CR>zz')

-- Quick find and replace for the current word
vim.keymap.set('n', '<leader>s', [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]])
vim.keymap.set('n', '<leader>x', '<cmd>!chmod +x %<CR>', { silent = true })

"
add_to_file $REMAP_FILEPATH "$CONTENT"
add_to_file $BASE_LUA_FILEPATH "require('$SUB_LUA_DIR_NAME.remap')"
###############################################################################
###############################################################################
###############################################################################

###############################################################################
################################ Packer install ###############################
###############################################################################\
if [[ -d "$HOME/.local/share/nvim/site/pack/packer" ]]; then
    yes | rm -r "$HOME/.local/share/nvim/site/pack/packer"
fi
git clone --depth 1 https://github.com/wbthomason/packer.nvim \
    ~/.local/share/nvim/site/pack/packer/start/packer.nvim


CONTENT="
    vim.cmd [[packadd packer.nvim]]

    return require('packer').startup(function(use)

        use('wbthomason/packer.nvim')

        use ({
            'nvim-telescope/telescope.nvim', 
            tag = '0.1.8',
            requires = { 
                {'nvim-lua/plenary.nvim'} 
            }
        })

        use({
            'rose-pine/neovim',
            as = 'rose-pine',
            config = function ()
                vim.cmd('colorscheme rose-pine')
            end
        })

        use('nvim-treesitter/nvim-treesitter', {run = ':TSUpdate'})
        use('nvim-treesitter/playground')
        use('theprimeagen/harpoon')
        use('mbbill/undotree')
        use('tpope/vim-fugitive')

        use ({'neovim/nvim-lspconfig', tag = 'v0.1.7'})
        use ({'williamboman/mason.nvim', tag = 'v1.8.1',})
        use ({
            'williamboman/mason-lspconfig.nvim', 
            branch = 'v1.x',
            requires = {
                'williamboman/mason.nvim',
            },
        })


        use ({
            'VonHeikemen/lsp-zero.nvim',
            branch = 'v1.x',
            requires = {

                -- Autocompletion
                {'hrsh7th/nvim-cmp'},         -- Required
                {'hrsh7th/cmp-nvim-lsp'},     -- Required
                {'hrsh7th/cmp-buffer'},       -- Optional
                {'hrsh7th/cmp-path'},         -- Optional
                {'saadparwaiz1/cmp_luasnip'}, -- Optional
                {'hrsh7th/cmp-nvim-lua'},     -- Optional

                -- Snippets
                {'L3MON4D3/LuaSnip'},             -- Required
                {'rafamadriz/friendly-snippets'}, -- Optional
            }
        })

    end)
"

add_to_file $PACKER_FILEPATH "$CONTENT"
add_to_file $BASE_LUA_FILEPATH "require(\"$SUB_LUA_DIR_NAME.packer\")"

packer_sync
###############################################################################
###############################################################################
###############################################################################

###############################################################################
################################# Telescope Config ############################
###############################################################################
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
        builtin.git_files, { }
    )
    vim.keymap.set(
        'n', 
        '<leader>ps', 
        function() 
            builtin.grep_string({ 
                search = vim.fn.input(\"Grep > \") 
            });
        end
    )
"
add_to_file $TELESCOPE_FILEPATH "$CONTENT"
packer_sync # is this necessary?
###############################################################################
###############################################################################
###############################################################################

###############################################################################
################################# Colour Config ###############################
###############################################################################
COLOURS_LUA_FILEPATH="$AFTER_PLUGIN_DIRECTORY/colours.lua"

create_fresh_file $COLOURS_LUA_FILEPATH

CONTENT="
    function ColourMyPencils(colour)
        colour = colour or 'rose-pine'
        vim.cmd.colorscheme(colour)

        vim.api.nvim_set_hl(0, 'Normal', { bg='NONE' })
        vim.api.nvim_set_hl(0, 'NormalFloat', { bg='NONE' })

    end

    -- Ensure highlights are applied after the colorscheme loads
    vim.api.nvim_create_autocmd('ColorScheme', {
        pattern = '*',
        callback = function()
            vim.api.nvim_set_hl(0, 'Normal', { bg='NONE' })
            vim.api.nvim_set_hl(0, 'NormalFloat', { bg='NONE' })
        end
    })

    ColourMyPencils()
"
add_to_file $COLOURS_LUA_FILEPATH "$CONTENT"
packer_sync
call_lua_function "ColourMyPencils"
###############################################################################
###############################################################################
###############################################################################

###############################################################################
############################ Treesitter Config ################################
###############################################################################
TREESITTER_LUA_FILEPATH=$AFTER_PLUGIN_DIRECTORY/treesitter.lua
create_fresh_file $TREESITTER_LUA_FILEPATH

LANG_FILE="./treesitter_language_flags.ini"

lua_content="local language_flags = {
"
while IFS='=' read -r key value; do
    lua_content+="    $key = $value,
    "
done < "$LANG_FILE"
lua_content+="}"

CONTENT="
    $lua_content

    local ensure_list = {}

    for lang, enabled in pairs(language_flags) do
        if enabled then
            table.insert(ensure_list, lang)
        end
    end

    require'nvim-treesitter.configs'.setup {
    
        ensure_installed = ensure_list,

        sync_install = false,

        auto_install = true,

        highlight = {
            enable = true,
        },
    }
"

add_to_file $TREESITTER_LUA_FILEPATH "$CONTENT"
nvim_source_lua_file "$TREESITTER_LUA_FILEPATH"
###############################################################################
###############################################################################
###############################################################################

###############################################################################
############################# Harpoon Config ##################################
###############################################################################
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

add_to_file $HARPOON_FILEPATH "$CONTENT"
nvim_source_lua_file "$HARPOON_FILEPATH"
###############################################################################
###############################################################################
###############################################################################

###############################################################################
############################ Undotree Config ##################################
###############################################################################
CONTENT="
    vim.keymap.set('n', '<leader>u', vim.cmd.UndotreeToggle)
"

add_to_file $UNDOTREE_FILEPATH "$CONTENT"
nvim_source_lua_file "$UNDOTREE_FILEPATH"
###############################################################################
###############################################################################
###############################################################################

###############################################################################
############################ Fugitive Config ##################################
###############################################################################
CONTENT="
    vim.keymap.set(\"n\", \"<leader>gs\", vim.cmd.Git)
"
add_to_file $FUGITIVE_FILEPATH "$CONTENT"
nvim_source_lua_file "$FUGITIVE_FILEPATH"
###############################################################################
###############################################################################
###############################################################################

###############################################################################
################################# LSP Config ##################################
###############################################################################
CONTENT="
    local lsp = require('lsp-zero')

    lsp.preset('recommended')

    require('mason').setup()

    -- vtsls is used rather than 'tsserver'/'ts_ls' as there is a 
    -- name conflict betwen mason and nvim lsps that I don't have time to 
    -- resolve.  

    require('mason-lspconfig').setup {
    ensure_installed = { 
        'vtsls', 
        'eslint', 
        'lua_ls', 
        'rust_analyzer',
        'pylsp'
        },
    
    }

    lsp.ensure_installed({
        'vtsls',
        'eslint',
        'lua_ls',
        'rust_analyzer',
        'pylsp'
    })

    local cmp = require('cmp')
    local cmp_select = {behavior = cmp.SelectBehavior.Select}
    local cmp_mappings = lsp.defaults.cmp_mappings({
        ['<C-p>'] = cmp.mapping.select_prev_item(cmp_select),
        ['<C-n>'] = cmp.mapping.select_next_item(cmp_select),
        ['<C-y>'] = cmp.mapping.confirm({ select = true }),
        ['<C-Space>'] = cmp.mapping.complete(),
    })

    lsp.set_preferences({
        sign_icons = { }
    })

    lsp.on_attach(function(client, bufnr)
        
        local opts = {buffer = bufnr, remap = false}

        vim.keymap.set('n', 'gd', function() vim.lsp.buf.definition() end, opts)
        vim.keymap.set('n', 'K', function() vim.lsp.buf.hover() end, opts)
        vim.keymap.set('n', '<leader>vws', function() vim.lsp.buf.workspace_symbol() end, opts)
        vim.keymap.set('n', '<leader>vd', function() vim.diagnostic.open_float() end, opts)
        vim.keymap.set('n', '[d', function() vim.diagnostic.goto_next() end, opts)
        vim.keymap.set('n', ']d', function() vim.diagnostic.goto_prev() end, opts)
        vim.keymap.set('n', '<leader>vca', function() vim.lsp.buf.code_action() end, opts)
        vim.keymap.set('n', '<leader>vrr', function() vim.lsp.buf.references() end, opts)
        vim.keymap.set('n', '<leader>vrn', function() vim.lsp.buf.rename() end, opts)
        -- vim.keymap.set('n', '<C-h>', function() vim.lsp.buf.signature_help() end, opts)

    end)

    lsp.setup()
"
add_to_file $LSP_FILEPATH "$CONTENT"
nvim_source_lua_file "$LSP_FILEPATH"
###############################################################################
###############################################################################
###############################################################################
CONTENT="
-- I don't like this; vim.opt.guicursor = ' '

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
add_to_file $SET_FILEPATH "$CONTENT"
nvim_source_lua_file "$SET_FILEPATH"
###############################################################################
############################ Fugitive Config ##################################
###############################################################################