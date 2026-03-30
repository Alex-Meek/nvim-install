#!/bin/bash

set -e

REPO_URL="https://github.com/arturgoms/nvim"

###############################################################################
# Detect Neovim binary
###############################################################################

NVIM_CMD="nvim"

if ! "$NVIM_CMD" --version >/dev/null 2>&1; then
    echo "Neovim not found on PATH."
    echo "Install Neovim via MSYS2 (pacman -S mingw-w64-ucrt-x86_64-neovim) and re-run."
    exit 1
fi

echo "Using Neovim: $NVIM_CMD"

###############################################################################
# Choose config/data dirs to match Neovim on this OS
###############################################################################

UNAME_STR=$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')

if [[ "$UNAME_STR" == *"mingw"* ]] || [[ "$UNAME_STR" == *"msys"* ]]; then
    NVIM_CONFIG_DIR="$HOME/AppData/Local/nvim"
    NVIM_DATA_DIR="$HOME/AppData/Local/nvim-data"
else
    NVIM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
    NVIM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
fi

echo "Neovim config dir: $NVIM_CONFIG_DIR"
echo "Neovim data dir:   $NVIM_DATA_DIR"

###############################################################################
# Install Node.js + CLI tools on MSYS2
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
        UCRT64)     NODE_PKG="mingw-w64-ucrt-x86_64-nodejs" ;;
        CLANG64)    NODE_PKG="mingw-w64-clang-x86_64-nodejs" ;;
        MINGW64)    NODE_PKG="mingw-w64-x86_64-nodejs" ;;
        MINGW32)    NODE_PKG="mingw-w64-i686-nodejs" ;;
        CLANGARM64) NODE_PKG="mingw-w64-clang-aarch64-nodejs" ;;
        MSYS|"")
            [ "$UNAME_MACH" = "x86_64" ] \
                && NODE_PKG="mingw-w64-ucrt-x86_64-nodejs" \
                || NODE_PKG="nodejs"
            ;;
        *)
            [ "$UNAME_MACH" = "x86_64" ] \
                && NODE_PKG="mingw-w64-ucrt-x86_64-nodejs" \
                || NODE_PKG="nodejs"
            ;;
    esac

    echo "Installing package '$NODE_PKG'..."
    set +e
    pacman -Sy --needed --noconfirm "$NODE_PKG"
    local status=$?
    set -e

    if [ $status -ne 0 ]; then
        echo "pacman failed to install '$NODE_PKG' (exit $status)."
        return $status
    fi

    command -v node && node --version || echo "node not on PATH"
    command -v npm  && npm  --version || echo "npm not on PATH"
}

install_cli_tools_for_msys2() {
    echo "=== Installing CLI tools via MSYS2 pacman ==="

    if ! command -v pacman >/dev/null 2>&1; then
        return 1
    fi

    local pkgs=(
        mingw-w64-ucrt-x86_64-fzf
        mingw-w64-ucrt-x86_64-ripgrep
        findutils
    )

    pacman -Sy --needed --noconfirm "${pkgs[@]}"
}

warn_pwsh() {
    if ! command -v pwsh >/dev/null 2>&1; then
        echo ""
        echo "NOTE: 'pwsh' (PowerShell Core) not found."
        echo "Mason will show a warning but will still work for most packages."
        echo "To silence it, install manually after this script finishes:"
        echo "  winget install --id Microsoft.PowerShell"
        echo ""
    fi
}

###############################################################################
# Install npm globals: neovim package + tree-sitter-cli (if GLIBC >= 2.29)
# - neovim npm package fixes :checkhealth vim.provider Node warning
# - tree-sitter-cli fixes :checkhealth nvim-treesitter warning
#   (skipped on RHEL 8 / GLIBC < 2.29 — the prebuilt binary won't run there)
###############################################################################

install_npm_globals() {
    echo "=== Installing npm global packages ==="

    if ! command -v npm >/dev/null 2>&1; then
        echo "npm not found — skipping npm global installs."
        return 0
    fi

    echo "Installing neovim npm package..."
    set +e
    npm install -g neovim
    set -e

    # Parse the system GLIBC version from ldd
    local version_str major minor
    version_str=$(ldd --version 2>/dev/null | awk 'NR==1{ print $NF }')
    major=$(echo "$version_str" | cut -d. -f1)
    minor=$(echo "$version_str" | cut -d. -f2)

    echo "Detected GLIBC version: ${major}.${minor}"

    # tree-sitter-cli prebuilt binaries require GLIBC >= 2.29.
    # If GLIBC is too old, uninstall any existing tree-sitter-cli (it may
    # have been installed via nvm's npm, bypassing a previous GLIBC guard)
    # so nvim-treesitter cannot find it and falls back to gcc.
    local glibc_ok=true
    if [[ -n "$major" && -n "$minor" ]]; then
        if [[ "$major" -lt 2 ]] || \
           ( [[ "$major" -eq 2 ]] && [[ "$minor" -lt 29 ]] ); then
            glibc_ok=false
        fi
    fi

    if [[ "$glibc_ok" == false ]]; then
        echo "GLIBC ${major}.${minor} < 2.29 — skipping tree-sitter-cli install."
        echo "(Parsers will compile via gcc.)"
        # Evict any already-installed broken copy
        if command -v tree-sitter >/dev/null 2>&1; then
            echo "Removing existing (broken) tree-sitter-cli..."
            set +e
            npm uninstall -g tree-sitter-cli
            set -e
        fi
        return 0
    fi

    echo "Installing tree-sitter-cli..."
    set +e
    npm install -g tree-sitter-cli
    local status=$?
    set -e

    if [ $status -ne 0 ]; then
        echo "WARNING: npm install -g tree-sitter-cli failed (exit $status)."
        echo "Parsers will still compile via gcc — this is non-fatal."
    else
        echo "tree-sitter-cli installed successfully."
        command -v tree-sitter && tree-sitter --version || true
    fi
}
###############################################################################
# Install pynvim — fixes :checkhealth vim.provider Python warning
###############################################################################

install_pynvim() {
    echo "=== Installing pynvim ==="

    local PIP_CMD
    PIP_CMD=$(command -v pip3 2>/dev/null || command -v pip 2>/dev/null || true)

    if [[ -z "$PIP_CMD" ]]; then
        echo "pip not found — skipping pynvim install."
        return 0
    fi

    set +e
    "$PIP_CMD" install --quiet pynvim
    local status=$?
    set -e

    if [ $status -ne 0 ]; then
        echo "WARNING: pynvim install failed (exit $status). Python provider will show a warning."
    else
        echo "pynvim installed successfully."
    fi
}

if [[ "$UNAME_STR" == *"mingw"* ]] || [[ "$UNAME_STR" == *"msys"* ]]; then
    install_node_for_msys2
    install_cli_tools_for_msys2
    warn_pwsh
fi

install_npm_globals
install_pynvim

###############################################################################
# Helper functions
###############################################################################

create_directory() {
    local dir="$1"
    mkdir -p "$dir" && echo "Directory \"$dir\" ready." || {
        echo "Failed to create \"$dir\"."
        return 1
    }
}

create_file() {
    local file="$1"
    : > "$file" && echo "File \"$file\" created." || {
        echo "Failed to create \"$file\"."
        return 1
    }
}

add_to_file() {
    local file="$1"
    local content="$2"
    printf '%s\n' "$content" >> "$file"
}

###############################################################################
# Clean up old packer plugins
###############################################################################

PACKER_TREE="$NVIM_DATA_DIR/site/pack/packer"
if [[ -d "$PACKER_TREE" ]]; then
    echo "Removing old packer plugins at $PACKER_TREE"
    rm -rf "$PACKER_TREE"
fi

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
# FIX: Prepend provider disables + sessionoptions in one pass.
#
# vim.opt.runtimepath:prepend is intentionally NOT set here — lazy.nvim resets
# the rtp when it loads, so the correct mechanism is performance.rtp.paths in
# the lazy.setup() options (patched in patch_lazy_rocks below).
###############################################################################

if [[ -f "$INIT_LUA" ]]; then
    tmp="${INIT_LUA}.tmp"
    {
        cat <<'EOF'
-- Disable unused providers (suppresses :checkhealth warnings)
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

-- Session options for auto-session
vim.o.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"
EOF
        grep -v 'sessionoptions' "$INIT_LUA"
    } > "$tmp"
    mv "$tmp" "$INIT_LUA"
fi

###############################################################################
# Disable upstream personal.keymaps
###############################################################################

if [[ -f "$INIT_LUA" ]]; then
    tmp="${INIT_LUA}.tmp"
    awk '
      /require.*personal\.keymaps/ && !done {
        print "-- " $0
        done=1
        next
      }
      { print }
    ' "$INIT_LUA" > "$tmp"
    mv "$tmp" "$INIT_LUA"
fi

###############################################################################
# Disable upstream lsp.lsp-setup
###############################################################################

if [[ -f "$INIT_LUA" ]]; then
    tmp="${INIT_LUA}.tmp"
    awk '
      /require.*lsp\.lsp-setup/ && !done {
        print "-- " $0
        done=1
        next
      }
      { print }
    ' "$INIT_LUA" > "$tmp"
    mv "$tmp" "$INIT_LUA"
fi

###############################################################################
# FIX: Disable auto-session plugin
###############################################################################

AUTO_FILES=$(grep -rl 'rmagatti/auto-session' "$NVIM_CONFIG_DIR/lua" 2>/dev/null || true)
for f in $AUTO_FILES; do
    echo "Disabling auto-session in $f"
    python3 - "$f" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    src = fh.read()

patched = re.sub(
    r'("rmagatti/auto-session"),?',
    r'\1,\n    enabled = false,',
    src,
    count=1,
)

if 'enabled = false' not in src:
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(patched)
    print(f"  Patched {path}")
else:
    print(f"  Already patched, skipping {path}")
PYEOF
done

###############################################################################
# FIX: Disable luarocks/hererocks in lazy.nvim and register treesitter parser
# dir via performance.rtp.paths so lazy doesn't wipe it from the runtimepath.
###############################################################################

LAZY_PLUGINS_FILE="$NVIM_CONFIG_DIR/lua/lazy-plugins.lua"

patch_lazy_rocks() {
    local file="$1"
    python3 - "$file" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    src = fh.read()

if 'rocks' in src and 'hererocks' in src:
    print("  lazy rocks config already present, skipping.")
    sys.exit(0)

new_src = re.sub(
    r'(require\(["\']lazy["\']\)\.setup\(\s*\{.*?\})\s*\)',
    r'\1,\n'
    r'  {\n'
    r'    rocks = { enabled = false, hererocks = false },\n'
    r'    performance = {\n'
    r'      rtp = {\n'
    r'        paths = { vim.fn.stdpath("data") .. "/site" },\n'
    r'      },\n'
    r'    },\n'
    r'  }\n)',
    src,
    count=1,
    flags=re.DOTALL,
)

if new_src == src:
    print("  Could not auto-patch lazy rocks config. Add manually:")
    print('    require("lazy").setup({...}, {')
    print('      rocks = { enabled = false, hererocks = false },')
    print('      performance = { rtp = { paths = { vim.fn.stdpath("data") .. "/site" } } },')
    print('    })')
else:
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(new_src)
    print(f"  Patched lazy rocks config in {path}")
PYEOF
}

if [[ -f "$LAZY_PLUGINS_FILE" ]]; then
    patch_lazy_rocks "$LAZY_PLUGINS_FILE"
elif [[ -f "$INIT_LUA" ]]; then
    patch_lazy_rocks "$INIT_LUA"
fi

###############################################################################
# FIX: Pin nvim-treesitter to master branch (gcc compiler support)
# The main branch removed gcc support and requires tree-sitter-cli which
# needs GLIBC >= 2.29. master branch retains gcc compilation.
###############################################################################

echo "Pinning nvim-treesitter to master branch..."
TS_SPEC_FILE=$(grep -rl 'nvim-treesitter/nvim-treesitter' "$NVIM_CONFIG_DIR/lua" \
    --include="*.lua" 2>/dev/null | head -1)

if [[ -n "$TS_SPEC_FILE" ]]; then
    python3 - "$TS_SPEC_FILE" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    src = fh.read()

if 'branch = "master"' in src:
    print(f"  Already pinned, skipping {path}")
    sys.exit(0)

src = re.sub(
    r'(["\']nvim-treesitter/nvim-treesitter["\'])',
    r'\1, branch = "master"',
    src,
    count=1,
)

with open(path, 'w', encoding='utf-8') as fh:
    fh.write(src)
print(f"  Pinned nvim-treesitter to master in {path}")
PYEOF
else
    echo "WARNING: could not find nvim-treesitter plugin spec — pin manually."
fi

###############################################################################
# Patch lazy-plugins.lua: inject extra plugins
###############################################################################

if [[ -f "$LAZY_PLUGINS_FILE" ]] && ! grep -q 'shaunsingh/moonlight.nvim' "$LAZY_PLUGINS_FILE" 2>/dev/null; then
    tmp="${LAZY_PLUGINS_FILE}.tmp"
    awk '
      /require.*custom\.plugins\.debug/ && !done {
        print
        print "    { \"shaunsingh/moonlight.nvim\", lazy = false, priority = 1000 },"
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
    ' "$LAZY_PLUGINS_FILE" > "$tmp"
    mv "$tmp" "$LAZY_PLUGINS_FILE"
fi

###############################################################################
# Create override directory and files
###############################################################################

A_SUB_DIR="$NVIM_CONFIG_DIR/lua/a_sub_directory"
create_directory "$A_SUB_DIR"

REMAP_FILEPATH="$A_SUB_DIR/remap.lua"
LSP_CUSTOM_FILE="$A_SUB_DIR/lsp.lua"

create_file "$REMAP_FILEPATH"
create_file "$LSP_CUSTOM_FILE"

# FIX: use $A_SUB_DIR variable instead of hardcoded ~/.config/nvim path,
# and use add_to_file instead of a hardcoded >> redirection so the require
# lands in the correct init.lua on every OS (including MSYS2/Windows).
cat > "$A_SUB_DIR/lualine_fix.lua" <<'EOF'
-- Lualine's own ColorScheme autocmd calls lualine.setup() which cascades
-- and wipes treesitter highlight groups. Replace it with refresh() instead.
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    -- Remove lualine's internal ColorScheme handler
    pcall(vim.api.nvim_clear_autocmds, { group = "lualine", event = "ColorScheme" })

    -- Replace it with a safe version that doesn't cascade
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("lualine_safe", { clear = true }),
      callback = function()
        vim.schedule(function()
          pcall(require("lualine").refresh)
          -- Re-attach treesitter to all active buffers
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype ~= "" then
              pcall(vim.treesitter.start, buf)
            end
          end
        end)
      end,
    })
  end,
})
EOF

add_to_file "$INIT_LUA" "require('a_sub_directory.lualine_fix')"

###############################################################################
# FIX: Filetype detection in vsplits
# Deferred with vim.schedule so filetype detect never fires mid-treesitter
# attach sequence. Double-check inside the callback in case it was set
# between the BufWinEnter event and the scheduled tick.
###############################################################################

FILETYPE_FIX_FILE="$A_SUB_DIR/filetype_fix.lua"
cat > "$FILETYPE_FIX_FILE" <<'EOF'
vim.api.nvim_create_autocmd("BufWinEnter", {
  callback = function(ev)
    local buf = ev.buf
    vim.schedule(function()
      if
        vim.bo[buf].filetype == ""
        and vim.bo[buf].buftype == ""
        and vim.api.nvim_buf_get_name(buf) ~= ""
      then
        -- Run filetype detect in the context of the specific buffer,
        -- not whatever happens to be current at schedule time.
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("filetype detect")
        end)
      end
    end)
  end,
})
EOF

add_to_file "$INIT_LUA" "require('a_sub_directory.filetype_fix')"

###############################################################################
# FIX: Re-attach treesitter when returning to a buffer from file explorer
###############################################################################

TREESITTER_REATTACH_FILE="$A_SUB_DIR/treesitter_reattach.lua"
cat > "$TREESITTER_REATTACH_FILE" <<'EOF'
-- Re-attach treesitter on BufEnter for buffers that already have a filetype.
vim.api.nvim_create_autocmd("BufEnter", {
  callback = function(ev)
    local buf = ev.buf
    vim.schedule(function()
      if vim.bo[buf].buftype ~= "" then return end
      local ft = vim.bo[buf].filetype
      if ft == "" or ft == "netrw" then return end
      local hl = vim.treesitter.highlighter
      if hl and not hl.active[buf] then
        pcall(vim.treesitter.start, buf)
      end
    end)
  end,
})

-- Treesitter never auto-attaches after a delayed filetype detect.
-- This catches buffers that had filetype="" at BufEnter time and only
-- got their filetype set later (e.g. via the BufWinEnter filetype fix).
vim.api.nvim_create_autocmd("FileType", {
  callback = function(ev)
    local buf = ev.buf
    vim.schedule(function()
      if vim.bo[buf].buftype ~= "" then return end
      local hl = vim.treesitter.highlighter
      if hl and not hl.active[buf] then
        pcall(vim.treesitter.start, buf)
      end
    end)
  end,
})
EOF
add_to_file "$INIT_LUA" "require('a_sub_directory.treesitter_reattach')"

###############################################################################
# FIX: Treesitter compiler config — must load early so TSInstall uses gcc.
###############################################################################

TREESITTER_COMPILER_FILE="$A_SUB_DIR/treesitter_compiler.lua"
cat > "$TREESITTER_COMPILER_FILE" <<'EOF'
-- Strip broken tree-sitter-cli from PATH immediately (GLIBC too old).
local ts_exe = vim.fn.exepath('tree-sitter')
if ts_exe ~= '' then
  local ts_dir = vim.fn.fnamemodify(ts_exe, ':h')
  local parts = vim.split(vim.env.PATH, ':', { plain = true })
  parts = vim.tbl_filter(function(p) return p ~= ts_dir end, parts)
  vim.env.PATH = table.concat(parts, ':')
end

-- Patch nvim-treesitter's compiler selector to never attempt tree-sitter build.
-- This must be done after the plugin loads, before any TSInstall call.
local function patch_ts_install()
  local ok, install = pcall(require, 'nvim-treesitter.install')
  if not ok then return end
  install.prefer_git = false
  install.compilers   = { 'gcc', 'cc', 'g++', 'clang' }

  -- Patch the internal selector that picks tree-sitter build over gcc.
  local ok2, sel = pcall(require, 'nvim-treesitter.shell_command_selectors')
  if not ok2 or not sel then return end

  if type(sel.select_compiler_for_lang) == 'function' then
    local orig = sel.select_compiler_for_lang
    sel.select_compiler_for_lang = function(...)
      local result = orig(...)
      -- If the selected command is tree-sitter, discard it so the caller
      -- falls back to the next compiler (gcc).
      if type(result) == 'table'
         and type(result[1]) == 'table'
         and result[1][1] == 'tree-sitter'
      then
        return nil
      end
      return result
    end
  end
end

-- Apply immediately (in case nvim-treesitter was already loaded).
patch_ts_install()

-- Also apply on LazyLoad in case nvim-treesitter loads after this module.
vim.api.nvim_create_autocmd('User', {
  pattern  = 'LazyLoad',
  callback = function(ev)
    if ev.data == 'nvim-treesitter' then
      patch_ts_install()
    end
  end,
})
EOF

add_to_file "$INIT_LUA" "require('a_sub_directory.treesitter_compiler')"

###############################################################################
# FIX: Patch upstream wk.register() -> wk.add()
# Handles both the call-style (prefix= arg) and the table-literal old spec
# style ({ S = { name = "..." }, prefix = "<leader>" }) reported in checkhealth.
###############################################################################

echo "=== Patching upstream which-key register() calls ==="
WK_REGISTER_FILES=$(grep -rl 'wk\.register\b' "$NVIM_CONFIG_DIR/lua" \
    --include="*.lua" 2>/dev/null || true)

for f in $WK_REGISTER_FILES; do
    echo "  Converting wk.register() -> wk.add() in: $f"
    python3 - "$f" <<'PYEOF'
import sys
import re

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    src = fh.read()

def find_matching_paren(s, start):
    assert s[start] == '('
    depth = 0
    for i in range(start, len(s)):
        if s[i] == '(':
            depth += 1
        elif s[i] == ')':
            depth -= 1
            if depth == 0:
                return i
    return -1

changed = False
result = src

while True:
    m = re.search(r'wk\.register\s*\(', result)
    if not m:
        break

    paren_pos = m.end() - 1
    close = find_matching_paren(result, paren_pos)
    if close == -1:
        break

    call_body = result[paren_pos + 1 : close]

    if 'prefix' not in call_body:
        result = result[:m.start()] + 'wk.__register(' + result[m.end():]
        continue

    entries = re.findall(
        r'(\w+)\s*=\s*\{\s*name\s*=\s*["\']([^"\']+)["\']\s*\}',
        call_body,
    )

    prefix_m = re.search(r'prefix\s*=\s*["\']([^"\']+)["\']', call_body)
    prefix = prefix_m.group(1) if prefix_m else '<leader>'

    if not entries:
        break

    lines = ['wk.add({']
    for key, label in entries:
        lines.append(f'  {{ "{prefix}{key}", group = "{label}" }},')
    lines.append('})')
    replacement = '\n'.join(lines)

    result = result[:m.start()] + replacement + result[close + 1:]
    changed = True

result = result.replace('wk.__register(', 'wk.register(')

if changed:
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(result)
    print(f"  Patched: {path}")
else:
    print(f"  No prefix-style register() found in {path}, skipping.")
PYEOF
done

###############################################################################
# whichkey.lua
###############################################################################

cat > "$A_SUB_DIR/whichkey.lua" <<'EOF'
local ok, wk = pcall(require, "which-key")
if not ok then return end

wk.add({
  { "<leader>v",  group = "LSP" },
  { "<leader>cs", group = "Substitute" },
})
EOF

add_to_file "$INIT_LUA" "require('a_sub_directory.whichkey')"

###############################################################################
# remap.lua
###############################################################################

cat > "$REMAP_FILEPATH" <<'EOF'
vim.g.mapleader = ' '

vim.keymap.set('n', '<leader>pv', ':Ex<CR>')

vim.keymap.set('v', 'J', ":m '>+1<CR>gv=gv")
vim.keymap.set('v', 'K', ":m '<-2<CR>gv=gv")

vim.keymap.set('n', 'J', 'mzJ`z')

vim.keymap.set('n', '<C-d>', '<C-d>zz')
vim.keymap.set('n', '<C-u>', '<C-u>zz')

vim.keymap.set('n', 'n', 'nzzzv')
vim.keymap.set('n', 'N', 'nzzzv')

vim.keymap.set('x', '<leader>p', '"_dP')

vim.keymap.set('n', '<leader>y', '"+y')
vim.keymap.set('v', '<leader>y', '"+y')
vim.keymap.set('n', '<leader>Y', '"+Y')

vim.keymap.set('n', '<leader>d', '"_d')
vim.keymap.set('v', '<leader>d', '"_d')

vim.keymap.set('n', 'Q', '<nop>')

vim.keymap.set('n', '<C-k>', '<cmd>cnext<CR>zz')
vim.keymap.set('n', '<C-j>', '<cmd>cprev<CR>zz')
vim.keymap.set('n', '<leader>k', '<cmd>lnext<CR>zz')
vim.keymap.set('n', '<leader>j', '<cmd>lprev<CR>zz')

vim.keymap.set('n', '<leader>vd', vim.diagnostic.open_float, { desc = 'LSP: Diagnostics Float' })
vim.keymap.set('n', '[d',         vim.diagnostic.goto_prev,  { desc = 'LSP: Prev Diagnostic' })
vim.keymap.set('n', ']d',         vim.diagnostic.goto_next,  { desc = 'LSP: Next Diagnostic' })

vim.keymap.set('n', '<leader>cs', [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]])

vim.keymap.set('n', '<leader>x', '<cmd>!chmod +x %<CR>', { silent = true })

vim.opt.clipboard = 'unnamedplus'

if os.getenv('SSH_TTY') ~= nil then
  vim.g.clipboard = {
    name  = 'OSC 52',
    copy  = {
      ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
      ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
    },
    paste = {
      ['+'] = require('vim.ui.clipboard.osc52').paste('+'),
      ['*'] = require('vim.ui.clipboard.osc52').paste('*'),
    },
  }
end
EOF

###############################################################################
# lsp.lua
###############################################################################

cat > "$LSP_CUSTOM_FILE" <<'EOF'
local ok_cmp, cmp_nvim_lsp = pcall(require, 'cmp_nvim_lsp')
local capabilities = ok_cmp
    and cmp_nvim_lsp.default_capabilities()
    or vim.lsp.protocol.make_client_capabilities()

vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('UserLspKeymaps', { clear = true }),
    callback = function(ev)
        local nmap = function(keys, func, desc)
            vim.keymap.set('n', keys, func, {
                buffer = ev.buf,
                desc = desc and ('LSP: ' .. desc) or nil,
            })
        end

        nmap('gd',          vim.lsp.buf.definition, 'Goto Definition')
        nmap('K',           vim.lsp.buf.hover,       'Hover')
        nmap('<leader>vca', vim.lsp.buf.code_action, 'Code Action')
        nmap('<leader>vrn', vim.lsp.buf.rename,      'Rename')
    end,
})

vim.lsp.config('lua_ls', {
    capabilities = capabilities,
    settings = {
        Lua = {
            workspace  = { checkThirdParty = false },
            telemetry  = { enable = false },
        },
    },
})

vim.lsp.config('pyright',       { capabilities = capabilities })
vim.lsp.config('rust_analyzer', { capabilities = capabilities })
vim.lsp.config('elixirls',      { capabilities = capabilities })

require('mason').setup()

require('mason-lspconfig').setup({
    ensure_installed = { 'lua_ls', 'pyright', 'rust_analyzer', 'elixirls' },
    automatic_enable = true,
})

vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "*.py",
  callback = function()
    vim.lsp.start({
      name = "pyright",
      cmd = { "pyright-langserver", "--stdio" },
    })
  end,
})
EOF

###############################################################################
# fzf_lua.lua
###############################################################################

FZF_LUA_OVERRIDE="$A_SUB_DIR/fzf_lua.lua"
cat > "$FZF_LUA_OVERRIDE" <<'EOF'
local is_msys = (vim.fn.has('win32') == 1)
    or (os.getenv('MSYSTEM') ~= nil)
    or (os.getenv('MSYSCON') ~= nil)

if not is_msys then
    return
end

local ok, config = pcall(require, 'fzf-lua.config')
if not ok or not config.globals then
    return
end

local comspec = os.getenv('COMSPEC') or 'cmd.exe'
rawset(config.globals, '__shell',      comspec)
rawset(config.globals, '__shell_flag', '/s /c')
EOF

add_to_file "$INIT_LUA" "require('a_sub_directory.fzf_lua')"

###############################################################################
# Append remaining overrides to init.lua
###############################################################################

if [[ -f "$INIT_LUA" ]]; then
    add_to_file "$INIT_LUA" "
-- Load personal overrides
require('a_sub_directory.remap')
require('a_sub_directory.lsp')
"
fi

###############################################################################
# FIX: Replace treesitter-setup.lua with LazyDone-deferred safe version.
# parser_install_dir is set explicitly to stdpath("data")/site which is
# registered with lazy via performance.rtp.paths so it survives rtp resets.
###############################################################################

TS_SETUP="$NVIM_CONFIG_DIR/lua/lsp/treesitter-setup.lua"
if [[ -f "$TS_SETUP" ]]; then
    echo "Replacing treesitter-setup.lua with LazyDone-deferred safe version."
    cat > "$TS_SETUP" <<'EOF'
vim.api.nvim_create_autocmd('User', {
  pattern  = 'LazyDone',
  once     = true,
  callback = function()
    local ok, configs = pcall(require, 'nvim-treesitter.configs')
    if not ok then
      vim.notify(
        'nvim-treesitter not available: ' .. tostring(configs),
        vim.log.levels.WARN
      )
      return
    end

    -- Keep parsers in stdpath("data")/site, which is added to the rtp via
    -- lazy's performance.rtp.paths option (patched in lazy-plugins.lua).
    local parser_dir = vim.fn.stdpath("data") .. "/site"
    vim.fn.mkdir(parser_dir .. "/parser", "p")

    configs.setup({
      parser_install_dir = parser_dir,
      ensure_installed = {
        'bash', 'c', 'lua', 'python',
        'javascript', 'typescript',
        'rust', 'go',
        'html', 'css', 'json', 'yaml', 'toml',
        'query', 'vimdoc',
      },
      highlight = { enable = true },
      indent    = { enable = true },
    })
  end,
})
EOF
fi

#######################################################################################
# FIX: Force which-key to load eagerly (lazy=false)
# Without this, the first keypress that triggers which-key to load is
# consumed, causing 'v' to require two presses on first use.
###############################################################################

echo "=== Patching which-key to load eagerly ==="
WK_SPEC_FILE=$(grep -rl 'which-key' "$NVIM_CONFIG_DIR/lua" \
    --include="*.lua" 2>/dev/null | head -1)

if [[ -n "$WK_SPEC_FILE" ]]; then
    echo "  Patching which-key spec in: $WK_SPEC_FILE"
    python3 - "$WK_SPEC_FILE" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    src = f.read()

if 'lazy = false' in src and 'which-key' in src:
    print("  which-key already marked lazy=false, skipping.")
    sys.exit(0)

# Remove any event/keys/cmd trigger on the which-key spec
src = re.sub(
    r'(["\']folke/which-key\.nvim["\'][^}]*?)'
    r',?\s*event\s*=\s*["\'][^"\']*["\']',
    r'\1',
    src, flags=re.DOTALL
)

# Inject lazy=false, priority=100 after the plugin name
src = re.sub(
    r'(["\']folke/which-key\.nvim["\'])',
    r'\1,\n    lazy = false,\n    priority = 100,',
    src, count=1
)

with open(path, 'w', encoding='utf-8') as f:
    f.write(src)
print(f"  Patched: {path}")
PYEOF
else
    echo "  WARNING: could not find which-key plugin spec."
fi

#######################################################################
# FIX: Copilot duplicate keymaps
###############################################################################

echo "=== Patching copilot duplicate keymaps ==="

python3 - "$NVIM_CONFIG_DIR" <<'PYEOF'
import os, re, sys

config_dir = sys.argv[1]

for root, _, files in os.walk(config_dir):
    for fname in files:
        if not fname.endswith('.lua'):
            continue
        path = os.path.join(root, fname)
        with open(path, 'r', encoding='utf-8') as fh:
            src = fh.read()

        if 'copilot' not in src.lower():
            continue

        if 'accept = false' in src:
            print(f"  Already patched: {path}")
            continue

        original = src

        src = re.sub(
            r'(suggestion\s*=\s*\{[^}]*keymap\s*=\s*\{)[^}]*(})',
            r'\1 accept = false, next = false, prev = false, dismiss = false \2',
            src,
            flags=re.DOTALL,
        )

        if src == original and re.search(r'suggestion\s*=\s*\{', src):
            src = re.sub(
                r'(suggestion\s*=\s*\{)',
                r'\1\n        keymap = { accept = false, next = false, prev = false, dismiss = false },',
                src, count=1,
            )

        if src == original and re.search(r'require\s*\(\s*["\']copilot["\']\s*\)\s*\.setup\s*\(', src):
            src = re.sub(
                r'(require\s*\(\s*["\']copilot["\']\s*\)\s*\.setup\s*\(\s*\{)',
                r'\1\n  suggestion = { keymap = { accept = false, next = false, prev = false, dismiss = false } },',
                src, count=1,
            )

        if src == original and re.search(r'["\']zbirenbaum/copilot', src):
            if re.search(r'\bopts\s*=\s*\{', src):
                src = re.sub(
                    r'(\bopts\s*=\s*\{)',
                    r'\1\n      suggestion = { keymap = { accept = false, next = false, prev = false, dismiss = false } },',
                    src, count=1,
                )
            else:
                src = re.sub(
                    r'(["\']zbirenbaum/copilot\.lua["\'][^}]*?)(,?\s*\})',
                    r'\1,\n    opts = { suggestion = { keymap = { accept = false, next = false, prev = false, dismiss = false } } }\2',
                    src, count=1, flags=re.DOTALL,
                )

        if src != original:
            with open(path, 'w', encoding='utf-8') as fh:
                fh.write(src)
            print(f"  Patched: {path}")
        else:
            print(f"  WARNING: no pattern matched in: {path}")
            for i, line in enumerate(src.splitlines(), 1):
                if 'copilot' in line.lower() or 'suggestion' in line.lower():
                    print(f"    line {i}: {line}")
PYEOF

cat > "$A_SUB_DIR/copilot_keys.lua" <<'EOF'
vim.api.nvim_create_autocmd('InsertEnter', {
  once     = true,
  callback = function()
    local ok, s = pcall(require, 'copilot.suggestion')
    if not ok then return end
    vim.keymap.set('i', '<C-a>', function() s.accept() end, { desc = 'Copilot: Accept' })
    vim.keymap.set('i', '<C-j>', function() s.next()   end, { desc = 'Copilot: Next' })
    vim.keymap.set('i', '<C-k>', function() s.prev()   end, { desc = 'Copilot: Prev' })
  end,
})
EOF

add_to_file "$INIT_LUA" "require('a_sub_directory.copilot_keys')"

###############################################################################
# FIX: Colorscheme races
# moonlight.nvim is lazy=false, priority=1000 so applying only on VimEnter
# avoids a double reload that can wipe treesitter highlight groups on the
# first buffer.
#
# FIX 1: Use $A_SUB_DIR variable (not hardcoded ~/.config/nvim path) so the
#         file lands in the right place on every OS including MSYS2/Windows.
# FIX 2: add_to_file "$INIT_LUA" so the module is actually require'd.
# FIX 3: BufEnter guard no longer skips ft == 'netrw' for the colorscheme
#         check — netrw should still receive moonlight colors. Only the
#         treesitter re-attach (in treesitter_reattach.lua) skips netrw.
###############################################################################

cat > "$A_SUB_DIR/colorscheme.lua" <<'EOF'
local function reattach_treesitter_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf)
       and vim.bo[buf].buftype == ""
       and vim.bo[buf].filetype ~= ""
    then
      pcall(vim.treesitter.start, buf)
    end
  end
end

local function apply_moonlight()
  vim.g.moonlight_italic_comments    = true
  vim.g.moonlight_italic_keywords    = true
  vim.g.moonlight_italic_functions   = true
  vim.g.moonlight_contrast           = true
  vim.g.moonlight_disable_background = false
  local ok, err = pcall(vim.cmd.colorscheme, 'moonlight')
  if not ok then
    vim.notify('moonlight colorscheme failed: ' .. tostring(err), vim.log.levels.WARN)
    return
  end
  -- Defer reattach so buffers opened *after* this colorscheme call
  -- (e.g. from netrw) have time to complete filetype detection first.
  vim.defer_fn(reattach_treesitter_all, 50)
end

vim.api.nvim_create_autocmd('VimEnter', {
  once     = true,
  callback = function()
    vim.schedule(apply_moonlight)
  end,
})

vim.api.nvim_create_autocmd('ColorScheme', {
  callback = function(ev)
    if ev.match == 'moonlight' then return end
    vim.schedule(apply_moonlight)
  end,
})
EOF


# FIX: wire the module into init.lua (was missing entirely in the original).
add_to_file "$INIT_LUA" "require('a_sub_directory.colorscheme')"

###############################################################################
# FIX: vim.highlight -> vim.hl
###############################################################################

AUTOCOMMANDS_FILE="$NVIM_CONFIG_DIR/lua/personal/autocommands.lua"
if [[ -f "$AUTOCOMMANDS_FILE" ]]; then
    echo "Patching vim.highlight -> vim.hl in $AUTOCOMMANDS_FILE"
    sed -i 's/\bvim\.highlight\b/vim.hl/g' "$AUTOCOMMANDS_FILE"
fi

###############################################################################
# Pre-install plugins via lazy.nvim
###############################################################################

echo "Running Lazy sync (attempt 1)..."
set +e
"$NVIM_CMD" --headless "+Lazy! sync" +qa
lazy_status=$?
set -e

if [ $lazy_status -ne 0 ]; then
    echo "Lazy sync attempt 1 exited $lazy_status, retrying..."
    set +e
    "$NVIM_CMD" --headless "+Lazy! sync" +qa
    set -e
fi

###############################################################################
# Update treesitter parsers and install python parser
###############################################################################

TS_PLUGIN_DIR="$NVIM_DATA_DIR/lazy/nvim-treesitter"
if [[ -d "$TS_PLUGIN_DIR" ]]; then
    echo "Updating treesitter parsers..."
    set +e
    "$NVIM_CMD" --headless "+TSUpdate query" +qa
    "$NVIM_CMD" --headless "+TSUpdate vimdoc" +qa
    echo "Installing python treesitter parser..."
    "$NVIM_CMD" --headless \
        -c "lua require('nvim-treesitter.install').compilers = {'gcc','cc','g++','clang'}" \
        -c "TSInstall! python" \
        -c "qa"
    set -e
else
    echo "Skipping TSUpdate: nvim-treesitter not installed yet."
    echo "Open Neovim and run :Lazy sync, then :TSUpdate manually."
fi

###############################################################################
# Post-install notes
###############################################################################

echo ""
echo "====================================================================="
echo "Install complete. Remaining manual steps:"
echo ""
echo "  1. Open Neovim. If :Lazy shows failed plugins, run :Lazy sync again."
echo ""
echo "  2. GitHub Copilot: nvim -> :Copilot auth"
echo ""
echo "  3. If 'pwsh' was just installed, restart your shell so Mason can"
echo "     find it for Windows-specific package installs."
echo ""
echo "  4. Substitute-word is now <leader>cs (was <leader>s)."
echo "     This avoids shadowing the upstream Search group on <leader>s."
echo ""
echo "  5. Run :checkhealth in Neovim to verify remaining issues."
echo "     Expected remaining noise: luarocks/pwsh/java/ruby/go/cargo"
echo "     (only relevant if you use those languages)."
echo "====================================================================="
