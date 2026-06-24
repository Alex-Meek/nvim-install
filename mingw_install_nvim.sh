#!/usr/bin/env bash
# Neovim Installer for Git Bash / MinGW and remote Linux
# Fixes:
# - real colored installer output
# - installs correct Neovim release for Windows/Linux + CPU arch + glibc
# - correct Neovim config/data paths
# - correct packer install path
# - ensures ~/.local/bin is on PATH
# - keymaps load properly
# - gruvbox colorscheme loads properly
# - Hybrid remote clipboard handling (MobaXterm X11 vs MSYS2 OSC52)

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

version_ge() {
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" == "$2" ]]
}

detect_glibc_version() {
  local v=""

  if command -v getconf >/dev/null 2>&1; then
    v="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2; exit}')"
    if [[ -n "$v" ]]; then
      printf '%s\n' "$v"
      return 0
    fi
  fi

  if command -v ldd >/dev/null 2>&1; then
    v="$(
      ldd --version 2>/dev/null | awk '
        NR == 1 {
          for (i = 1; i <= NF; i++) {
            if ($i ~ /^[0-9]+\.[0-9]+$/) {
              print $i
              exit
            }
          }
        }
      '
    )"
    if [[ -n "$v" ]]; then
      printf '%s\n' "$v"
      return 0
    fi
  fi

  return 1
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
    +"autocmd User PackerComplete ++once PackerCompile" \
    +"autocmd User PackerCompileDone ++once quitall" \
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

select_neovim_release() {
  NVIM_RELEASE_TAG="latest"

  if [[ "$PLATFORM" != "linux" ]]; then
    return
  fi

  case "$PLATFORM_ARCH" in
    x86_64 | amd64)
      local glibc_version=""
      glibc_version="$(detect_glibc_version || true)"

      if [[ -z "$glibc_version" ]]; then
        echo_info "Could not detect glibc version; using latest Neovim"
        return
      fi

      echo_info "Detected glibc: $glibc_version"

      if version_ge "$glibc_version" "2.34"; then
        NVIM_RELEASE_TAG="latest"
        NVIM_ASSET="nvim-linux-x86_64.tar.gz"
        NVIM_DIRNAME="nvim-linux-x86_64"
      elif version_ge "$glibc_version" "2.28"; then
        NVIM_RELEASE_TAG="v0.9.5"
        NVIM_ASSET="nvim-linux64.tar.gz"
        NVIM_DIRNAME="nvim-linux64"
        echo_info "Using Neovim v0.9.5 for glibc compatibility"
      else
        echo_error "glibc $glibc_version is too old for this installer's"
        echo_error "prebuilt Neovim binaries"
        echo_error "Use a site module, conda-forge, or build from source"
        exit 1
      fi
      ;;
  esac
}

validate_neovim_binary() {
  local output=""
  local status=0
  local real_bin="$NVIM_INSTALL_DIR/$NVIM_BIN_REL"

  if command -v timeout >/dev/null 2>&1; then
    set +e
    output="$(timeout 15s "$real_bin" --version 2>&1)"
    status=$?
    set -e
  else
    set +e
    output="$("$real_bin" --version 2>&1)"
    status=$?
    set -e
  fi

  if [[ $status -ne 0 ]]; then
    echo_error "Installed Neovim failed validation"
    printf '%s\n' "$output" >&2

    if [[ $status -eq 124 ]]; then
      echo_error "Neovim validation timed out"
    fi

    if grep -q 'GLIBC_' <<<"$output"; then
      echo_error "The downloaded Neovim binary is not compatible with"
      echo_error "this host's glibc"
    fi

    exit 1
  fi
}

install_nvim_launcher() {
  local target="$NVIM_INSTALL_DIR/$NVIM_BIN_REL"

  if [[ "$PLATFORM" == "linux" ]]; then
    if [[ "$(readlink -f "$BIN_DIR")" == \
      "$(readlink -f "$NVIM_INSTALL_DIR/bin")" ]]; then
      echo_ok "Using Neovim launcher already present in $NVIM_INSTALL_DIR/bin"
      return
    fi

    ln -sfn "$target" "$BIN_DIR/nvim"
    echo_ok "Linked: $BIN_DIR/nvim -> $target"
    return
  fi

  write_file "$BIN_DIR/nvim" <<EOF
#!/usr/bin/env bash
export TERM="\${TERM:-xterm-256color}"
export COLORTERM="\${COLORTERM:-truecolor}"
exec "$target" "\$@"
EOF

  chmod +x "$BIN_DIR/nvim"
}

install_neovim() {
  local tmp_dir archive_path download_url
  tmp_dir="$(mktemp -d)"
  archive_path="$tmp_dir/$NVIM_ASSET"

  if [[ "$NVIM_RELEASE_TAG" == "latest" ]]; then
    download_url="https://github.com/neovim/neovim/releases/latest/download/$NVIM_ASSET"
  else
    download_url="https://github.com/neovim/neovim/releases/download/$NVIM_RELEASE_TAG/$NVIM_ASSET"
  fi

  echo_info "Downloading Neovim $NVIM_RELEASE_TAG for $PLATFORM"
  echo_info "Asset: $NVIM_ASSET"
  curl -fsSLo "$archive_path" "$download_url"

  rm -rf \
    "$INSTALL_BASE_DIR/nvim-linux64" \
    "$INSTALL_BASE_DIR/nvim-linux-x86_64" \
    "$INSTALL_BASE_DIR/nvim-linux-arm64" \
    "$INSTALL_BASE_DIR/nvim-linux-armhf" \
    "$INSTALL_BASE_DIR/nvim-win64"

  case "$PLATFORM" in
    windows)
      unzip -q "$archive_path" -d "$INSTALL_BASE_DIR"
      ;;
    linux)
      tar -xzf "$archive_path" -C "$INSTALL_BASE_DIR"
      ;;
  esac

  validate_neovim_binary
  rm -rf "$tmp_dir"
}

require_cmd curl
require_cmd git

INSTALL_BASE_DIR="$HOME/.local"
BIN_DIR="$INSTALL_BASE_DIR/bin"

mkdir -p "$BIN_DIR"
detect_platform
select_neovim_release

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
echo_ok "Selected Neovim release: $NVIM_RELEASE_TAG"
install_neovim
install_nvim_launcher
ensure_local_bin_on_path
echo_ok "Neovim installed"

echo_info "Detecting Neovim config/data paths..."
if [[ "$PLATFORM" == "linux" ]]; then
  RAW_NVIM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
  RAW_NVIM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
else
  RAW_NVIM_CONFIG_DIR="$("$BIN_DIR/nvim" \
    -u NONE -i NONE --noplugin --headless \
    +"lua io.write(vim.fn.stdpath('config'))" +qall! 2>/dev/null)"
  RAW_NVIM_DATA_DIR="$("$BIN_DIR/nvim" \
    -u NONE -i NONE --noplugin --headless \
    +"lua io.write(vim.fn.stdpath('data'))" +qall! 2>/dev/null)"
fi

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
local function has(cmd)
  return vim.fn.executable(cmd) == 1
end

local is_remote = vim.env.SSH_CONNECTION
  or vim.env.SSH_CLIENT
  or vim.env.SSH_TTY
  or vim.env.MOSH_IP

-- 1. HYBRID REMOTE ENV (MobaXterm with X11 Forwarding enabled)
if is_remote and vim.env.DISPLAY then
  if has("xclip") then
    vim.g.clipboard = {
      name = "xclip-moba-x11",
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
    return
  elseif has("xsel") then
    vim.g.clipboard = {
      name = "xsel-moba-x11",
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
    return
  end
end

-- 2. HYBRID REMOTE ENV FALLBACK (MSYS2 / Mintty / Terminals with native OSC52 support)
if is_remote then
  if vim.fn.has("nvim-0.10") == 1 then
    vim.g.clipboard = {
      name = "osc52-native",
      copy = {
        ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
        ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
      },
      paste = {
        ["+"] = require("vim.ui.clipboard.osc52").paste("+"),
        ["*"] = require("vim.ui.clipboard.osc52").paste("*"),
      },
    }
  else
    vim.g.clipboard = {
      name = "osc52-plugin-fallback",
      copy = {
        ["+"] = function(lines) pcall(function() require("osc52").copy(table.concat(lines, "\n")) end) end,
        ["*"] = function(lines) pcall(function() require("osc52").copy(table.concat(lines, "\n")) end) end,
      },
      paste = {
        ["+"] = function() return {vim.fn.split(vim.fn.getreg('"'), '\n'), vim.fn.getregtype('"')} end,
        ["*"] = function() return {vim.fn.split(vim.fn.getreg('"'), '\n'), vim.fn.getregtype('"')} end,
      },
    }
  end
  return
end

-- 3. LOCAL MACHINE FALLBACKS
if has("wl-copy") and has("wl-paste") then
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
  return
end

if has("xclip") then
  vim.g.clipboard = {
    name = "xclip-local",
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
  return
end

if has("xsel") then
  vim.g.clipboard = {
    name = "xsel-local",
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

local ok, packer = pcall(require, "packer")
if not ok then
  return
end

local compile_path = vim.fn.stdpath("config")
  .. "/plugin/packer_compiled.lua"
local has_nvim_0_11 = vim.fn.has("nvim-0.11") == 1

packer.init({
  compile_path = compile_path,
  compile_on_sync = false,
  auto_reload_compiled = true,
})

packer.startup(function(use)
  use("wbthomason/packer.nvim")

  use({
    "morhetz/gruvbox",
    config = function()
      vim.o.background = "dark"
      vim.g.gruvbox_contrast_dark = "hard"
      vim.g.gruvbox_italic = 1
      pcall(vim.cmd.colorscheme, "gruvbox")
    end,
  })

  if has_nvim_0_11 then
    use({
      "nvim-telescope/telescope.nvim",
      requires = {
        "nvim-lua/plenary.nvim",
      },
      config = function()
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
  else
    use({
      "nvim-telescope/telescope.nvim",
      tag = "0.1.8",
      requires = {
        "nvim-lua/plenary.nvim",
      },
        config = function()
          local ok_telescope, telescope = pcall(require, "telescope")
          if not ok_telescope then
            return
          end
        
          telescope.setup({
            defaults = {
              preview = {
                treesitter = false,
              },
            },
          })
        
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
  end

  use({
    "nvim-treesitter/nvim-treesitter",
    run = function()
      local ok_install, install = pcall(
        require,
        "nvim-treesitter.install"
      )
      if ok_install then
        install.update({ with_sync = true })()
      end
    end,
    config = function()
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

  use({
    "ojroques/nvim-osc52",
    config = function()
      local is_remote = vim.env.SSH_CONNECTION
        or vim.env.SSH_CLIENT
        or vim.env.SSH_TTY
        or vim.env.MOSH_IP

      -- Clean native setup handles clipboard context dynamically. 
      -- The plugin fallback configuration only initializes for older Neovim releases (<0.10).
      if not is_remote or vim.fn.has("nvim-0.10") == 1 then
        return
      end

      local ok_osc, osc52 = pcall(require, "osc52")
      if not ok_osc then
        return
      end

      pcall(function()
        osc52.setup({
          max_length = 0,
          silent = true,
          trim = false,
        })
      end)
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

  if has_nvim_0_11 then
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

        local ok_mlc, mason_lspconfig = pcall(
          require,
          "mason-lspconfig"
        )
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
  end
end)
EOF

run_treesitter_update() {
  echo_info "Updating Treesitter parsers..."

  if ! "$BIN_DIR/nvim" --headless \
    +'lua local ok, install = pcall(require, "nvim-treesitter.install"); if ok then install.update({ with_sync = true })() end' \
    +qall
  then
    echo_error "Treesitter update failed. Open nvim and run :TSUpdate"
  else
    echo_ok "Treesitter parsers updated"
  fi
} 

rm -f "$NVIM_CONFIG_DIR/plugin/packer_compiled.lua" 2>/dev/null || true

if [[ ! -d "$PACKER_PATH" ]]; then
  echo_info "Cloning Packer..."
  git clone --depth 1 \
    https://github.com/wbthomason/packer.nvim \
    "$PACKER_PATH"
fi

run_packer_sync 1
run_packer_sync 2
run_treesitter_update

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
echo "  colorscheme  -> gruvbox"
