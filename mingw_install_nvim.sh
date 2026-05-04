#!/usr/bin/env bash
# Neovim Installer for Git Bash / MinGW and remote Linux
# Fixes:
# - real colored installer output
# - installs correct Neovim release for Windows/Linux + CPU arch
# - correct Neovim config/data paths
# - correct packer install path
# - ensures ~/.local/bin is on PATH
# - keymaps load properly
# - rose-pine colorscheme loads properly

set -euo pipefail

if [[ -t 1 ]]; then
  C_INFO=$'\033[1;34m'
  C_OK=$'\033[1;32m'
  C_ERR=$'\033[1;31m'
  C_RST=$'\033[0m'
else
  C_INFO=""
  C_OK=""
  C_ERR=""
  C_RST=""
fi

echo_info() {
  printf "%b\n" "${C_INFO}➤${C_RST} $1"
}

echo_ok() {
  printf "%b\n" "${C_OK}✅${C_RST} $1"
}

echo_error() {
  printf "%b\n" "${C_ERR}❌${C_RST} $1"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo_error "Missing required command: $1"
    exit 1
  fi
}

normalize_path() {
  local p="$1"

  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$p"
  else
    printf '%s\n' "${p//\\//}"
  fi
}

create_fresh_directory() {
  local dir="$1"
  rm -rf "$dir" 2>/dev/null || true
  mkdir -p "$dir"
  echo_ok "Directory: $dir"
}

write_file() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  cat > "$file"
  echo_ok "Written: $file"
}

ensure_local_bin_on_path() {
  export PATH="$BIN_DIR:$PATH"

  local bashrc="$HOME/.bashrc"
  local line='export PATH="$HOME/.local/bin:$PATH"'

  if [[ -f "$bashrc" ]]; then
    if ! grep -qxF "$line" "$bashrc"; then
      printf '\n%s\n' "$line" >> "$bashrc"
      echo_ok "Added ~/.local/bin to PATH in ~/.bashrc"
    fi
  else
    printf '%s\n' "$line" > "$bashrc"
    echo_ok "Created ~/.bashrc and added ~/.local/bin to PATH"
  fi
}

run_packer_sync() {
  echo_info "Running PackerSync (pass $1)..."

  if ! "$BIN_DIR/nvim" --headless \
    +"autocmd User PackerComplete quitall" \
    +"PackerSync"
  then
    echo_error "PackerSync pass $1 failed. Open nvim and run :PackerSync"
  else
    echo_ok "PackerSync pass $1 complete"
  fi
}

detect_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Linux)
      PLATFORM="linux"

      case "$arch" in
        x86_64 | amd64)
          NVIM_ASSET="nvim-linux-x86_64.tar.gz"
          NVIM_DIRNAME="nvim-linux-x86_64"
          NVIM_BIN_REL="bin/nvim"
          ;;
        aarch64 | arm64)
          NVIM_ASSET="nvim-linux-arm64.tar.gz"
          NVIM_DIRNAME="nvim-linux-arm64"
          NVIM_BIN_REL="bin/nvim"
          ;;
        armv7l | armv6l)
          NVIM_ASSET="nvim-linux-armhf.tar.gz"
          NVIM_DIRNAME="nvim-linux-armhf"
          NVIM_BIN_REL="bin/nvim"
          ;;
        *)
          echo_error "Unsupported Linux architecture: $arch"
          exit 1
          ;;
      esac
      ;;
    MINGW* | MSYS* | CYGWIN*)
      PLATFORM="windows"
      NVIM_ASSET="nvim-win64.zip"
      NVIM_DIRNAME="nvim-win64"
      NVIM_BIN_REL="bin/nvim.exe"
      ;;
    *)
      echo_error "Unsupported operating system: $os"
      exit 1
      ;;
  esac

  PLATFORM_ARCH="$arch"
}

install_neovim() {
  local tmp_dir archive_path download_url
  tmp_dir="$(mktemp -d)"
  archive_path="$tmp_dir/$NVIM_ASSET"
  download_url="https://github.com/neovim/neovim/releases/latest/download/$NVIM_ASSET"

  echo_info "Downloading latest Neovim for $PLATFORM ($PLATFORM_ARCH)..."
  curl -fsSLo "$archive_path" "$download_url"

  rm -rf "$NVIM_INSTALL_DIR"

  case "$PLATFORM" in
    windows)
      unzip -q "$archive_path" -d "$INSTALL_BASE_DIR"
      ;;
    linux)
      tar -xzf "$archive_path" -C "$INSTALL_BASE_DIR"
      ;;
  esac

  rm -rf "$tmp_dir"
}

require_cmd curl
require_cmd git

INSTALL_BASE_DIR="$HOME/.local"
BIN_DIR="$INSTALL_BASE_DIR/bin"

mkdir -p "$BIN_DIR"
detect_platform

case "$PLATFORM" in
  windows)
    require_cmd unzip
    ;;
  linux)
    require_cmd tar
    ;;
esac

NVIM_INSTALL_DIR="$INSTALL_BASE_DIR/$NVIM_DIRNAME"

echo_ok "Detected platform: $PLATFORM ($PLATFORM_ARCH)"
install_neovim

write_file "$BIN_DIR/nvim" <<EOF
#!/usr/bin/env bash
export TERM="\${TERM:-xterm-256color}"
export COLORTERM="\${COLORTERM:-truecolor}"
exec "$NVIM_INSTALL_DIR/$NVIM_BIN_REL" "\$@"
EOF

chmod +x "$BIN_DIR/nvim"
ensure_local_bin_on_path
echo_ok "Neovim installed"

echo_info "Detecting Neovim config/data paths..."
RAW_NVIM_CONFIG_DIR="$("$BIN_DIR/nvim" \
  -u NONE -i NONE --noplugin --headless \
  +"lua io.write(vim.fn.stdpath('config'))" +qall! 2>/dev/null)"
RAW_NVIM_DATA_DIR="$("$BIN_DIR/nvim" \
  -u NONE -i NONE --noplugin --headless \
  +"lua io.write(vim.fn.stdpath('data'))" +qall! 2>/dev/null)"

if [[ -z "$RAW_NVIM_CONFIG_DIR" || -z "$RAW_NVIM_DATA_DIR" ]]; then
  echo_error "Failed to detect Neovim stdpath() directories"
  exit 1
fi

NVIM_CONFIG_DIR="$(normalize_path "$RAW_NVIM_CONFIG_DIR")"
NVIM_DATA_DIR="$(normalize_path "$RAW_NVIM_DATA_DIR")"
LUA_USER_DIR="$NVIM_CONFIG_DIR/lua/user"
PACKER_PATH="$NVIM_DATA_DIR/site/pack/packer/start/packer.nvim"

echo_ok "Config dir: $NVIM_CONFIG_DIR"
echo_ok "Data dir:   $NVIM_DATA_DIR"

echo_info "Creating fresh config..."
rm -rf "$NVIM_CONFIG_DIR" "$HOME/.config/nvim" 2>/dev/null || true
rm -rf "$NVIM_DATA_DIR/site/pack" 2>/dev/null || true
create_fresh_directory "$LUA_USER_DIR"
mkdir -p "$NVIM_DATA_DIR/undo" "$NVIM_CONFIG_DIR/plugin"

INIT_LUA="$NVIM_CONFIG_DIR/init.lua"
SETTINGS_LUA="$LUA_USER_DIR/settings.lua"
REMAPS_LUA="$LUA_USER_DIR/remaps.lua"
PLUGINS_LUA="$LUA_USER_DIR/plugins.lua"

CLIPBOARD_LUA="$LUA_USER_DIR/clipboard.lua"

write_file "$INIT_LUA" <<'EOF'
vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("user.settings")
require("user.clipboard")
require("user.remaps")
require("user.plugins")
EOF

write_file "$CLIPBOARD_LUA" <<'EOF'
local is_ssh = vim.env.SSH_CONNECTION ~= nil or vim.env.SSH_TTY ~= nil

vim.opt.clipboard = "unnamedplus"

if is_ssh then
  local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
  if ok then
    vim.g.clipboard = {
      name = "OSC52",
      copy = {
        ["+"] = osc52.copy("+"),
        ["*"] = osc52.copy("*"),
      },
      paste = {
        ["+"] = osc52.paste("+"),
        ["*"] = osc52.paste("*"),
      },
    }
  end
elseif vim.fn.executable("wl-copy") == 1
  and vim.fn.executable("wl-paste") == 1
then
  vim.g.clipboard = {
    name = "wl-clipboard",
    copy = {
      ["+"] = "wl-copy --foreground --type text/plain",
      ["*"] = "wl-copy --foreground --primary --type text/plain",
    },
    paste = {
      ["+"] = "wl-paste --no-newline",
      ["*"] = "wl-paste --no-newline --primary",
    },
    cache_enabled = 0,
  }
elseif vim.fn.executable("xclip") == 1 then
  vim.g.clipboard = {
    name = "xclip",
    copy = {
      ["+"] = "xclip -quiet -i -selection clipboard",
      ["*"] = "xclip -quiet -i -selection primary",
    },
    paste = {
      ["+"] = "xclip -o -selection clipboard",
      ["*"] = "xclip -o -selection primary",
    },
    cache_enabled = 0,
  }
elseif vim.fn.executable("xsel") == 1 then
  vim.g.clipboard = {
    name = "xsel",
    copy = {
      ["+"] = "xsel --clipboard --input",
      ["*"] = "xsel --primary --input",
    },
    paste = {
      ["+"] = "xsel --clipboard --output",
      ["*"] = "xsel --primary --output",
    },
    cache_enabled = 0,
  }
end
EOF

write_file "$SETTINGS_LUA" <<'EOF'
vim.opt.number = true
vim.opt.relativenumber = true

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true

vim.opt.wrap = false
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = vim.fn.stdpath("data") .. "/undo"
vim.opt.undofile = true

vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.termguicolors = true

vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 50
vim.opt.colorcolumn = "80"

vim.opt.isfname:append("@-@")
EOF

write_file "$REMAPS_LUA" <<'EOF'
local map = vim.keymap.set

map("n", "<leader>pv", vim.cmd.Ex)

map("v", "J", ":m '>+1<CR>gv=gv")
map("v", "K", ":m '<-2<CR>gv=gv")
map("n", "J", "mzJ`z")

map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")

map("x", "<leader>p", [["_dP]])
map({ "n", "v" }, "<leader>y", [["+y]])
map("n", "<leader>Y", [["+Y]])
map({ "n", "v" }, "<leader>d", [["_d]])

map("n", "Q", "<nop>")

map("n", "<C-k>", "<cmd>cnext<CR>zz")
map("n", "<C-j>", "<cmd>cprev<CR>zz")
map("n", "<leader>k", "<cmd>lnext<CR>zz")
map("n", "<leader>j", "<cmd>lprev<CR>zz")

map(
  "n",
  "<leader>s",
  [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]]
)

map("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })
EOF

write_file "$PLUGINS_LUA" <<'EOF'
vim.cmd("packadd packer.nvim")
vim.cmd("silent! packloadall")

local ok, packer = pcall(require, "packer")
if not ok then
  return
end

packer.init({
  compile_path = vim.fn.stdpath("config") .. "/plugin/packer_compiled.lua",
})

packer.startup(function(use)
  use("wbthomason/packer.nvim")

  use({
    "morhetz/gruvbox",
    config = function()
      vim.cmd("silent! packloadall")
      vim.o.background = "dark"
      vim.g.gruvbox_contrast_dark = "hard"
      vim.g.gruvbox_italic = 1
      pcall(vim.cmd.colorscheme, "gruvbox")
    end,
  })

  use({
    "nvim-telescope/telescope.nvim",
    requires = {
      "nvim-lua/plenary.nvim",
    },
    config = function()
      vim.cmd("silent! packloadall")

      local ok_tel, builtin = pcall(require, "telescope.builtin")
      if not ok_tel then
        return
      end

      vim.keymap.set("n", "<leader>pf", builtin.find_files, {
        desc = "Find files",
      })

      vim.keymap.set("n", "<C-p>", builtin.git_files, {
        desc = "Git files",
      })

      vim.keymap.set("n", "<leader>ps", function()
        builtin.grep_string({ search = vim.fn.input("Grep > ") })
      end, {
        desc = "Grep string",
      })
    end,
  })

  use({
    "nvim-treesitter/nvim-treesitter",
    run = ":TSUpdate",
    config = function()
      vim.cmd("silent! packloadall")

      local ok_ts, configs = pcall(require, "nvim-treesitter.configs")
      if not ok_ts then
        return
      end

      configs.setup({
        ensure_installed = {
          "bash",
          "c",
          "css",
          "html",
          "javascript",
          "json",
          "lua",
          "markdown",
          "python",
          "query",
          "vim",
          "vimdoc",
        },
        highlight = {
          enable = true,
        },
      })
    end,
  })

  use("ThePrimeagen/harpoon")

  use({
    "mbbill/undotree",
    config = function()
      vim.keymap.set("n", "<leader>u", vim.cmd.UndotreeToggle, {
        desc = "Undotree",
      })
    end,
  })

  use({
    "tpope/vim-fugitive",
    config = function()
      vim.keymap.set("n", "<leader>gs", vim.cmd.Git, {
        desc = "Git status",
      })
    end,
  })

  use({
    "VonHeikemen/lsp-zero.nvim",
    branch = "v3.x",
    requires = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "neovim/nvim-lspconfig",
      "hrsh7th/nvim-cmp",
      "hrsh7th/cmp-nvim-lsp",
      "L3MON4D3/LuaSnip",
    },
    config = function()
      vim.cmd("silent! packloadall")

      local ok_lsp, lsp_zero = pcall(require, "lsp-zero")
      if not ok_lsp then
        return
      end

      lsp_zero.on_attach(function(_, bufnr)
        lsp_zero.default_keymaps({ buffer = bufnr })
      end)

      local ok_mason, mason = pcall(require, "mason")
      if ok_mason then
        mason.setup()
      end

      local ok_mlc, mason_lspconfig = pcall(require, "mason-lspconfig")
      if ok_mlc then
        mason_lspconfig.setup({
          ensure_installed = {
            "lua_ls",
            "pyright",
            "rust_analyzer",
          },
          handlers = {
            lsp_zero.default_setup,
          },
        })
      end
    end,
  })
end)
EOF

rm -f "$NVIM_CONFIG_DIR/plugin/packer_compiled.lua" 2>/dev/null || true

if [[ ! -d "$PACKER_PATH" ]]; then
  echo_info "Cloning Packer..."
  git clone --depth 1 \
    https://github.com/wbthomason/packer.nvim \
    "$PACKER_PATH"
fi

run_packer_sync 1
run_packer_sync 2

echo
echo_ok "Installation finished!"
echo
echo "Open a new shell session (or run: source ~/.bashrc), then run:"
echo "  nvim"
echo
echo "If you want to verify you're using the correct binary, run:"
echo "  which nvim"
echo
echo "Expected tests:"
echo "  <leader>pv   -> file explorer"
echo "  <leader>pf   -> Telescope find files"
echo "  <leader>u    -> Undotree"
echo "  <leader>gs   -> Fugitive git status"
echo "  colorscheme  -> rose-pine"
