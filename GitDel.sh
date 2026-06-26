#!/usr/bin/env bash
set +e

# ===== 输出函数 =====
info() { echo -e "\033[36m[信息]\033[0m $1"; }
warn() { echo -e "\033[33m[警告]\033[0m $1"; }
success() { echo -e "\033[32m[完成]\033[0m $1"; }
title() { echo -e "\033[35m$1\033[0m"; }

title "=== Git 历史清空工具（支持私有仓库 & 自定义分支 & 批量操作） ==="
echo -e "bash <(curl -sL https://url.wuyang.skin/GitDel)"

# 读取 GitHub Token
read -p "请输入 GitHub Token（私有仓库必填）: " GITHUB_TOKEN
trap 'unset GITHUB_TOKEN; info "GitHub Token 已清除"' EXIT

# ===== 主循环 =====
while true; do

    read -p "请输入仓库列表（空格分隔，0退出）: " -a REPO_LIST
    [[ "${REPO_LIST[0]}" == "0" ]] && exit 0

    for INPUT_REPO in "${REPO_LIST[@]}"; do

        TMP_DIR=""
        TMP_WORKFLOW=""

        # =========================
        # 解析仓库
        # =========================
        if [[ "$INPUT_REPO" =~ ^https://github.com/(.+)$ ]]; then
            REPO_PATH="${BASH_REMATCH[1]}"
        else
            REPO_PATH="${INPUT_REPO#/}"
        fi

        if [[ -n "$GITHUB_TOKEN" ]]; then
            REMOTE_URL="https://${GITHUB_TOKEN}@github.com/${REPO_PATH}.git"
        else
            REMOTE_URL="https://github.com/${REPO_PATH}.git"
        fi

        info "准备操作仓库: $REPO_PATH"

        # =========================
        # clone
        # =========================
        TMP_DIR=$(mktemp -d)
        info "临时目录: $TMP_DIR"

        git clone "$REMOTE_URL" "$TMP_DIR"
        cd "$TMP_DIR"

        # =========================
        # 自动检测默认分支
        # =========================
        DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

        if [[ -z "$DEFAULT_BRANCH" ]]; then
            if git ls-remote --heads origin main | grep -q main; then
                DEFAULT_BRANCH="main"
            elif git ls-remote --heads origin master | grep -q master; then
                DEFAULT_BRANCH="master"
            else
                DEFAULT_BRANCH="main"
            fi
        fi

        info "默认分支: $DEFAULT_BRANCH"

        # =========================
        # 备份 workflows
        # =========================
        if [ -d ".github/workflows" ]; then
            TMP_WORKFLOW=$(mktemp -d)
            cp -r .github/workflows "$TMP_WORKFLOW/"
            info "已备份 workflows"
        fi

        # =========================
        # 清空历史
        # =========================
        rm -rf .git
        git init

        git config user.name "AutoCommit"
        git config user.email "auto@example.com"

        git add .
        git commit -m "init"
        success "历史已清空"

        # =========================
        # 恢复 workflows
        # =========================
        if [ -d "$TMP_WORKFLOW/workflows" ]; then
            mkdir -p .github
            rsync -a "$TMP_WORKFLOW/workflows/" .github/workflows/
            git add -f .github/workflows
            git commit --amend --no-edit
            success "已恢复 workflows"
        fi

        # =========================
        # 强制分支统一
        # =========================
        git branch -M "$DEFAULT_BRANCH"

        git remote add origin "$REMOTE_URL"

        # =========================
        # push
        # =========================
        info "推送到 $DEFAULT_BRANCH ..."

        push_output=$(git push -f origin "$DEFAULT_BRANCH" 2>&1) || true
        echo "$push_output"

        if echo "$push_output" | grep -q "protected"; then
            warn "分支可能受保护"
        fi

        if echo "$push_output" | grep -q "error"; then
            warn "推送失败"
        fi

        success "完成: $REPO_PATH"

        cd / >/dev/null 2>&1

        if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
            rm -rf "$TMP_DIR" 2>/dev/null
            info "已删除临时目录"
        fi

        if [[ -n "$TMP_WORKFLOW" && -d "$TMP_WORKFLOW" ]]; then
            rm -rf "$TMP_WORKFLOW" 2>/dev/null
            info "已删除 workflow 临时目录"
        fi

        echo "-----------------------------------"

    done

done
