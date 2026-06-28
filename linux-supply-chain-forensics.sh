#!/usr/bin/env bash
#
# linux-supply-chain-forensics.sh
# 唯讀鑑識腳本 — 針對 npm/pip 供應鏈攻擊(安裝期竊密 + 執行期挖礦)
#
# 特性:只「讀取」不修改系統。不刪檔、不殺進程、不改設定。
# 用法:
#   chmod +x linux-supply-chain-forensics.sh
#   sudo ./linux-supply-chain-forensics.sh            # 建議用 root 取得完整覆蓋
#   ./linux-supply-chain-forensics.sh                 # 非 root 也能跑,部分項目會略過
#
# 輸出:畫面 + 一份報告檔 /tmp 之外的位置(預設家目錄)
#
# 重要提醒:攻擊會自刪證據。即使本腳本「沒發現」,只要你曾在此機開發過受影響專案,
#          仍應假設金鑰/token 全數外洩並全部輪換。雲端側日誌(CloudTrail/GitHub audit)
#          才是攻擊者刪不掉的證據,務必另外查。
#
set -uo pipefail

# ---------- 設定 ----------
REPORT="${HOME}/forensics-report-$(date +%Y%m%d-%H%M%S).txt"
FINDINGS=0
SCAN_HOME_USERS=()   # 要掃哪些使用者家目錄;預設自動偵測

# ---------- 輸出工具 ----------
RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; CYN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "$*" | tee -a "$REPORT"; }
hdr()  { log "\n${CYN}===== $* =====${NC}"; }
ok()   { log "${GRN}  [OK] $*${NC}"; }
warn() { log "${YEL}  [注意] $*${NC}"; }
hit()  { log "${RED}  [!! 可疑] $*${NC}"; FINDINGS=$((FINDINGS+1)); }
note() { log "       $*"; }

require_cmd() { command -v "$1" >/dev/null 2>&1; }

# ---------- 開頭 ----------
{
echo "Linux 供應鏈攻擊鑑識報告"
echo "時間: $(date)"
echo "主機: $(hostname 2>/dev/null)"
echo "核心: $(uname -a 2>/dev/null)"
echo "執行身分: $(id -un) (uid=$(id -u))"
[ "$(id -u)" -ne 0 ] && echo "警告: 非 root 執行,部分項目覆蓋不完整"
echo "報告檔: $REPORT"
} | tee "$REPORT"

# 偵測要掃描的家目錄
if [ "${#SCAN_HOME_USERS[@]}" -eq 0 ]; then
    HOMES=$(awk -F: '$3>=1000 && $3<65534 {print $6}' /etc/passwd 2>/dev/null | sort -u)
    [ -z "$HOMES" ] && HOMES="$HOME"
    HOMES="$HOMES /root"
fi

# =====================================================================
hdr "1. 執行期挖礦偵測 (Monero / xmrig 等)"
# =====================================================================
# 1a. 高 CPU 進程
log "  -- CPU 前 10 名進程 --"
ps -eo pid,ppid,user,%cpu,%mem,etime,comm --sort=-%cpu 2>/dev/null | head -11 | tee -a "$REPORT"

# 1b. 已知挖礦特徵的進程名 / 完整命令列
MINER_PAT='xmrig|xmr-stak|minerd|cpuminer|ccminer|cgminer|ethminer|nbminer|phoenixminer|t-rex|kdevtmpfsi|kinsing|monero|stratum|nicehash|randomx'
log "  -- 比對挖礦特徵字 --"
if ps -eo pid,user,args 2>/dev/null | grep -iE "$MINER_PAT" | grep -v grep | grep -qv "forensics"; then
    ps -eo pid,user,args 2>/dev/null | grep -iE "$MINER_PAT" | grep -v grep | grep -v "forensics" | while read -r l; do hit "挖礦特徵進程: $l"; done
else
    ok "未發現已知挖礦進程"
fi

# 1c. 從 /tmp /dev/shm /var/tmp 啟動的進程 (deleted 二進位)
log "  -- 執行映像位於暫存區或已被刪除的進程 (典型自刪手法) --"
found_tmp_proc=0
for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
    exe=$(readlink /proc/"$pid"/exe 2>/dev/null) || continue
    case "$exe" in
        /tmp/*|/var/tmp/*|/dev/shm/*)
            hit "PID $pid 從暫存區執行: $exe"; found_tmp_proc=1 ;;
        *"(deleted)")
            hit "PID $pid 執行已被刪除的二進位 (自刪痕跡): $exe"; found_tmp_proc=1 ;;
    esac
done
[ "$found_tmp_proc" -eq 0 ] && ok "無從暫存區/已刪除映像執行的進程"

# =====================================================================
hdr "2. /tmp /var/tmp /dev/shm 落地檔案 (亂數 / PID 命名)"
# =====================================================================
for d in /tmp /var/tmp /dev/shm; do
    [ -d "$d" ] || continue
    log "  -- $d 中的可執行一般檔 --"
    find "$d" -maxdepth 3 -type f -perm -u+x 2>/dev/null | grep -v "forensics" | head -40 | while read -r f; do
        hit "可執行檔: $f ($(stat -c '%y %U %s bytes' "$f" 2>/dev/null))"
    done
    # 亂數/十六進位/純數字命名的目錄或檔(攻擊常用 /tmp/<random> 或 /tmp/<pid>)
    find "$d" -maxdepth 1 -mindepth 1 \( -regextype posix-extended -regex '.*/[a-f0-9]{8,}$' -o -regextype posix-extended -regex '.*/[0-9]{4,}$' \) 2>/dev/null | head -30 | while read -r f; do
        warn "亂數/數字命名項目(需人工研判): $f"
    done
done
ok "(以上若無紅色 [!! 可疑] 代表暫存區無可執行落地檔)"

# =====================================================================
hdr "3. 持久化機制 (cron / systemd / rc / profile)"
# =====================================================================
# 3a. crontab — 系統 + 各使用者 + cron.d
log "  -- 系統 crontab / cron.d / cron.* --"
for cf in /etc/crontab /etc/cron.d/* /etc/cron.hourly/* /etc/cron.daily/* /etc/cron.weekly/* /etc/cron.monthly/*; do
    [ -f "$cf" ] || continue
    if grep -lE 'curl|wget|/tmp/|/dev/shm|base64|\.onion|xmr|stratum' "$cf" >/dev/null 2>&1; then
        hit "可疑 cron 檔: $cf"; grep -nE 'curl|wget|/tmp/|/dev/shm|base64|xmr|stratum' "$cf" 2>/dev/null | sed 's/^/        /' | tee -a "$REPORT"
    fi
done
log "  -- 各使用者 crontab --"
if require_cmd crontab; then
    for u in $(cut -d: -f1 /etc/passwd 2>/dev/null); do
        ct=$(crontab -l -u "$u" 2>/dev/null) || continue
        [ -z "$ct" ] && continue
        if echo "$ct" | grep -qE 'curl|wget|/tmp/|/dev/shm|base64|xmr|stratum'; then
            hit "使用者 $u 的 crontab 含可疑內容:"; echo "$ct" | grep -E 'curl|wget|/tmp/|/dev/shm|base64|xmr|stratum' | sed 's/^/        /' | tee -a "$REPORT"
        fi
    done
fi

# 3b. systemd 服務 / timer — 指向暫存區或近期建立
log "  -- systemd unit 指向暫存區 / 可疑路徑 --"
for ud in /etc/systemd/system /run/systemd/system /usr/lib/systemd/system ~/.config/systemd/user; do
    [ -d "$ud" ] || continue
    grep -rlE 'ExecStart=.*(/tmp/|/var/tmp/|/dev/shm/|curl|wget|base64)' "$ud" 2>/dev/null | while read -r u; do
        hit "可疑 systemd unit: $u"; grep -nE 'ExecStart=' "$u" 2>/dev/null | sed 's/^/        /' | tee -a "$REPORT"
    done
done
# 近 30 天內新建/異動的 systemd unit
log "  -- 近 30 天異動的 systemd unit (供比對) --"
find /etc/systemd/system /usr/lib/systemd/system -name '*.service' -mtime -30 2>/dev/null | head -20 | while read -r u; do note "$u  ($(stat -c '%y' "$u" 2>/dev/null))"; done

# 3c. rc.local / profile.d / shell rc 注入
log "  -- 開機與 shell 啟動檔注入 --"
for f in /etc/rc.local /etc/profile /etc/profile.d/* /etc/bash.bashrc; do
    [ -f "$f" ] || continue
    grep -lE 'curl|wget|/tmp/|/dev/shm|base64 -d|eval.*\$\(' "$f" >/dev/null 2>&1 && { hit "啟動檔含可疑指令: $f"; grep -nE 'curl|wget|/tmp/|base64 -d|eval' "$f" | sed 's/^/        /' | tee -a "$REPORT"; }
done
for h in $HOMES; do
    for rc in "$h/.bashrc" "$h/.bash_profile" "$h/.profile" "$h/.zshrc"; do
        [ -f "$rc" ] || continue
        grep -nE 'curl.*\|.*sh|wget.*\|.*sh|/tmp/[a-z0-9]{4,}|base64 -d|eval.*\$\(' "$rc" 2>/dev/null | sed "s|^|        $rc: |" | while read -r l; do hit "shell rc 注入: $l"; done
    done
done

# 3d. ld.so.preload (rootkit 常用)
log "  -- /etc/ld.so.preload (rootkit 注入點) --"
if [ -s /etc/ld.so.preload ]; then
    hit "/etc/ld.so.preload 非空 (高度可疑):"; cat /etc/ld.so.preload 2>/dev/null | sed 's/^/        /' | tee -a "$REPORT"
else
    ok "/etc/ld.so.preload 為空或不存在"
fi

# =====================================================================
hdr "4. SSH 橫向移動跡證 (你提到攻擊會用 SSH key 跳 AWS)"
# =====================================================================
for h in $HOMES; do
    ak="$h/.ssh/authorized_keys"
    if [ -f "$ak" ]; then
        log "  -- $ak --"
        cat "$ak" 2>/dev/null | grep -vE '^\s*#|^\s*$' | sed 's/^/        /' | tee -a "$REPORT"
        warn "請逐行確認以上每把 key 都是你認得的;不認得的立即移除"
    fi
    # 私鑰是否沒有 passphrase (可直接被攻擊者使用)
    for key in "$h"/.ssh/id_* "$h"/.ssh/*.pem; do
        [ -f "$key" ] || continue
        case "$key" in *.pub) continue;; esac
        if head -3 "$key" 2>/dev/null | grep -q "PRIVATE KEY" && ! grep -q "ENCRYPTED\|DEK-Info\|bcrypt" "$key" 2>/dev/null; then
            hit "未加密(無 passphrase)的私鑰: $key  ← 外洩即可直接登入,建議重設並加長 passphrase"
        fi
    done
done
# SSH known_hosts:看曾連往哪些主機(橫向移動目標線索)
log "  -- 各家目錄 known_hosts 曾連線主機數 (橫向移動範圍參考) --"
for h in $HOMES; do
    kh="$h/.ssh/known_hosts"
    [ -f "$kh" ] && note "$kh : $(grep -cvE '^\s*$' "$kh" 2>/dev/null) 筆"
done

# =====================================================================
hdr "5. 對外網路連線 (外洩 / 礦池)"
# =====================================================================
if require_cmd ss; then
    log "  -- 已建立的對外連線 --"
    ss -tnp 2>/dev/null | grep ESTAB | grep -vE '127\.0\.0\.1|::1|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.' | head -40 | tee -a "$REPORT"
elif require_cmd netstat; then
    netstat -tnp 2>/dev/null | grep ESTABLISHED | grep -vE '127\.0\.0\.1|::1' | head -40 | tee -a "$REPORT"
fi
# 監聽中的非預期埠
log "  -- 監聽中的埠 --"
(ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null) | head -30 | tee -a "$REPORT"

# =====================================================================
hdr "6. npm / Node 供應鏈跡證"
# =====================================================================
# 6a. npm debug log (記錄安裝行為)
for h in $HOMES; do
    logdir="$h/.npm/_logs"
    [ -d "$logdir" ] || continue
    log "  -- $logdir 近期紀錄 --"
    ls -lt "$logdir" 2>/dev/null | head -6 | sed 's/^/        /' | tee -a "$REPORT"
done
# 6b. 已知惡意/被攻陷套件 IOC (代表性清單,非完整)
log "  -- 已知遭攻陷 npm 套件比對 (★版本感知:只比對到惡意版本才告警) --"
# 格式:套件名|惡意版本(逗號分隔)。只有「裝到這些版本」才是真的中標;
# 同名套件的乾淨版本(多數情況)不會誤報。清單為代表性,非窮舉。
IOC_DB='node-ipc|9.2.2,10.1.1,10.1.2,11.0.0,11.1.0
event-stream|3.3.6
flatmap-stream|0.1.1
eslint-scope|3.7.2
ua-parser-js|0.7.29,0.8.0,1.0.0
coa|2.0.3,2.0.4
rc|1.2.9,1.3.9,2.3.9
@ctrl/tinycolor|4.1.1,4.1.2'

pkg_ver() {
    local pj="$1/package.json"
    [ -f "$pj" ] || return 1
    if command -v jq >/dev/null 2>&1; then
        jq -r '.version // empty' "$pj" 2>/dev/null
    else
        grep -m1 -E '^[[:space:]]*"version"[[:space:]]*:' "$pj" 2>/dev/null | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
    fi
}

ioc_results=$(for h in $HOMES; do
    while IFS='|' read -r pkg bad; do
        [ -z "$pkg" ] && continue
        while IFS= read -r d; do
            [ -z "$d" ] && continue
            v=$(pkg_ver "$d"); [ -z "$v" ] && continue
            echo ",$bad," | grep -q ",$v," && echo "$pkg|$v|$d"
        done < <(find "$h" -maxdepth 8 -type d -path "*/node_modules/$pkg" 2>/dev/null)
    done <<EOF
$IOC_DB
EOF
done)
if [ -n "$ioc_results" ]; then
    while IFS='|' read -r pkg v d; do
        [ -n "$pkg" ] && hit "惡意版本 $pkg@$v: $d"
    done <<< "$ioc_results"
else
    ok "未發現已知惡意版本(已比對實際版本,非僅比對名稱)"
fi
# 6c. node_modules 內帶 install 腳本 + 可疑外洩行為的套件
log "  -- 含 preinstall/postinstall 且引用敏感環境變數的套件 (人工複查) --"
for h in $HOMES; do
    find "$h" -maxdepth 8 -type f -name package.json -path '*/node_modules/*' 2>/dev/null | head -2000 | while read -r pj; do
        if grep -qE '"(pre|post)install"\s*:' "$pj" 2>/dev/null; then
            dir=$(dirname "$pj")
            if grep -rqiE 'process\.env\.(AWS|GITHUB|NPM_TOKEN|SSH|HOME).{0,40}(http|net|child_process)|os\.homedir\(\).{0,40}ssh|/\.aws/|/\.ssh/' "$dir" --include='*.js' 2>/dev/null; then
                warn "可疑安裝腳本+敏感存取: $dir"
            fi
        fi
    done
done
ok "(6b/6c 若無紅色項目,代表未命中已知 IOC;但新型變種未必在清單內)"

# =====================================================================
hdr "7. Shell 歷史:下載執行 / 編碼混淆"
# =====================================================================
for h in $HOMES; do
    for hist in "$h/.bash_history" "$h/.zsh_history" "$h/.local/share/fish/fish_history" "$h/.node_repl_history"; do
        [ -f "$hist" ] || continue
        m=$(grep -aiE 'curl.*\|.*(ba)?sh|wget.*\|.*(ba)?sh|/tmp/[a-z0-9]{4,}|base64\s+-d|eval\s+.*\$\(|chmod\s+\+x\s+/tmp' "$hist" 2>/dev/null)
        if [ -n "$m" ]; then
            hit "$hist 含下載執行/混淆指令:"; echo "$m" | tail -15 | sed 's/^/        /' | tee -a "$REPORT"
        fi
    done
done
ok "(若無紅色項目代表歷史無明顯下載執行痕跡;但攻擊可能清過 history)"

# =====================================================================
hdr "8. 套件管理器 / auth 日誌 (攻擊者較難清的旁證)"
# =====================================================================
log "  -- 近期套件安裝 (apt/dnf/apk) --"
[ -f /var/log/dpkg.log ] && grep " install " /var/log/dpkg.log 2>/dev/null | tail -15 | sed 's/^/        /' | tee -a "$REPORT"
[ -f /var/log/dnf.log ] && tail -15 /var/log/dnf.log 2>/dev/null | sed 's/^/        /' | tee -a "$REPORT"
log "  -- 近期成功的 SSH 登入 (橫向移動跡象) --"
( grep -hE 'Accepted (password|publickey)' /var/log/auth.log* /var/log/secure* 2>/dev/null | tail -20 || \
  journalctl -u ssh -u sshd --no-pager 2>/dev/null | grep Accepted | tail -20 ) | sed 's/^/        /' | tee -a "$REPORT"

# =====================================================================
hdr "9. 近期新建/異動的可執行檔 (家目錄 + 系統路徑)"
# =====================================================================
log "  -- 近 14 天家目錄中新建的可執行檔 (排除 node_modules/.git) --"
for h in $HOMES; do
    find "$h" -maxdepth 6 -type f -perm -u+x -mtime -14 \
        ! -path '*/node_modules/*' ! -path '*/.git/*' ! -path '*/.cache/*' 2>/dev/null | head -30 | sed 's/^/        /' | tee -a "$REPORT"
done

# =====================================================================
hdr "結論"
# =====================================================================
if [ "$FINDINGS" -eq 0 ]; then
    log "${GRN}本次掃描未命中明確的 [!! 可疑] 指標。${NC}"
    log "${YEL}但這不代表沒中標 — 此類攻擊會自刪證據。仍請:${NC}"
else
    log "${RED}共命中 $FINDINGS 個可疑指標,請逐項複查上方紅色項目。${NC}"
fi
log "  1. 假設此機所有金鑰/token 已外洩,全部輪換 (SSH/雲端/GitHub/API/錢包)"
log "  2. 查雲端側日誌 (AWS CloudTrail / GitHub Security log) — 攻擊者刪不掉"
log "  3. 真要確認乾淨,最保險是重灌此機,並用隔離環境 (VM/Docker) 重建開發環境"
log "\n完整報告已存到: ${CYN}$REPORT${NC}"
