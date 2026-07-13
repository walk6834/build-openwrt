#!/bin/bash

# 打包toolchain目录
if [[ "$REBUILD_TOOLCHAIN" = 'true' ]]; then
    cd $OPENWRT_PATH
    sed -i 's/ $(tool.*\/stamp-compile)//' Makefile
    if [[ -d ".ccache" && $(du -s .ccache | cut -f1) -gt 0 ]]; then
        echo "🔍 缓存目录大小:"
        du -h --max-depth=1 .ccache
        ccache_dir=".ccache"
    fi
    echo "📦 工具链目录大小:"
    du -h --max-depth=1 staging_dir
    tar -I zstdmt -cf "$GITHUB_WORKSPACE/output/$CACHE_NAME.tzst" staging_dir/host* staging_dir/tool* $ccache_dir
    echo "📁 输出目录内容:"
    ls -lh "$GITHUB_WORKSPACE/output"
    if [[ ! -e "$GITHUB_WORKSPACE/output/$CACHE_NAME.tzst" ]]; then
        echo "❌ 工具链打包失败!"
        exit 1
    fi
    echo "✅ 工具链打包完成"
    exit 0
fi

# 创建toolchain缓存保存目录
[ -d "$GITHUB_WORKSPACE/output" ] || mkdir "$GITHUB_WORKSPACE/output"

# 颜色输出
color() {
    case "$1" in
        cr) echo -e "\e[1;31m${2}\e[0m" ;;  # 红色
        cg) echo -e "\e[1;32m${2}\e[0m" ;;  # 绿色
        cy) echo -e "\e[1;33m${2}\e[0m" ;;  # 黄色
        cb) echo -e "\e[1;34m${2}\e[0m" ;;  # 蓝色
        cp) echo -e "\e[1;35m${2}\e[0m" ;;  # 紫色
        cc) echo -e "\e[1;36m${2}\e[0m" ;;  # 青色
        cw) echo -e "\e[1;37m${2}\e[0m" ;;  # 白色
    esac
}

# 状态显示和时间统计
status_info() {
    local task_name="$1" begin_time=$(date +%s) exit_code time_info
    shift
    "$@"
    exit_code=$?
    [[ "$exit_code" -eq 99 ]] && return 0
    if [[ -n "$begin_time" ]]; then
        time_info="==> 用时 $(($(date +%s) - begin_time)) 秒"
    else
        time_info=""
    fi
    if [[ "$exit_code" -eq 0 ]]; then
        printf "%s %-52s %s %s %s %s %s %s %s\n" \
        $(color cy "⏳ $task_name") [ $(color cg ✔) ] $(color cw "$time_info")
    else
        printf "%s %-52s %s %s %s %s %s %s %s\n" \
        $(color cy "⏳ $task_name") [ $(color cr ✖) ] $(color cw "$time_info")
    fi
}

# 查找目录
find_dir() {
    find $1 -maxdepth 3 -type d -name "$2" -print -quit 2>/dev/null
}

# 打印信息
print_info() {
    printf "%s %-40s %s %s %s\n" "$1" "$2" "$3" "$4" "$5"
}

# 添加整个源仓库(git clone)
git_clone() {
    local repo_url branch target_dir current_dir
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    target_dir="${1:-${repo_url##*/}}"
    git clone -q $branch --depth=1 "$repo_url" "$target_dir" 2>/dev/null || {
        print_info $(color cr 拉取) "$repo_url" [ $(color cr ✖) ]
        return 1
    }
    rm -rf $target_dir/{.git*,README*.md,LICENSE}
    current_dir=$(find_dir "package/ feeds/ target/" "$target_dir")
    if [[ -d "$current_dir" ]]; then
        rm -rf "$current_dir"
        mv -f "$target_dir" "${current_dir%/*}"
        print_info $(color cg 替换) "$target_dir" [ $(color cg ✔) ]
    else
        mv -f "$target_dir" "$destination_dir"
        print_info $(color cb 添加) "$target_dir" [ $(color cb ✔) ]
    fi
}

# 添加源仓库内的所有子目录
clone_all() {
    local repo_url branch temp_dir=$(mktemp -d)
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    git clone -q $branch --depth=1 "$repo_url" "$temp_dir" 2>/dev/null || {
        print_info $(color cr 拉取) "$repo_url" [ $(color cr ✖) ]
        rm -rf "$temp_dir"
        return 1
    }
    process_dir() {
        while IFS= read -r source_dir; do
            local target_dir=$(basename "$source_dir")
            local current_dir=$(find_dir "package/ feeds/ target/" "$target_dir")
            if [[ -d "$current_dir" ]]; then
                rm -rf "$current_dir"
                mv -f "$source_dir" "${current_dir%/*}"
                print_info $(color cg 替换) "$target_dir" [ $(color cg ✔) ]
            else
                mv -f "$source_dir" "$destination_dir"
                print_info $(color cb 添加) "$target_dir" [ $(color cb ✔) ]
            fi
        done < <(find "$1" -maxdepth 1 -mindepth 1 -type d ! -name '.*')
    }
    if [[ $# -eq 0 ]]; then
        process_dir "$temp_dir"
    else
        for dir_name in "$@"; do
            [[ -d "$temp_dir/$dir_name" ]] && process_dir "$temp_dir/$dir_name" || \
            print_info $(color cr 目录) "$dir_name" [ $(color cr ✖) ]
        done
    fi
    rm -rf "$temp_dir"
}

# 主流程
main() {
    echo "$(color cp "🚀 开始运行自定义脚本")"
    echo "========================================"

    # 拉取编译源码
    status_info "拉取编译源码" clone_source_code

    # 设置环境变量
    status_info "设置环境变量" set_variable_values

    # 下载部署toolchain缓存
    status_info "下载部署toolchain缓存" download_toolchain

    # 更新&安装插件
    status_info "更新&安装插件" update_install_feeds

    # 添加额外插件
    status_info "添加额外插件" add_custom_packages

    # 加载个人设置
    status_info "加载个人设置" apply_custom_settings

    # 更新配置文件
    status_info "更新配置文件" update_config_file

    # 显示编译信息
    show_build_info

    echo "$(color cp "✅ 自定义脚本运行完成")"
    echo "========================================"
}

# 拉取编译源码
clone_source_code() {
    # 设置编译源码与分支
    REPO_URL="https://github.com/immortalwrt/immortalwrt"
    echo "REPO_URL=$REPO_URL" >> $GITHUB_ENV
    REPO_BRANCH="openwrt-24.10"
    echo "REPO_BRANCH=$REPO_BRANCH" >> $GITHUB_ENV

    # 拉取编译源码
    cd /workdir
    git clone -q -b "$REPO_BRANCH" --single-branch "$REPO_URL" openwrt
    ln -sf /workdir/openwrt $GITHUB_WORKSPACE/openwrt
    [ -d openwrt ] && cd openwrt || exit
    echo "OPENWRT_PATH=$PWD" >> $GITHUB_ENV
}

# 设置环境变量
set_variable_values() {
    local TARGET_NAME SUBTARGET_NAME KERNEL KERNEL_FILE TOOLS_HASH

    # 源仓库与分支
    SOURCE_REPO=$(basename "$REPO_URL")
    echo "SOURCE_REPO=$SOURCE_REPO" >> $GITHUB_ENV
    echo "LITE_BRANCH=${REPO_BRANCH#*-}" >> $GITHUB_ENV

    # 平台架构
    TARGET_NAME=$(grep -oP "^CONFIG_TARGET_\K[a-z0-9]+(?==y)" "$GITHUB_WORKSPACE/$CONFIG_FILE")
    SUBTARGET_NAME=$(grep -oP "^CONFIG_TARGET_${TARGET_NAME}_\K[a-z0-9]+(?==y)" "$GITHUB_WORKSPACE/$CONFIG_FILE")
    DEVICE_TARGET="$TARGET_NAME-$SUBTARGET_NAME"
    echo "DEVICE_TARGET=$DEVICE_TARGET" >> $GITHUB_ENV

    # 内核版本
    KERNEL=$(grep -oP 'KERNEL_PATCHVER:=\K[\d\.]+' "target/linux/$TARGET_NAME/Makefile")
    KERNEL_FILE="include/kernel-$KERNEL"
    [ -e "$KERNEL_FILE" ] || KERNEL_FILE="target/linux/generic/kernel-$KERNEL"
    KERNEL_VERSION=$(grep -oP 'LINUX_KERNEL_HASH-\K[\d\.]+' "$KERNEL_FILE")
    echo "KERNEL_VERSION=$KERNEL_VERSION" >> $GITHUB_ENV

    # toolchain缓存文件名
    TOOLS_HASH=$(git log -1 --pretty=format:"%h" tools toolchain)
    CACHE_NAME="$SOURCE_REPO-${REPO_BRANCH#*-}-$DEVICE_TARGET-cache-$TOOLS_HASH"
    echo "CACHE_NAME=$CACHE_NAME" >> $GITHUB_ENV

    # 源码更新信息
    echo "COMMIT_AUTHOR=$(git show -s --date=short --format="作者: %an")" >> $GITHUB_ENV
    echo "COMMIT_DATE=$(git show -s --date=short --format="时间: %ci")" >> $GITHUB_ENV
    echo "COMMIT_MESSAGE=$(git show -s --date=short --format="内容: %s")" >> $GITHUB_ENV
    echo "COMMIT_HASH=$(git show -s --date=short --format="hash: %H")" >> $GITHUB_ENV
}

# 下载部署toolchain缓存
download_toolchain() {
    local cache_xa cache_xc
    if [[ "$TOOLCHAIN" = 'true' ]]; then
        cache_xa=$(curl -sL "https://api.github.com/repos/$GITHUB_REPOSITORY/releases" | awk -F '"' '/download_url/{print $4}' | grep "$CACHE_NAME")
        cache_xc=$(curl -sL "https://api.github.com/repos/haiibo/toolchain-cache/releases" | awk -F '"' '/download_url/{print $4}' | grep "$CACHE_NAME")
        if [[ "$cache_xa" || "$cache_xc" ]]; then
            wget -qc -t=3 "${cache_xa:-$cache_xc}"
            if [ -e *.tzst ]; then
                tar -I unzstd -xf *.tzst || tar -xf *.tzst
                [ "$cache_xa" ] || (cp *.tzst $GITHUB_WORKSPACE/output && echo "OUTPUT_RELEASE=true" >> $GITHUB_ENV)
                [ -d staging_dir ] && sed -i 's/ $(tool.*\/stamp-compile)//' Makefile
            fi
        else
            echo "REBUILD_TOOLCHAIN=true" >> $GITHUB_ENV
            echo "⚠️ 未找到最新工具链"
            return 99
        fi
    else
        echo "REBUILD_TOOLCHAIN=true" >> $GITHUB_ENV
        return 99
    fi
}

# 更新&安装插件
update_install_feeds() {
    ./scripts/feeds update -a 1>/dev/null 2>&1
    ./scripts/feeds install -a 1>/dev/null 2>&1
}

# 添加额外插件
add_custom_packages() {
    echo "📦 添加额外插件..."

    # 科学上网插件
    clone_all https://github.com/Openwrt-Passwall/openwrt-passwall-packages
    clone_all https://github.com/Openwrt-Passwall/openwrt-passwall
    clone_all https://github.com/nikkinikki-org/OpenWrt-nikki
    clone_all https://github.com/nikkinikki-org/OpenWrt-momo

    # Themes
    git_clone https://github.com/jerrykuku/luci-theme-argon
    git_clone https://github.com/jerrykuku/luci-app-argon-config
}

# 加载个人设置
apply_custom_settings() {
    local drv_path pbuf_path

    [ -e "$GITHUB_WORKSPACE/files" ] && mv "$GITHUB_WORKSPACE/files" files

    # 设置固件rootfs大小
    if [ "$PART_SIZE" ]; then
        sed -i '/ROOTFS_PARTSIZE/d' "$GITHUB_WORKSPACE/$CONFIG_FILE"
        echo "CONFIG_TARGET_ROOTFS_PARTSIZE=$PART_SIZE" >> "$GITHUB_WORKSPACE/$CONFIG_FILE"
    fi

    # 修改默认ip地址
    [ "$IP_ADDRESS" ] && sed -i '/lan) ipad/s/".*"/"'"$IP_ADDRESS"'"/' package/base-files/files/bin/config_generate

    # ttyd免登录
    sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

    # 设置root用户密码为password
    sed -i 's/root:::0:99999:7:::/root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.::0:99999:7:::/g' package/base-files/files/etc/shadow

    # 更改argon主题背景
    cp -f $GITHUB_WORKSPACE/images/bg1.jpg feeds/luci/themes/luci-theme-argon/htdocs/luci-static/argon/img/bg1.jpg
}

# 更新配置文件
update_config_file() {
    [ -e "$GITHUB_WORKSPACE/$CONFIG_FILE" ] && cp -f "$GITHUB_WORKSPACE/$CONFIG_FILE" .config
    make defconfig 1>/dev/null 2>&1
}

show_build_info() {
    echo -e "$(color cy "📊 当前编译信息")"
    echo "========================================"
    echo "🔷 固件源码: $(color cc "$SOURCE_REPO")"
    echo "🔷 源码分支: $(color cc "$REPO_BRANCH")"
    echo "🔷 目标设备: $(color cc "$DEVICE_TARGET")"
    echo "🔷 内核版本: $(color cc "$KERNEL_VERSION")"
    echo "========================================"
}

main "$@"
