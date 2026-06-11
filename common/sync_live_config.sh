#!/bin/bash
set -euo pipefail

cd /opt/hiddify-manager
source ./common/utils.sh

LOCK_FILE="/run/hiddify-live-config-sync.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    exit 0
fi

TMP_FILE="$(mktemp /tmp/hiddify-live-config.XXXXXX.json)"
trap 'rm -f "$TMP_FILE"' EXIT

if ! hiddify-panel-cli all-configs >"$TMP_FILE" 2>/dev/null; then
    exit 0
fi

chmod 600 "$TMP_FILE"

current_file="/opt/hiddify-manager/current.json"
live_signature="$(jq -cS '{domains: [.domains[]? | {domain, mode, sub_link_only, child_id, need_valid_ssl}], panel_links, admin_path, api_path}' "$TMP_FILE" 2>/dev/null || true)"
current_signature=""
if [ -f "$current_file" ]; then
    current_signature="$(jq -cS '{domains: [.domains[]? | {domain, mode, sub_link_only, child_id, need_valid_ssl}], panel_links, admin_path, api_path}' "$current_file" 2>/dev/null || true)"
fi

needs_apply=0
if [ -z "$current_signature" ] || [ "$live_signature" != "$current_signature" ]; then
    needs_apply=1
fi

while IFS=$'\t' read -r domain mode need_valid_ssl; do
    [ -z "$domain" ] && continue
    cert="/opt/hiddify-manager/ssl/${domain:0:64}.crt"

    if [ ! -f "$cert" ]; then
        needs_apply=1
        break
    fi

    if [ "$need_valid_ssl" = "true" ]; then
        if [[ "$domain" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            if ! openssl x509 -in "$cert" -noout -checkip "$domain" >/dev/null 2>&1; then
                needs_apply=1
                break
            fi
        else
            if ! openssl x509 -in "$cert" -noout -checkhost "$domain" >/dev/null 2>&1; then
                needs_apply=1
                break
            fi
        fi
    fi
done < <(jq -r '.domains[]? | select(.mode | IN("direct", "relay", "old_xtls_direct", "sub_link_only")) | [.domain, .mode, (.need_valid_ssl | tostring)] | @tsv' "$TMP_FILE")

mv "$TMP_FILE" "$current_file"
trap - EXIT

if [ "$needs_apply" -eq 1 ]; then
    echo "Detected live config drift or certificate mismatch. Applying configs..."
    bash /opt/hiddify-manager/apply_configs.sh --no-gui --no-log
fi
