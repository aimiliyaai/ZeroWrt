#!/bin/bash -e
export RED_COLOR='\e[1;31m'
export GREEN_COLOR='\e[1;32m'
export YELLOW_COLOR='\e[1;33m'
export BLUE_COLOR='\e[1;34m'
export PINK_COLOR='\e[1;35m'
export SHAN='\e[1;33;5m'
export RES='\e[0m'

GROUP=
group() {
    endgroup
    echo "::group::  $1"
    GROUP=1
}
endgroup() {
    if [ -n "$GROUP" ]; then
        echo "::endgroup::"
    fi
    GROUP=
}

#####################################
#        OpenWrt Build Script       #
#####################################

# Check root
if [ "$(id -u)" = "0" ]; then
    export FORCE_UNSAFE_CONFIGURE=1 FORCE=1
fi

# Start time
starttime=`date +'%Y-%m-%d %H:%M:%S'`
CURRENT_DATE=$(date +%s)

# Cpus
cores=`expr $(nproc --all) + 1`

# $CURL_BAR
if curl --help | grep progress-bar >/dev/null 2>&1; then
    CURL_BAR="--progress-bar";
fi

SUPPORTED_BOARDS="rockchip x86_64"
if [ -z "$1" ] || ! echo "$SUPPORTED_BOARDS" | grep -qw "$2"; then
    echo -e "\n${RED_COLOR}Building type not specified or unsupported board: '$2'.${RES}\n"
    echo -e "Usage:\n"

    for board in $SUPPORTED_BOARDS; do
        echo -e "$board releases: ${GREEN_COLOR}bash build.sh v24 $board${RES}"
        echo -e "$board snapshots: ${GREEN_COLOR}bash build.sh openwrt-24.10 $board${RES}"
    done
    echo
    exit 1
fi

# Source branch
if [ "$1" = "dev" ]; then
    export branch=openwrt-24.10
    export version=dev
elif [ "$1" = "v24" ]; then
    # 使用最新的稳定版本
    export branch=openwrt-24.10
    export version=v24
else
    export branch=$1
    export version=$1
fi

# lan
[ -n "$LAN" ] && export LAN=$LAN || export LAN=192.168.1.1

# platform
case "$2" in
    rockchip)
        platform="rockchip"
        toolchain_arch="aarch64_generic"
        ;;
    x86_64)
        platform="x86_64"
        toolchain_arch="x86_64"
        ;;
esac
export platform toolchain_arch

# gcc version (使用官方默认)
export gcc_version=13

# build.sh flags
export \
    ENABLE_BPF=$ENABLE_BPF \
    ROOT_PASSWORD=$ROOT_PASSWORD

# print version
echo -e "\r\n${GREEN_COLOR}Building $branch${RES}\r\n"
case "$platform" in
    x86_64)
        echo -e "${GREEN_COLOR}Model: x86_64${RES}"
        ;;
    rockchip)
        echo -e "${GREEN_COLOR}Model: rockchip${RES}"
        ;;
esac

# print build opt
echo -e "${GREEN_COLOR}Date: $CURRENT_DATE${RES}\r\n"
echo -e "${GREEN_COLOR}GCC VERSION: $gcc_version${RES}"
print_status() {
    local name="$1"
    local value="$2"
    local true_color="${3:-$GREEN_COLOR}"
    local false_color="${4:-$YELLOW_COLOR}"
    local newline="${5:-}"
    if [ "$value" = "y" ]; then
        echo -e "${GREEN_COLOR}${name}:${RES} ${true_color}true${RES}${newline}"
    else
        echo -e "${GREEN_COLOR}${name}:${RES} ${false_color}false${RES}${newline}"
    fi
}
[ -n "$LAN" ] && echo -e "${GREEN_COLOR}LAN:${RES} $LAN" || echo -e "${GREEN_COLOR}LAN:${RES} 192.168.1.1"
[ -n "$ROOT_PASSWORD" ] \
    && echo -e "${GREEN_COLOR}Default Password:${RES} ${BLUE_COLOR}$ROOT_PASSWORD${RES}" \
    || echo -e "${GREEN_COLOR}Default Password:${RES} (${YELLOW_COLOR}No password${RES})"
echo -e "${GREEN_COLOR}Standard C Library:${RES} ${BLUE_COLOR}musl${RES}"
print_status "ENABLE_BPF"        "$ENABLE_BPF" "$GREEN_COLOR" "$RED_COLOR"
print_status "BUILD_FAST"        "$BUILD_FAST" "$GREEN_COLOR" "$YELLOW_COLOR" "\n"

# clean old files
rm -rf openwrt

# openwrt - releases
[ "$(whoami)" = "runner" ] && group "source code"
git clone --depth=1 https://github.com/openwrt/openwrt.git -b $branch

if [ -d openwrt ]; then
    cd openwrt
else
    echo -e "${RED_COLOR}Failed to download source code${RES}"
    exit 1
fi

# tags
if [ "$1" = "v24" ]; then
    git describe --abbrev=0 --tags > version.txt 2>/dev/null || echo "$branch" > version.txt
else
    echo "$branch" > version.txt
fi

# 使用官方 feeds 配置
echo -e "\n${GREEN_COLOR}Using official feeds...${RES}\n"
# 保持官方默认的 feeds.conf.default 不变

# Init feeds
[ "$(whoami)" = "runner" ] && group "feeds update -a"
./scripts/feeds update -a
[ "$(whoami)" = "runner" ] && endgroup

[ "$(whoami)" = "runner" ] && group "feeds install -a"
./scripts/feeds install -a
[ "$(whoami)" = "runner" ] && endgroup

# loader dl
if [ -f ../dl.gz ]; then
    tar xf ../dl.gz -C .
fi

###############################################
echo -e "\n${GREEN_COLOR}Preparing configuration ...${RES}\n"

# 基础配置 - 针对不同平台
if [ "$platform" = "x86_64" ]; then
    cat > .config <<EOF
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y

# 文件系统
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_TARGET_EXT4_RESERVED_PCT=0
CONFIG_TARGET_EXT4_BLOCKSIZE_4K=y
CONFIG_TARGET_ROOTFS_PARTSIZE=512
CONFIG_TARGET_KERNEL_PARTSIZE=64

# 镜像格式
CONFIG_TARGET_IMAGES_GZIP=y
CONFIG_GRUB_IMAGES=y
CONFIG_GRUB_EFI_IMAGES=y
CONFIG_VDI_IMAGES=y
CONFIG_VMDK_IMAGES=y

# 网络
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl=y
CONFIG_PACKAGE_luci-app-firewall=y
CONFIG_PACKAGE_luci-app-adblock=y
CONFIG_PACKAGE_luci-app-ddns=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-app-sqm=y
CONFIG_PACKAGE_luci-app-nlbwmon=y

# 基础软件包
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_wget-ssl=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_iperf3=y
CONFIG_PACKAGE_tcpdump=y
CONFIG_PACKAGE_ethtool=y

# USB 支持
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-usb2=y
CONFIG_PACKAGE_kmod-usb3=y
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-fs-ntfs3=y
CONFIG_PACKAGE_kmod-fs-vfat=y
CONFIG_PACKAGE_block-mount=y

# 无线支持
CONFIG_PACKAGE_kmod-cfg80211=y
CONFIG_PACKAGE_kmod-mac80211=y
CONFIG_PACKAGE_wpad-openssl=y
CONFIG_PACKAGE_hostapd-common=y
CONFIG_PACKAGE_iw=y
CONFIG_PACKAGE_iwinfo=y

# PPP 支持
CONFIG_PACKAGE_ppp=y
CONFIG_PACKAGE_ppp-mod-pppoe=y
CONFIG_PACKAGE_kmod-pppoe=y

EOF

elif [ "$platform" = "rockchip" ]; then
    cat > .config <<EOF
CONFIG_TARGET_rockchip=y
CONFIG_TARGET_rockchip_armv8=y
CONFIG_TARGET_MULTI_PROFILE=y

# 选择支持的设备
CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_friendlyarm_nanopi-r2c=y
CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_friendlyarm_nanopi-r2s=y
CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_friendlyarm_nanopi-r4s=y
CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_friendlyarm_nanopi-r5c=y
CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_friendlyarm_nanopi-r5s=y
CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_friendlyarm_nanopi-r6c=y
CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_friendlyarm_nanopi-r6s=y
CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_radxa_rock-5a=y
CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_radxa_rock-5b=y
CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_xunlong_orangepi-5=y
CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_xunlong_orangepi-5-plus=y

# 文件系统
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_TARGET_EXT4_RESERVED_PCT=0
CONFIG_TARGET_EXT4_BLOCKSIZE_4K=y
CONFIG_TARGET_ROOTFS_PARTSIZE=512

# 镜像格式
CONFIG_TARGET_IMAGES_GZIP=y

# 网络
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl=y
CONFIG_PACKAGE_luci-app-firewall=y
CONFIG_PACKAGE_luci-app-adblock=y
CONFIG_PACKAGE_luci-app-ddns=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-app-sqm=y
CONFIG_PACKAGE_luci-app-nlbwmon=y

# 基础软件包
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_wget-ssl=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_iperf3=y
CONFIG_PACKAGE_tcpdump=y
CONFIG_PACKAGE_ethtool=y

# USB 支持
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-usb2=y
CONFIG_PACKAGE_kmod-usb3=y
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-fs-ntfs3=y
CONFIG_PACKAGE_kmod-fs-vfat=y
CONFIG_PACKAGE_block-mount=y

# 无线支持
CONFIG_PACKAGE_kmod-cfg80211=y
CONFIG_PACKAGE_kmod-mac80211=y
CONFIG_PACKAGE_wpad-openssl=y
CONFIG_PACKAGE_hostapd-common=y
CONFIG_PACKAGE_iw=y
CONFIG_PACKAGE_iwinfo=y

# PPP 支持
CONFIG_PACKAGE_ppp=y
CONFIG_PACKAGE_ppp-mod-pppoe=y
CONFIG_PACKAGE_kmod-pppoe=y

EOF
fi

# 通用配置
cat >> .config <<EOF

# 语言包
CONFIG_LUCI_LANG_zh_Hans=y

# 主题
CONFIG_PACKAGE_luci-theme-bootstrap=y

# SSL 证书
CONFIG_PACKAGE_ca-certificates=y

# 时间同步
CONFIG_PACKAGE_ntpd=y

# IPv6 支持
CONFIG_PACKAGE_ipv6helper=y
CONFIG_PACKAGE_odhcp6c=y
CONFIG_PACKAGE_odhcpd-ipv6only=y

# 防火墙增强
CONFIG_PACKAGE_iptables-mod-extra=y
CONFIG_PACKAGE_iptables-mod-nat-extra=y

# 网络工具
CONFIG_PACKAGE_dnsmasq-full=y
CONFIG_PACKAGE_dropbear=y

EOF

# BPF 支持
if [ "$ENABLE_BPF" = "y" ]; then
    cat >> .config <<EOF

# BPF 支持
CONFIG_KERNEL_BPF=y
CONFIG_KERNEL_XDP_SOCKETS=y
CONFIG_PACKAGE_kmod-xdp-sockets-diag=y
CONFIG_BPF_TOOLCHAIN_HOST=y

EOF
fi

# 设置密码
if [ -n "$ROOT_PASSWORD" ]; then
    echo "CONFIG_TARGET_PREINIT_DISABLE_FAILSAFE=y" >> .config
    echo "CONFIG_TARGET_PREINIT_SUPPRESS_STDERR=y" >> .config
fi

# 移除一些不需要的包来减小体积
cat >> .config <<EOF

# 移除一些默认包
# CONFIG_PACKAGE_ppp is not set
# CONFIG_PACKAGE_ppp-mod-pppoe is not set

EOF

# 自定义网络配置
if [ -n "$LAN" ] && [ "$LAN" != "192.168.1.1" ]; then
    mkdir -p files/etc/config
    cat > files/etc/config/network <<EOF
config interface 'loopback'
        option ifname 'lo'
        option proto 'static'
        option ipaddr '127.0.0.1'
        option netmask '255.0.0.0'

config globals 'globals'
        option ula_prefix 'fd12:3456:789a::/48'

config interface 'lan'
        option type 'bridge'
        option ifname 'eth0'
        option proto 'static'
        option ipaddr '$LAN'
        option netmask '255.255.255.0'
        option ip6assign '60'

EOF
fi

# 设置root密码
if [ -n "$ROOT_PASSWORD" ]; then
    mkdir -p files/etc
    echo "root:$(openssl passwd -1 "$ROOT_PASSWORD")" > files/etc/shadow
fi

# init openwrt config
rm -rf tmp/*
if [ "$BUILD" = "n" ]; then
    exit 0
else
    make defconfig
fi

# Compile
echo -e "\r\n${GREEN_COLOR}Building OpenWrt ...${RES}\r\n"
make -j$cores || make -j1 V=s

# Compile time
endtime=`date +'%Y-%m-%d %H:%M:%S'`
start_seconds=$(date --date="$starttime" +%s);
end_seconds=$(date --date="$endtime" +%s);
SEC=$((end_seconds-start_seconds));

if [ -f bin/targets/*/*/sha256sums ]; then
    echo -e "${GREEN_COLOR} Build success! ${RES}"
    echo -e " Build time: $(( SEC / 3600 ))h,$(( (SEC % 3600) / 60 ))m,$(( (SEC % 3600) % 60 ))s"
    
    # 显示生成的文件
    echo -e "\n${GREEN_COLOR}Generated files:${RES}"
    find bin/targets -name "*.img.gz" -o -name "*.bin" -o -name "*.ubi" | head -10
else
    echo -e "\n${RED_COLOR} Build error... ${RES}"
    echo -e " Build time: $(( SEC / 3600 ))h,$(( (SEC % 3600) / 60 ))m,$(( (SEC % 3600) % 60 ))s"
    echo
    exit 1
fi

echo -e "\n${GREEN_COLOR}Build completed successfully!${RES}"
echo -e "Firmware images are located in: ${BLUE_COLOR}bin/targets/*/64/${RES}"
