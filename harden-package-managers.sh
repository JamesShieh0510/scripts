#!/usr/bin/env bash
#
# harden-package-managers.sh
# 一鍵關閉各套件管理器的「安裝期 lifecycle 腳本」(preinstall/postinstall),
# 擋掉約 9 成的供應鏈竊密(它們多半靠安裝腳本在 npm install 當下執行)。
#
# 特性:冪等(可重複執行)、只動設定不裝東西、附 status / revert。
# 用法:
#   ./harden-package-managers.sh            # 套用強化(預設)
#   ./harden-package-managers.sh status     # 只查目前狀態,不修改
#   ./harden-package-managers.sh revert     # 還原(重新允許安裝腳本)
#
# 注意:
#  - 只影響「未來的安裝」,不會保護已裝好的 node_modules。
#  - 會擋掉合法 build(esbuild/sharp/better-sqlite3 等),裝完用 `npm rebuild <pkg>`
#    或臨時 `npm install --foreground-scripts` 針對性放行。
#
set -o pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; CYN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GRN}  ✓ $*${NC}"; }
warn() { echo -e "${YEL}  ! $*${NC}"; }
info() { echo -e "    $*"; }
hdr()  { echo -e "\n${CYN}== $* ==${NC}"; }

ACTION="${1:-apply}"
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------- npm ----------------
do_npm() {
    hdr "npm"
    have npm || { warn "未安裝 npm,略過"; return; }
    case "$ACTION" in
        status)
            local v; v=$(npm config get ignore-scripts 2>/dev/null)
            [ "$v" = "true" ] && ok "ignore-scripts = true(已關閉安裝腳本)" || warn "ignore-scripts = $v(仍會跑安裝腳本)"
            ;;
        revert)
            npm config delete ignore-scripts 2>/dev/null
            ok "已還原(npm 恢復預設,會跑安裝腳本)"
            ;;
        *)
            npm config set ignore-scripts true
            ok "已設 ignore-scripts=true(寫入 $(npm config get userconfig 2>/dev/null || echo ~/.npmrc))"
            info "需要 build 的套件: npm rebuild <pkg> 或 npm install --foreground-scripts"
            ;;
    esac
}

# ---------------- pnpm ----------------
do_pnpm() {
    hdr "pnpm"
    have pnpm || { info "未安裝 pnpm,略過"; return; }
    local major; major=$(pnpm --version 2>/dev/null | cut -d. -f1)
    case "$ACTION" in
        status)
            if [ "${major:-0}" -ge 10 ] 2>/dev/null; then
                ok "pnpm $major:預設即封鎖未白名單套件的安裝腳本"
            else
                warn "pnpm $major:建議在 .npmrc 設 enable-pre-post-scripts=false,或升級到 10+"
            fi
            ;;
        revert)
            warn "pnpm 設定多在各專案 .npmrc / package.json(onlyBuiltDependencies),請手動檢視"
            ;;
        *)
            if [ "${major:-0}" -ge 10 ] 2>/dev/null; then
                ok "pnpm $major 預設已封鎖,無需額外設定"
                info "要放行特定套件:package.json 加 pnpm.onlyBuiltDependencies: ['esbuild', ...]"
            else
                # 寫進使用者層 .npmrc(pnpm 也讀 npm 的 ignore-scripts)
                npm config set ignore-scripts true 2>/dev/null
                ok "已透過 ~/.npmrc ignore-scripts=true 涵蓋(建議升級 pnpm 到 10+)"
            fi
            ;;
    esac
}

# ---------------- yarn ----------------
do_yarn() {
    hdr "yarn"
    have yarn || { info "未安裝 yarn,略過"; return; }
    local major; major=$(yarn --version 2>/dev/null | cut -d. -f1)

    if [ "${major:-1}" -ge 2 ] 2>/dev/null; then
        # Yarn Berry:全域 .yarnrc.yml 的 enableScripts
        local rc="$HOME/.yarnrc.yml"
        case "$ACTION" in
            status)
                grep -q '^enableScripts: false' "$rc" 2>/dev/null && ok "Berry: enableScripts=false" || warn "Berry: enableScripts 未關閉"
                ;;
            revert)
                [ -f "$rc" ] && sed -i.bak '/^enableScripts: false/d' "$rc" 2>/dev/null && ok "已移除 enableScripts:false（備份 $rc.bak)"
                ;;
            *)
                touch "$rc"
                if grep -q '^enableScripts:' "$rc" 2>/dev/null; then
                    sed -i.bak 's/^enableScripts:.*/enableScripts: false/' "$rc"
                else
                    printf 'enableScripts: false\n' >> "$rc"
                fi
                ok "Berry: 已在 $rc 設 enableScripts: false"
                info "要放行特定套件:用 dependenciesMeta.<pkg>.built true"
                ;;
        esac
    else
        # Yarn Classic 1.x:沒有全域 ignore-scripts 設定,只能用 flag
        case "$ACTION" in
            status) warn "Classic $major:無全域設定,需每次 yarn install --ignore-scripts" ;;
            revert) info "Classic 無全域設定可還原" ;;
            *)
                warn "Yarn Classic($major)沒有全域 ignore-scripts 設定。建議擇一:"
                info "1) 每次安裝加旗標: yarn install --ignore-scripts"
                info "2) 加 shell 函式包裝(可加進 ~/.zshrc):"
                info "     yarn() { command yarn \"\$@\" \${@/#install/install --ignore-scripts}; }"
                info "3) 改用 bun / pnpm(預設較安全)"
                ;;
        esac
    fi
}

# ---------------- bun ----------------
do_bun() {
    hdr "bun"
    have bun || { info "未安裝 bun,略過"; return; }
    ok "bun $(bun --version):預設即封鎖「未信任套件」的安裝腳本"
    info "白名單機制:package.json 的 trustedDependencies 才會跑該套件的 postinstall"
    [ "$ACTION" = "revert" ] && info "(bun 無需還原:本腳本未改 bun 設定)"
}

echo -e "${CYN}套件管理器安裝腳本強化 — 動作: ${ACTION}${NC}"
do_npm
do_pnpm
do_yarn
do_bun

echo -e "\n${CYN}== 提醒 ==${NC}"
echo "  • 只影響未來安裝,不保護已裝好的 node_modules(那要靠鑑識腳本查)"
echo "  • 合法 build 被擋時針對性放行,不要全域關掉強化"
echo "  • 用 ./harden-package-managers.sh status 隨時複查"
