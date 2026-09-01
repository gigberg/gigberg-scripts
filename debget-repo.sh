#!/usr/bin/env bash
# gen-deb-get-local.sh
# 在 /etc/deb-get/99-local.d/ 生成 deb-get 本地包定义文件。
# 模板依据: https://github.com/wimpysworld/deb-get/blob/main/EXTREPO.md
# 用法: debget-repo.sh [owner/repo [APP [--force]]]，无参数时进入交互式菜单。

set -euo pipefail

TARGET_DIR="${DEBGET_LOCAL_DIR:-/etc/deb-get/99-local.d}"

fail() {
    echo "错误: $*" >&2
    exit 1
}

require_nonempty() {
    local name="$1"
    local value="${!name:-}"
    if [[ -z "$value" ]]; then
        fail "${name} 不能为空"
    fi
}

validate_cut_field() {
    local name="$1"
    local value="${!name:-}"
    if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
        fail "${name} 必须是正整数"
    fi
}

validate_delimiter() {
    local value="$1"
    if [[ "${#value}" -ne 1 ]]; then
        fail "cut 分隔符必须是单个字符"
    fi
}

escape_dq() {
    local value="$1"
    local escape_dollar="${2:-1}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//\`/\\\`}"
    if [[ "${escape_dollar}" == 1 ]]; then
        value="${value//\$/\\\$}"
    fi
    printf '%s' "$value"
}

write_var() {
    local name="$1"
    local value="$2"
    printf '%s="%s"\n' "$name" "$(escape_dq "$value" 0)"
}

write_arch_support() {
    write_var "ARCHS_SUPPORTED" "$ARCHS_SUPPORTED"
    if [[ -n "$CODENAMES_SUPPORTED" ]]; then
        write_var "CODENAMES_SUPPORTED" "$CODENAMES_SUPPORTED"
    fi
}

write_common_tail() {
    write_var "EULA" "$EULA"
    write_var "PRETTY_NAME" "$PRETTY_NAME"
    write_var "WEBSITE" "$WEBSITE"
    write_var "SUMMARY" "$SUMMARY"
}

write_github_template() {
    {
        write_var "DEFVER" "1"
        write_arch_support
        printf 'get_github_releases "%s/%s" "latest"\n' "$(escape_dq "$GH_ORG")" "$(escape_dq "$GH_REPO")"
        printf 'if [ "${ACTION}" != prettylist ]; then\n'
        printf '    URL="$(grep -m 1 "browser_download_url.*\\.deb\\"" "${CACHE_FILE}" | cut -d "%s" -f %s)"\n' "$(escape_dq "$DELIM")" "$URL_FIELD"
        printf '    VERSION_PUBLISHED="$(cut -d "%s" -f %s <<< "${URL/v/}")"\n' "$(escape_dq "$DELIM")" "$VER_FIELD"
        printf 'fi\n'
        write_common_tail
    } > "${TMP_FILE}"
}

validate_repo_slug() {
    local value="$1"
    if [[ ! "$value" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
        fail "仓库参数格式必须是 owner/repo，例如 mkasberg/ghostty-ubuntu"
    fi
}

fetch_github_summary() {
    local api_url description
    SUMMARY=""
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        echo "警告: GITHUB_TOKEN 未设置，SUMMARY 留空" >&2
        return 0
    fi

    api_url="https://api.github.com/repos/${GH_ORG}/${GH_REPO}"
    if ! description="$(curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" "${api_url}" | jq -r '.description // ""' 2>/dev/null)"; then
        echo "警告: 获取 GitHub 仓库描述失败，SUMMARY 留空" >&2
        return 0
    fi
    SUMMARY="$description"
}

CLI_MODE=0
FORCE=0
POSITIONAL=()
for arg in "$@"; do
    if [[ "${arg}" == "--force" ]]; then
        FORCE=1
    else
        POSITIONAL+=("${arg}")
    fi
done

if [[ "${FORCE}" -eq 1 && "${#POSITIONAL[@]}" -eq 0 ]]; then
    fail "用法: debget-repo.sh <owner/repo> [APP] [--force]"
fi

if [[ "${#POSITIONAL[@]}" -gt 0 ]]; then
    CLI_MODE=1
    if [[ "${#POSITIONAL[@]}" -gt 2 ]]; then
        fail "用法: debget-repo.sh <owner/repo> [APP] [--force]"
    fi

    REPO_SLUG="${POSITIONAL[0]}"
    validate_repo_slug "${REPO_SLUG}"
    GH_ORG="${REPO_SLUG%%/*}"
    GH_REPO="${REPO_SLUG#*/}"
    APP="${POSITIONAL[1]:-${GH_REPO}}"
    if [[ ! "$APP" =~ ^[a-zA-Z0-9][a-zA-Z0-9._+-]*$ ]]; then
        fail "包名只能包含字母、数字、点、下划线、加号和减号"
    fi

    TEMPLATE="github"
    PRETTY_NAME="${APP}"
    WEBSITE="https://github.com/${GH_ORG}/${GH_REPO}"
    EULA=""
    ARCHS_SUPPORTED="amd64"
    CODENAMES_SUPPORTED=""
    DELIM="/"
    URL_FIELD="8"
    VER_FIELD="8"
    fetch_github_summary
else
cat <<'EOF'
==== deb-get 本地包定义生成器 ====
支持的模板类型:
  1) apt-asc     - APT 仓库 (ASCII armored key)
  2) apt-gpg     - APT 仓库 (binary gpg key)
  3) apt-keyid   - APT 仓库 (keyserver key id)
  4) ppa         - Launchpad PPA
  5) github      - GitHub Releases (默认)
  6) website     - 网站解析下载
  7) direct      - 直接下载链接
EOF

read -rp "请选择模板类型 [5]: " TEMPLATE
TEMPLATE="${TEMPLATE:-5}"
TEMPLATE="${TEMPLATE,,}"

read -rp "包名 APP (必须与 apt show 显示的 Package: 名称一致): " APP
require_nonempty APP
if [[ ! "$APP" =~ ^[a-zA-Z0-9][a-zA-Z0-9._+-]*$ ]]; then
    fail "包名只能包含字母、数字、点、下划线、加号和减号"
fi

read -rp "PRETTY_NAME (软件品牌名): " PRETTY_NAME
read -rp "WEBSITE (官网 URL): " WEBSITE
read -rp "SUMMARY (简要描述): " SUMMARY
read -rp "EULA (可留空): " EULA
read -rp "ARCHS_SUPPORTED [amd64 arm64 armhf]: " ARCHS_SUPPORTED
ARCHS_SUPPORTED="${ARCHS_SUPPORTED:-amd64 arm64 armhf}"
read -rp "CODENAMES_SUPPORTED (可留空): " CODENAMES_SUPPORTED
fi

mkdir -p "${TARGET_DIR}"
if [[ ! -w "${TARGET_DIR}" ]]; then
    fail "${TARGET_DIR} 不可写，请使用 sudo 运行本脚本"
fi

OUT_FILE="${TARGET_DIR}/${APP}"
if [[ "${CLI_MODE}" -eq 1 ]]; then
    if [[ -e "${OUT_FILE}" && "${FORCE}" -ne 1 ]]; then
        fail "文件 ${OUT_FILE} 已存在，使用 --force 覆盖"
    fi
else
    if [[ -e "${OUT_FILE}" ]]; then
        read -rp "文件 ${OUT_FILE} 已存在，是否覆盖? [y/N]: " OVERWRITE
        if [[ ! "${OVERWRITE}" =~ ^[Yy]$ ]]; then
            echo "已取消"
            exit 0
        fi
    fi
fi

TMP_FILE="${OUT_FILE}.tmp.$$"
trap 'rm -f "${TMP_FILE}"' EXIT

case "${TEMPLATE}" in
    1|apt-asc)
        read -rp "ASC_KEY_URL (ASCII armored key 文件 URL): " ASC_KEY_URL
        require_nonempty ASC_KEY_URL
        read -rp "APT_LIST_NAME (默认 ${APP}): " APT_LIST_NAME
        APT_LIST_NAME="${APT_LIST_NAME:-\${APP}}"
        read -rp "APT_REPO_URL (仓库 URL、发行版代号和 components): " APT_REPO_URL
        require_nonempty APT_REPO_URL
        read -rp "APT_REPO_OPTIONS [arch=\${HOST_ARCH}]: " APT_REPO_OPTIONS
        APT_REPO_OPTIONS="${APT_REPO_OPTIONS:-arch=\${HOST_ARCH}}"
        {
            write_var "DEFVER" "1"
            write_arch_support
            write_var "ASC_KEY_URL" "$ASC_KEY_URL"
            write_var "APT_LIST_NAME" "$APT_LIST_NAME"
            write_var "APT_REPO_URL" "$APT_REPO_URL"
            write_var "APT_REPO_OPTIONS" "$APT_REPO_OPTIONS"
            write_common_tail
        } > "${TMP_FILE}"
        ;;

    2|apt-gpg)
        read -rp "GPG_KEY_URL (binary gpg key 文件 URL): " GPG_KEY_URL
        require_nonempty GPG_KEY_URL
        read -rp "APT_LIST_NAME (默认 ${APP}): " APT_LIST_NAME
        APT_LIST_NAME="${APT_LIST_NAME:-\${APP}}"
        read -rp "APT_REPO_URL (仓库 URL、发行版代号和 components): " APT_REPO_URL
        require_nonempty APT_REPO_URL
        read -rp "APT_REPO_OPTIONS [arch=\${HOST_ARCH}]: " APT_REPO_OPTIONS
        APT_REPO_OPTIONS="${APT_REPO_OPTIONS:-arch=\${HOST_ARCH}}"
        {
            write_var "DEFVER" "1"
            write_arch_support
            write_var "GPG_KEY_URL" "$GPG_KEY_URL"
            write_var "APT_LIST_NAME" "$APT_LIST_NAME"
            write_var "APT_REPO_URL" "$APT_REPO_URL"
            write_var "APT_REPO_OPTIONS" "$APT_REPO_OPTIONS"
            write_common_tail
        } > "${TMP_FILE}"
        ;;

    3|apt-keyid)
        read -rp "GPG_KEY_ID (keyserver key id): " GPG_KEY_ID
        require_nonempty GPG_KEY_ID
        read -rp "APT_LIST_NAME (默认 ${APP}): " APT_LIST_NAME
        APT_LIST_NAME="${APT_LIST_NAME:-\${APP}}"
        read -rp "APT_REPO_URL (仓库 URL、发行版代号和 components): " APT_REPO_URL
        require_nonempty APT_REPO_URL
        read -rp "APT_REPO_OPTIONS [arch=\${HOST_ARCH}]: " APT_REPO_OPTIONS
        APT_REPO_OPTIONS="${APT_REPO_OPTIONS:-arch=\${HOST_ARCH}}"
        {
            write_var "DEFVER" "1"
            write_arch_support
            write_var "GPG_KEY_ID" "$GPG_KEY_ID"
            write_var "APT_LIST_NAME" "$APT_LIST_NAME"
            write_var "APT_REPO_URL" "$APT_REPO_URL"
            write_var "APT_REPO_OPTIONS" "$APT_REPO_OPTIONS"
            write_common_tail
        } > "${TMP_FILE}"
        ;;

    4|ppa)
        read -rp "PPA (格式 ppa:<person>/<archive>): " PPA
        require_nonempty PPA
        {
            write_var "DEFVER" "1"
            write_var "PPA" "$PPA"
            write_common_tail
        } > "${TMP_FILE}"
        ;;

    5|github|"")
        if [[ "${CLI_MODE}" -ne 1 ]]; then
            read -rp "GitHub 组织/用户名: " GH_ORG
            require_nonempty GH_ORG
            read -rp "GitHub 仓库名: " GH_REPO
            require_nonempty GH_REPO
            read -rp "cut 分隔符 [/]: " DELIM
            DELIM="${DELIM:-/}"
            validate_delimiter "$DELIM"
            read -rp "URL cut 字段 [8]: " URL_FIELD
            URL_FIELD="${URL_FIELD:-8}"
            validate_cut_field URL_FIELD
            read -rp "VERSION_PUBLISHED cut 字段 [8]: " VER_FIELD
            VER_FIELD="${VER_FIELD:-8}"
            validate_cut_field VER_FIELD
        fi
        write_github_template
        ;;

    6|website)
        read -rp "网站 URL: " SITE_URL
        require_nonempty SITE_URL
        read -rp "grep 匹配模式 (pattern): " PATTERN
        require_nonempty PATTERN
        read -rp "cut 分隔符 [/]: " DELIM
        DELIM="${DELIM:-/}"
        validate_delimiter "$DELIM"
        read -rp "URL cut 字段: " URL_FIELD
        validate_cut_field URL_FIELD
        read -rp "VERSION_PUBLISHED cut 字段: " VER_FIELD
        validate_cut_field VER_FIELD
        {
            write_var "DEFVER" "1"
            write_arch_support
            printf 'get_website "%s"\n' "$(escape_dq "$SITE_URL")"
            printf 'if [ "${ACTION}" != prettylist ]; then\n'
            printf '    URL="$(grep -m 1 "%s" "${CACHE_FILE}" | cut -d "%s" -f %s)"\n' "$(escape_dq "$PATTERN")" "$(escape_dq "$DELIM")" "$URL_FIELD"
            printf '    VERSION_PUBLISHED="$(cut -d "%s" -f %s <<< "${URL}")"\n' "$(escape_dq "$DELIM")" "$VER_FIELD"
            printf 'fi\n'
            write_common_tail
        } > "${TMP_FILE}"
        ;;

    7|direct)
        read -rp "直接下载 URL: " DOWNLOAD_URL
        require_nonempty DOWNLOAD_URL
        read -rp "cut 分隔符 [/]: " DELIM
        DELIM="${DELIM:-/}"
        validate_delimiter "$DELIM"
        read -rp "VERSION_PUBLISHED cut 字段: " VER_FIELD
        validate_cut_field VER_FIELD
        {
            write_var "DEFVER" "1"
            write_arch_support
            printf 'if [ "${ACTION}" != prettylist ]; then\n'
            printf '    URL="$(unroll_url "%s")"\n' "$(escape_dq "$DOWNLOAD_URL")"
            printf '    VERSION_PUBLISHED="$(cut -d "%s" -f %s <<< "${URL}")"\n' "$(escape_dq "$DELIM")" "$VER_FIELD"
            printf 'fi\n'
            write_common_tail
        } > "${TMP_FILE}"
        ;;

    *)
        fail "不支持的模板类型: ${TEMPLATE}"
        ;;
esac

mv "${TMP_FILE}" "${OUT_FILE}"
trap - EXIT

echo "已生成: ${OUT_FILE}"
