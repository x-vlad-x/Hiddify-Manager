source /opt/hiddify-manager/common/utils.sh

if [[ "$(hiddify_get_apt_candidate "simple-obfs")" == "(none)" || -z "$(hiddify_get_apt_candidate "simple-obfs")" ]]; then
    warning "simple-obfs is not available on this Ubuntu release. Skipping ss-faketls installation."
    exit 0
fi

install_package shadowsocks-libev simple-obfs
chmod 600 *.service*
ln -sf $(pwd)/hiddify-ss-faketls.service /etc/systemd/system/hiddify-ss-faketls.service
systemctl disable --now ss-faketls.service > /dev/null 2>&1
rm ss-faketls.service* > /dev/null 2>&1
