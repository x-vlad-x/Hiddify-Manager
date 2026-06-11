source ../common/utils.sh
rm -rf *.template
if is_installed sniproxy; then
    # systemctl kill hiddify-sniproxy > /dev/null 2>&1
    systemctl stop hiddify-sniproxy >/dev/null 2>&1
    systemctl disable hiddify-sniproxy >/dev/null 2>&1
    pkill -9 sniproxy >/dev/null 2>&1
fi

checkOS || exit 1

HAPROXY_SOURCE=$(hiddify_resolve_haproxy_source) || exit 1
HAPROXY_INSTALL_MODE=$(echo "$HAPROXY_SOURCE" | cut -d'|' -f 1)
HAPROXY_VERSION=$(echo "$HAPROXY_SOURCE" | cut -d'|' -f 2)

if [[ "$HAPROXY_INSTALL_MODE" == "ppa" ]]; then
    if ! is_installed_package "haproxy=${HAPROXY_VERSION}"; then
        echo "Adding PPA for haproxy-${HAPROXY_VERSION}"
        add-apt-repository -y "ppa:vbernat/haproxy-${HAPROXY_VERSION}"
        if [ $? -ne 0 ]; then
            add-apt-repository -y "ppa:vbernat/haproxy-${HAPROXY_VERSION}"
        fi
        echo "Installing haproxy ${HAPROXY_VERSION} from PPA"
        install_package "haproxy=${HAPROXY_VERSION}.*"
    else
        echo "haproxy ${HAPROXY_VERSION} is already installed from PPA"
    fi
else
    if ! is_installed_package "haproxy=${HAPROXY_VERSION}"; then
        echo "Installing distro haproxy ${HAPROXY_VERSION}"
        install_package "haproxy=${HAPROXY_VERSION}.*"
    else
        echo "haproxy ${HAPROXY_VERSION} is already installed from distro packages"
    fi
fi
systemctl kill haproxy >/dev/null 2>&1
systemctl stop haproxy >/dev/null 2>&1
systemctl disable haproxy >/dev/null 2>&1

ln -sf $(pwd)/hiddify-haproxy.service /etc/systemd/system/hiddify-haproxy.service
systemctl enable hiddify-haproxy.service
