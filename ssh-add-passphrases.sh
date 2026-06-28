#!/usr/bin/env bash
#
# ssh-add-passphrases.sh — 互動式幫 ~/.ssh 下「沒加 passphrase」的私鑰補上 passphrase
#
# 重要:
#  - 加 passphrase 不會改變公鑰,不影響任何伺服器端設定(只加密本機私鑰檔)。
#  - 但對「已外洩」的 key 加 passphrase 無效 —— 攻擊者已有未加密副本。
#    曾在受害機上的 key 應「重新產生 + 換掉伺服器公鑰」,而非只加 passphrase。
#  - 本腳本為互動式:會逐把呼叫 ssh-keygen -p,由你親自輸入新密碼(不經過腳本)。
#
# 用法(請在你自己的終端機執行,需要 TTY 輸入密碼):
#   chmod +x ssh-add-passphrases.sh
#   ./ssh-add-passphrases.sh            # 處理所有沒加密的 key
#   ./ssh-add-passphrases.sh --dry-run  # 只列出哪些沒加密,不動作
#
set -o pipefail   # 不用 -u:相容 macOS 內建 bash 3.2 的空陣列展開
SSHDIR="${HOME}/.ssh"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; CYN='\033[0;36m'; NC='\033[0m'

[ -d "$SSHDIR" ] || { echo "找不到 $SSHDIR"; exit 1; }

is_private_key() { head -3 "$1" 2>/dev/null | grep -q "PRIVATE KEY"; }
has_passphrase() {
    # 舊格式靠標頭;新 OpenSSH 格式靠「空密碼能否解開」判斷
    grep -qE 'ENCRYPTED|DEK-Info|bcrypt' "$1" 2>/dev/null && return 0
    ssh-keygen -y -P "" -f "$1" >/dev/null 2>&1 && return 1 || return 0
}

# 蒐集 ~/.ssh 下所有私鑰(去重,排除 .pub/known_hosts/config);bash 3.2 相容
KEYS=()
while IFS= read -r f; do
    [ -n "$f" ] && KEYS+=("$f")
done < <(find "$SSHDIR" -maxdepth 1 -type f \
    ! -name '*.pub' ! -name 'known_hosts*' ! -name 'config' ! -name 'authorized_keys' \
    2>/dev/null | sort -u)

unenc=()
echo -e "${CYN}=== 掃描 $SSHDIR 私鑰 ===${NC}"
for k in "${KEYS[@]:-}"; do
    [ -z "$k" ] && continue
    is_private_key "$k" || continue
    if has_passphrase "$k"; then
        echo -e "🔒 已加密       $k"
    else
        echo -e "${YEL}🔓 無 passphrase $k${NC}"
        unenc+=("$k")
    fi
done

if [ "${#unenc[@]}" -eq 0 ]; then
    echo -e "\n${GRN}全部私鑰都有 passphrase,無需處理。${NC}"; exit 0
fi

echo -e "\n共 ${#unenc[@]} 把沒加 passphrase。"
if [ "$DRY" -eq 1 ]; then
    echo "(--dry-run:不做任何修改)"; exit 0
fi

echo -e "${RED}提醒:曾在受害機上的 key 應改用「重新產生」,加 passphrase 對已外洩的 key 無效。${NC}"
read -r -p "要現在逐把加 passphrase 嗎?(y/N) " ans
[ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "已取消。"; exit 0; }

for k in "${unenc[@]}"; do
    echo -e "\n${CYN}--- 處理 $k ---${NC}"
    echo "  (舊密碼是空的,提示輸入 Old passphrase 時直接 Enter;新密碼建議 15 碼以上)"
    # 唯讀的 key(常見於 chmod 400 的 .pem)ssh-keygen 寫不回去,暫時開寫入權限
    origmode=$(stat -f '%Lp' "$k" 2>/dev/null || stat -c '%a' "$k" 2>/dev/null)
    chmod u+w "$k" 2>/dev/null
    # -p 修改 passphrase;由 ssh-keygen 自行向 TTY 要密碼,腳本不接觸密碼
    if ssh-keygen -p -f "$k"; then
        chmod 600 "$k" 2>/dev/null   # 加密後收斂到安全權限
        echo -e "  ${GRN}✓ 已加上 passphrase (權限設為 600)${NC}"
    else
        # 還原原始權限,避免改壞
        [ -n "$origmode" ] && chmod "$origmode" "$k" 2>/dev/null
        echo -e "  ${RED}✗ 失敗(密碼不符 / 舊密碼非空 / 格式問題)${NC}"
    fi
done

echo -e "\n${GRN}完成。${NC}"
echo "建議把常用 key 存進 macOS keychain,之後免每次輸入:"
echo "    ssh-add --apple-use-keychain ~/.ssh/id_ed25519"
echo "並在 ~/.ssh/config 加:"
echo "    Host *"
echo "        UseKeychain yes"
echo "        AddKeysToAgent yes"
