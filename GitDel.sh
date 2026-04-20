#!/usr/bin/env bash
set -e

# 彩色输出函数
info() { echo -e "\033[36m[信息]\033[0m $1"; }
warn() { echo -e "\033[33m[警告]\033[0m $1"; }
success() { echo -e "\033[32m[完成]\033[0m $1"; }
title() { echo -e "\033[35m$1\033[0m"; }

title "=== Git 历史清空工具（支持私有仓库 & 自定义分支 & 批量操作） ==="
echo -e "bash <(curl -sL https://url.wuyang.skin/GitDel)"

# 读取 GitHub Token
read -p "请输入 GitHub Token（私有仓库必填）: " GITHUB_TOKEN

# 无论如何退出都清除 GitHub Token
trap 'unset GITHUB_TOKEN; echo -e "\033[36m[信息]\033[0m GitHub Token 已清除"' EXIT

while true; do
    read -p "请输入仓库列表（支持 URL 或 owner/repo，空格分隔，0退出）: " -a REPO_LIST
    if [[ "${REPO_LIST[0]}" == "0" ]]; then
        info "已退出脚本"
        exit 0
    fi

    for INPUT_REPO in "${REPO_LIST[@]}"; do
        # 统一仓库路径
        if [[ "$INPUT_REPO" =~ ^https://github.com/(.+)$ ]]; then
            REPO_PATH="${BASH_REMATCH[1]}"
        else
            REPO_PATH="${INPUT_REPO#/}"
        fi

        REMOTE_URL="https://github.com/$REPO_PATH.git"
        info "准备操作仓库: $REPO_PATH"

        TMP_DIR=$(mktemp -d)
        info "临时目录已创建: $TMP_DIR"

        info "正在克隆仓库..."
        git clone "$REMOTE_URL" "$TMP_DIR"
        cd "$TMP_DIR"

        # 检查仓库是否为空
        if [ -z "$(git ls-remote --heads origin)" ]; then
            warn "⚠️ 仓库为空！没有任何提交。"
            read -p "确定要继续清空并推送？[Y/N]: " yn_empty
            if [[ ! "$yn_empty" =~ ^[Yy]$ ]]; then
                warn "操作已取消"
                cd ~
                rm -rf "$TMP_DIR"
                continue
            fi
        fi

        # 备份工作流
        if [ -d ".github/workflows" ]; then
            TMP_WORKFLOW=$(mktemp -d)
            cp -r .github/workflows "$TMP_WORKFLOW/"
            info "工作流已备份到: $TMP_WORKFLOW"
        fi

        # 分支名
        read -p "请输入要操作的分支名（默认 main）: " BRANCH
        BRANCH=${BRANCH:-main}

        # 检查分支保护
        API_URL="https://api.github.com/repos/$REPO_PATH/branches/$BRANCH/protection"
        PROTECTED="no"
        HTTP_STATUS=$(curl -H "Authorization: token $GITHUB_TOKEN" -s -o /dev/null -w "%{http_code}" "$API_URL")
        if [[ "$HTTP_STATUS" == "200" ]]; then
            PROTECTED="yes"
        fi

        # 删除 Git 历史并初始化
        rm -rf .git
        git init

        # 自动设置 Git 提交身份，避免 commit 报错
        git config user.name "AutoCommit"
        git config user.email "auto@example.com"

        git add .
        git commit -m "init"
        success "Git 历史已清空（本地）"

        # 恢复工作流
        if [ -d "$TMP_WORKFLOW/workflows" ]; then
            mkdir -p .github
            rsync -a "$TMP_WORKFLOW/workflows/" .github/workflows/
            git add -f .github/workflows
            git commit --amend --no-edit
            success "工作流已恢复"
        fi

        git remote add origin "$REMOTE_URL"

        # 推送并解析中文错误
        info "正在推送到 $BRANCH..."
        push_output=$(git push -f origin "$BRANCH" 2>&1) || true
        if echo "$push_output" | grep -q "Cannot force-push"; then
            warn "⚠️ 无法强制推送到 $BRANCH 分支（受保护）"
        fi
        if echo "$push_output" | grep -q "Cannot update this protected ref"; then
            warn "⚠️ 远程分支受保护，更新被拒绝"
        fi
        if echo "$push_output" | grep -q "Changes must be made through a pull request"; then
            warn "⚠️ 必须通过 Pull Request 才能修改此分支"
        fi
        if echo "$push_output" | grep -q "required status checks"; then
            warn "⚠️ 分支有必需的状态检查未通过"
        fi
        if echo "$push_output" | grep -q "error:"; then
            warn "⚠️ 推送失败，请检查远程分支规则或权限"
        fi

        cd ~
        rm -rf "$TMP_DIR"
        success "临时目录已删除"
        title "=== 仓库 $REPO_PATH 操作完成 ==="
    done
done
