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

if [[ "$UNAME_STR" == *"mingw"* ]] || [[ "$UNAME_STR" == *"msys"* ]]; then
    install_node_for_msys2
    install_cli_tools_for_msys2
    warn_pwsh
fi

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
# FIX: Disable unused providers to suppress health warnings
###############################################################################

if [[ -f "$INIT_LUA" ]]; then
    tmp="${INIT_LUA}.tmp"
    {
        cat <<'EOF'
-- Disable unused providers (suppresses :checkhealth warnings)
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

EOF
        cat "$INIT_LUA"
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
# Force sessionoptions for auto-session
###############################################################################

if [[ -f "$INIT_LUA" ]]; then
    tmp="${INIT_LUA}.tmp"
    {
        echo 'vim.o.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"'
        awk 'NR>1 && $0 !~ /sessionoptions/' "$INIT_LUA"
    } > "$tmp"
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
# FIX: Disable luarocks/hererocks in lazy.nvim
###############################################################################

LAZY_PLUGINS_FILE="$NVIM_CONFIG_DIR/lua/lazy-plugins.lua"

patch_lazy_rocks() {
    local file="$1"
    python3 - "$file" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    src = fh.read()

if 'rocks' in src and 'enabled' in src:
    print("  lazy rocks config already present, skipping.")
    sys.exit(0)

new_src = re.sub(
    r'(require\(["\']lazy["\']\)\.setup\(\s*\{.*?\})\s*\)',
    r'\1,\n  {\n    rocks = { enabled = false },\n  }\n)',
    src,
    count=1,
    flags=re.DOTALL,
)

if new_src == src:
    print("  Could not auto-patch lazy rocks config. Add manually:")
    print('    require("lazy").setup({...}, { rocks = { enabled = false } })')
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

###############################################################################
# FIX: Patch upstream wk.register() -> wk.add() using brace-counting parser
# so the old prefix= spec is converted and which-key stops warning about it.
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
    """Return index of the ')' that closes the '(' at s[start]."""
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

    # Only convert calls that use the old prefix= style
    if 'prefix' not in call_body:
        # Mark as skipped so we don't loop forever
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

# Restore any skipped occurrences
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
# whichkey.lua: only register groups introduced by our overrides.
# Upstream groups are patched in-place above so don't re-add them here.
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
# remap.lua: global keymaps.
# Diagnostic maps are global so they work before any LSP server attaches.
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

-- Diagnostic maps are global: vim.diagnostic works without an LSP client
vim.keymap.set('n', '<leader>vd', vim.diagnostic.open_float, { desc = 'LSP: Diagnostics Float' })
vim.keymap.set('n', '[d',         vim.diagnostic.goto_prev,  { desc = 'LSP: Prev Diagnostic' })
vim.keymap.set('n', ']d',         vim.diagnostic.goto_next,  { desc = 'LSP: Next Diagnostic' })

-- Renamed from <leader>s to avoid shadowing the upstream Search group prefix
vim.keymap.set('n', '<leader>cs', [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]])

vim.keymap.set('n', '<leader>x', '<cmd>!chmod +x %<CR>', { silent = true })

vim.opt.clipboard = 'unnamedplus'

-- Only override on SSH sessions — local sessions auto-detect fine
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
# lsp.lua: LSP-specific buffer keymaps + mason setup.
# Diagnostic maps ([d, ]d, <leader>vd) live in remap.lua as globals.
###############################################################################

cat > "$LSP_CUSTOM_FILE" <<'EOF'
-- Modern LSP setup: vim.lsp.config (Neovim 0.11+) + mason-lspconfig v2

local ok_cmp, cmp_nvim_lsp = pcall(require, 'cmp_nvim_lsp')
local capabilities = ok_cmp
    and cmp_nvim_lsp.default_capabilities()
    or vim.lsp.protocol.make_client_capabilities()

-- Buffer-local LSP maps only. Diagnostic maps are global in remap.lua.
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
EOF

###############################################################################
# FIX: fzf-lua shell errors on MSYS2.
# fzf-lua detects Windows via PATHEXT and builds cmd.exe-style /s /c commands,
# but the shell on PATH is MSYS2 bash which rejects those flags.
# rawset() is required because config.globals has a __newindex guard.
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
# FIX: Replace treesitter-setup.lua with LazyDone-deferred safe version
###############################################################################

TS_SETUP="$NVIM_CONFIG_DIR/lua/lsp/treesitter-setup.lua"
if [[ -f "$TS_SETUP" ]]; then
    echo "Replacing treesitter-setup.lua with LazyDone-deferred safe version."
    cat > "$TS_SETUP" <<'EOF'
-- Defers setup until lazy.nvim fires LazyDone, guaranteeing nvim-treesitter
-- is on the runtimepath before we attempt to require it.
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
    configs.setup({
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

###############################################################################
# Patch which-key deprecated options (triggers_nowait, opts.window)
###############################################################################

WK_FILE=$(grep -rl 'triggers_nowait\|opts\.window' "$NVIM_CONFIG_DIR/lua" \
    --include="*.lua" 2>/dev/null | head -1)

if [[ -n "$WK_FILE" ]]; then
    echo "Patching which-key deprecated options in: $WK_FILE"
    python3 - "$WK_FILE" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    src = f.read()

src = re.sub(
    r'\btriggers_nowait\s*=\s*\{[^}]*\},?\s*\n?',
    '',
    src,
    flags=re.DOTALL,
)

src = re.sub(r'\bwindow\s*=\s*\{', 'win = {', src)

with open(path, 'w', encoding='utf-8') as f:
    f.write(src)

print(f"  Patched: {path}")
PYEOF
else
    echo "No which-key config with deprecated options found."
fi

###############################################################################
# FIX: Copilot duplicate keymaps
# Must run BEFORE Lazy sync. We do two things:
#   1. Patch the upstream copilot plugin spec to set all suggestion keymaps
#      to false so copilot.lua never self-registers them.
#   2. Write a dedicated override file that registers them exactly once.
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

        # Strategy 1: suggestion = { keymap = { accept = "<C-x>" ... } }
        # Replace the keymap table values with false
        src = re.sub(
            r'(suggestion\s*=\s*\{[^}]*keymap\s*=\s*\{)[^}]*(})',
            r'\1 accept = false, next = false, prev = false, dismiss = false \2',
            src,
            flags=re.DOTALL,
        )

        # Strategy 2: suggestion = { ... } exists but no keymap key inside it
        if src == original and re.search(r'suggestion\s*=\s*\{', src):
            src = re.sub(
                r'(suggestion\s*=\s*\{)',
                r'\1\n        keymap = { accept = false, next = false, prev = false, dismiss = false },',
                src, count=1,
            )

        # Strategy 3: require("copilot").setup({ ... }) — inject suggestion block
        if src == original and re.search(r'require\s*\(\s*["\']copilot["\']\s*\)\s*\.setup\s*\(', src):
            src = re.sub(
                r'(require\s*\(\s*["\']copilot["\']\s*\)\s*\.setup\s*\(\s*\{)',
                r'\1\n  suggestion = { keymap = { accept = false, next = false, prev = false, dismiss = false } },',
                src, count=1,
            )

        # Strategy 4: lazy spec with opts = { } — inject suggestion into opts
        if src == original and re.search(r'["\']zbirenbaum/copilot', src):
            # Check if there's an opts block
            if re.search(r'\bopts\s*=\s*\{', src):
                src = re.sub(
                    r'(\bopts\s*=\s*\{)',
                    r'\1\n      suggestion = { keymap = { accept = false, next = false, prev = false, dismiss = false } },',
                    src, count=1,
                )
            else:
                # No opts — inject opts before the closing of the plugin spec table
                # Find the copilot spec and add opts
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
            # Print relevant lines to help debug
            for i, line in enumerate(src.splitlines(), 1):
                if 'copilot' in line.lower() or 'suggestion' in line.lower():
                    print(f"    line {i}: {line}")
PYEOF

# Write a clean override that registers the keymaps exactly once.
# Uses InsertEnter (not LazyDone) because copilot.suggestion is only
# available after a suggestion fires for the first time.
cat > "$A_SUB_DIR/copilot_keys.lua" <<'EOF'
-- Register Copilot suggestion keymaps exactly once on first insert.
-- copilot.lua's own keymap registration is disabled via `keymap = false`
-- in its setup() call (patched by install script), so these are the
-- only registrations.
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
# FIX: Colorscheme races — force moonlight as the final word after LazyDone
###############################################################################

cat > "$A_SUB_DIR/colorscheme.lua" <<'EOF'
-- moonlight.nvim is loaded eagerly (lazy=false, priority=1000),
-- so it is safe to apply here directly. VimEnter is used as a
-- fallback to ensure all other startup colorscheme calls are overridden.
local function apply_moonlight()
  vim.g.moonlight_italic_comments    = true
  vim.g.moonlight_italic_keywords    = true
  vim.g.moonlight_italic_functions   = true
  vim.g.moonlight_contrast           = true
  vim.g.moonlight_disable_background = false
  local ok, err = pcall(vim.cmd.colorscheme, 'moonlight')
  if not ok then
    vim.notify('moonlight colorscheme failed: ' .. tostring(err), vim.log.levels.WARN)
  end
end

-- Apply immediately (plugin is eager), then re-apply on VimEnter
-- to win any race against the upstream colorscheme setting.
apply_moonlight()

vim.api.nvim_create_autocmd('VimEnter', {
  once     = true,
  callback = apply_moonlight,
})
EOF


add_to_file "$INIT_LUA" "require('a_sub_directory.colorscheme')"


###############################################################################
# FIX: vim.highlight -> vim.hl (deprecated in Nvim 2.0)
###############################################################################

AUTOCOMMANDS_FILE="$NVIM_CONFIG_DIR/lua/personal/autocommands.lua"
if [[ -f "$AUTOCOMMANDS_FILE" ]]; then
    echo "Patching vim.highlight -> vim.hl in $AUTOCOMMANDS_FILE"
    sed -i 's/\bvim\.highlight\b/vim.hl/g' "$AUTOCOMMANDS_FILE"
fi

###############################################################################
# Pre-install plugins via lazy.nvim (with retry for transient failures)
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
# Update treesitter parsers
###############################################################################

TS_PLUGIN_DIR="$NVIM_DATA_DIR/lazy/nvim-treesitter"
if [[ -d "$TS_PLUGIN_DIR" ]]; then
    echo "Updating treesitter parsers..."
    set +e
    "$NVIM_CMD" --headless "+TSUpdate query" +qa
    "$NVIM_CMD" --headless "+TSUpdate vimdoc" +qa
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
echo "     Expected remaining noise: luarocks/pwsh/java/ruby (safe to ignore)."
echo "====================================================================="
