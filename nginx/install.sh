source ../common/utils.sh
checkOS || exit 1
hiddify_assert_nginx_repo_supported || exit 1
NGINX_CANDIDATE=$(hiddify_get_apt_candidate "nginx")
NGINX_BRANCH=$(hiddify_extract_major_minor_version "$NGINX_CANDIDATE")
if [[ "$(vercomp "$NGINX_BRANCH" "1.26")" == "2" ]]; then
    error "The available nginx candidate ($NGINX_CANDIDATE) is below the supported minimum branch 1.26."
    exit 1
fi

if ! is_installed_package "nginx"; then
    useradd nginx >/dev/null 2>&1 || true
    curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor |
        sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
    https://nginx.org/packages/ubuntu ${HIDDIFY_OS_VERSION_CODENAME} nginx" |
        sudo tee /etc/apt/sources.list.d/nginx.list
    sudo apt update -y

fi
install_package "nginx"

systemctl kill nginx >/dev/null 2>&1
systemctl disable nginx >/dev/null 2>&1
systemctl kill apache2 >/dev/null 2>&1
systemctl disable apache2 >/dev/null 2>&1
# pkill -9 nginx

rm /etc/nginx/conf.d/web.conf >/dev/null 2>&1
rm /etc/nginx/sites-available/default >/dev/null 2>&1
rm /etc/nginx/sites-enabled/default >/dev/null 2>&1
rm /etc/nginx/conf.d/default.conf >/dev/null 2>&1
rm /etc/nginx/conf.d/xray-base.conf >/dev/null 2>&1
rm /etc/nginx/conf.d/speedtest.conf >/dev/null 2>&1

mkdir -p run
ln -sf $(pwd)/hiddify-nginx.service /etc/systemd/system/hiddify-nginx.service
systemctl enable hiddify-nginx.service
