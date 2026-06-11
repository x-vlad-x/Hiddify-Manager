source ../common/utils.sh

apply_hiddifypanel_runtime_compat_patches() {
    local crypto_file

    crypto_file="$(hiddifypanel_path)/hutils/crypto.py"
    if [ ! -f "$crypto_file" ]; then
        warning "Skipping hiddifypanel runtime compatibility patch because $crypto_file was not found."
        return 0
    fi

    if grep -Fq '"dsa", "ecdsa", "ed25519", "rsa"' "$crypto_file"; then
        sed -i 's/"dsa", "ecdsa", "ed25519", "rsa"/"ecdsa", "ed25519", "rsa"/' "$crypto_file"
        warning "Patched hiddifypanel SSH host key generation to skip deprecated DSA keys."
    fi
}

activate_python_venv
install_package wireguard libev-dev libevdev2 default-libmysqlclient-dev build-essential pkg-config ssh
mkdir -p ../log/system

# Fresh installs need the panel package and template deps before config rendering.
install_pypi_package pip setuptools wheel jinja2 json5
if ! is_installed_pypi_package hiddifypanel; then
    install_pypi_package hiddifypanel
fi
apply_hiddifypanel_runtime_compat_patches

useradd -m hiddify-panel -s /bin/bash >/dev/null 2>&1
usermod -aG hiddify-common hiddify-panel

echo -n "" >> ../log/system/panel.log
chown hiddify-panel ../log/system/panel.log
chsh hiddify-panel -s /bin/bash

chown -R hiddify-panel:hiddify-panel /home/hiddify-panel/ >/dev/null 2>&1
localectl set-locale LANG=C.UTF-8 >/dev/null 2>&1
su hiddify-panel -c update-locale LANG=C.UTF-8 >/dev/null 2>&1
chown -R hiddify-panel:hiddify-panel . >/dev/null 2>&1
# activate venv for hiddify-panel user
if ! grep -Fxq "source /opt/hiddify-manager/.venv313/bin/activate" "/home/hiddify-panel/.bashrc" && ! grep -Fxq "export PATH=/opt/hiddify-manager/.venv313/bin:\$PATH" "/home/hiddify-panel/.bashrc"; then
    echo "source /opt/hiddify-manager/.venv313/bin/activate" >> "/home/hiddify-panel/.bashrc"
    echo "export PATH=/opt/hiddify-manager/.venv313/bin:\$PATH" >> "/home/hiddify-panel/.bashrc"
fi


ln -sf $(pwd)/hiddify-panel.service /etc/systemd/system/hiddify-panel.service
systemctl enable hiddify-panel.service

ln -sf $(pwd)/hiddify-panel-background-tasks.service /etc/systemd/system/hiddify-panel-background-tasks.service
systemctl enable hiddify-panel-background-tasks.service

if [ -n "$HIDDIFY_PANLE_SOURCE_DIR" ]; then
    echo "NOTICE: building hiddifypanel package from source..."
    echo "NOTICE: the source dir $HIDDIFY_PANLE_SOURCE_DIR"
    uv pip install -e "$HIDDIFY_PANLE_SOURCE_DIR"
    apply_hiddifypanel_runtime_compat_patches
fi

rm -rf /etc/cron.d/{hiddify_usage_update,hiddify_auto_backup}
# echo "*/1 * * * * root $(pwd)/update_usage.sh" >/etc/cron.d/hiddify_usage_update
# echo "0 */6 * * * hiddify-panel $(pwd)/backup.sh" >/etc/cron.d/hiddify_auto_backup
service cron reload >/dev/null 2>&1


##### download videos

if [[ ! -e "GeoLite2-ASN.mmdb" || $(find "GeoLite2-ASN.mmdb" -mtime +1) ]]; then
    curl --connect-timeout 10 -sL -o GeoLite2-ASN.mmdb1 https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb && mv GeoLite2-ASN.mmdb1 GeoLite2-ASN.mmdb
fi
if [[ ! -e "GeoLite2-Country.mmdb" || $(find "GeoLite2-Country.mmdb" -mtime +1) ]]; then
    curl --connect-timeout 10 -sL -o GeoLite2-Country.mmdb1 https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb && mv GeoLite2-Country.mmdb1 GeoLite2-Country.mmdb
fi

# bash download_yt.sh &
