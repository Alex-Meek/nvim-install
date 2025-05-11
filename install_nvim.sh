#!/bin/bash

# To Do

# - [ ] Why is this better than just following the tutorial
    # 1. Using on multiple systems e.g. remote servers. (need to make this script robust, i.e. if curl is missing etc.)
# - [ ] Make it easer to change the configuration, e.g. the colorscheme.
# - [ ] Make sure each line is necessary, and we don't have a tonne of duplicate code 
# - [ ] Make sure the sections/layout makes sense.
# - [ ] If things should be in separate config files, move them there. 

# - [ ] .env file if it becomes necessary 

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

TELESCOPE_FILEPATH="$AFTER_PLUGIN_DIRECTORY/telescope.lua"

for i in $BASE_LUA_FILEPATH $SUB_LUA_FILEPATH $REMAP_FILEPATH $PACKER_FILEPATH $AFTER_INIT_LUA_FILEPATH $TELESCOPE_FILEPATH
do
    create_fresh_file $i
done

add_to_file $SUB_LUA_FILEPATH "print(\"Hello, from $SUB_LUA_FILEPATH!\")"
add_to_file $BASE_LUA_FILEPATH "require(\"$SUB_LUA_DIR_NAME\")"

###############################################################################
###############################################################################
###############################################################################

###############################################################################
################################### Remaps ####################################
###############################################################################
add_to_file $REMAP_FILEPATH "vim.g.mapleader = \" \""
add_to_file $REMAP_FILEPATH "vim.keymap.set(\"n\", \"<leader>pv\", \":Ex<CR>\")"
add_to_file $BASE_LUA_FILEPATH "require(\"$SUB_LUA_DIR_NAME.remap\")"
###############################################################################
###############################################################################
###############################################################################

###############################################################################
################################ Packer install ###############################
###############################################################################

if [[ -d "$HOME/.local/share/nvim/site/pack/packer" ]]; then
    yes | rm -r "$HOME/.local/share/nvim/site/pack/packer"
fi
git clone --depth 1 https://github.com/wbthomason/packer.nvim ~/.local/share/nvim/site/pack/packer/start/packer.nvim


CONTENT="-- This file can be loaded by calling \`lua require('plugins')\` from your init.vim
-- Only required if you have packer configured as \`opt\`
vim.cmd [[packadd packer.nvim]]

return require('packer').startup(function(use)

    -- Packer can manage itself
    use 'wbthomason/packer.nvim'

    use {
    'nvim-telescope/telescope.nvim', tag = '0.1.8',
    -- or                            , branch = '0.1.x',
    requires = { {'nvim-lua/plenary.nvim'} }
    }

    use({
        'rose-pine/neovim',
        as = 'rose-pine',
        config = function ()
            vim.cmd('colorscheme rose-pine')
        end
    })

    use('nvim-treesitter/nvim-treesitter', {run = ':TSUpdate'})
    use('nvim-treesitter/playground')

end)"

add_to_file $PACKER_FILEPATH "$CONTENT"
add_to_file $BASE_LUA_FILEPATH "require(\"$SUB_LUA_DIR_NAME.packer\")"

nvim --headless -c "autocmd User PackerComplete quitall" -c "PackerSync"
###############################################################################
###############################################################################
###############################################################################

###############################################################################
################################ Telescope install ############################
###############################################################################
add_to_file $TELESCOPE_FILEPATH "local builtin = require('telescope.builtin')"
add_to_file $TELESCOPE_FILEPATH "vim.keymap.set('n', '<leader>pf', builtin.find_files, { desc = 'Telescope find files' })"
add_to_file $TELESCOPE_FILEPATH "vim.keymap.set('n', '<C-p>', builtin.git_files, { })"

CONTENT="vim.keymap.set('n', '<leader>ps', function() 
    builtin.grep_string({ search = vim.fn.input(\"Grep > \") });
end)"

add_to_file $TELESCOPE_FILEPATH "$CONTENT"
###############################################################################
###############################################################################
###############################################################################

###############################################################################
################################### colours.lua ###############################
###############################################################################
COLOURS_LUA_FILEPATH="$AFTER_PLUGIN_DIRECTORY/colours.lua"

create_fresh_file $COLOURS_LUA_FILEPATH

CONTENT="
    function ColourMyPencils(colour)
        colour = colour or \"rose-pine\"
        vim.cmd.colorscheme(colour)

        vim.api.nvim_set_hl(0, \"Normal\", { bg=\"NONE\" })
        vim.api.nvim_set_hl(0, \"NormalFloat\", { bg=\"NONE\" })

    end

-- Ensure highlights are applied after the colorscheme loads
vim.api.nvim_create_autocmd(\"ColorScheme\", {
    pattern = \"*\",
    callback = function()
        vim.api.nvim_set_hl(0, \"Normal\", { bg=\"NONE\" })
        vim.api.nvim_set_hl(0, \"NormalFloat\", { bg=\"NONE\" })
    end
})

ColourMyPencils()
"

add_to_file $COLOURS_LUA_FILEPATH "$CONTENT"

###############################################################################
###############################################################################
###############################################################################

nvim --headless -c "autocmd User PackerComplete quitall" -c "PackerSync"
nvim --headless -c "lua ColourMyPencils()" -c "quitall"

###############################################################################
################################### Treesitter ################################
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

# Close the Lua table
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
  -- A list of parser names, or \"all\" (the listed parsers MUST always be installed)
  ensure_installed = ensure_list,

  -- Install parsers synchronously (only applied to \`ensure_installed\`)
  sync_install = false,

  -- Automatically install missing parsers when entering buffer
  -- Recommendation: set to false if you don't have \`tree-sitter\` CLI installed locally
  auto_install = true,

  highlight = {
    enable = true,

    -- Setting this to true will run \`:h syntax\` and tree-sitter at the same time.
    -- Set this to \`true\` if you depend on 'syntax' being enabled (like for indentation).
    -- Using this option may slow down your editor, and you may see some duplicate highlights.
    -- Instead of true it can also be a list of languages
    additional_vim_regex_highlighting = false,
  },
}
"

add_to_file $TREESITTER_LUA_FILEPATH "$CONTENT"
###############################################################################
###############################################################################
###############################################################################

nvim --headless -c "luafile $TREESITTER_LUA_FILEPATH" +qa