#!/usr/bin/env sh
  set -eu

  SKIP_PUSH_FEATURE=0
  CREATE_MR=0
  TARGET_BRANCH=
  FEATURE_BRANCH=
  REMOTE=

  for arg in "$@"; do
    case "$arg" in
      --skip-push-feature)
        SKIP_PUSH_FEATURE=1
        ;;
      --mr)
        CREATE_MR=1
        ;;
      *)
        if [ -z "$TARGET_BRANCH" ]; then
          TARGET_BRANCH="$arg"
        elif [ -z "$FEATURE_BRANCH" ]; then
          FEATURE_BRANCH="$arg"
        elif [ -z "$REMOTE" ]; then
          REMOTE="$arg"
        else
          echo "未知参数: $arg" >&2
          echo "用法: $0 [--skip-push-feature] [--mr] [目标分支] [feature分支] [remote]" >&2
          exit 2
        fi
        ;;
    esac
  done

  TARGET_BRANCH="${TARGET_BRANCH:-dev}"
  FEATURE_BRANCH="${FEATURE_BRANCH:-$(git branch --show-current)}"
  REMOTE="${REMOTE:-origin}"

  if [ -z "$FEATURE_BRANCH" ]; then
    echo "无法识别当前分支，请手动传入 feature 分支名"
    echo "用法: $0 [--skip-push-feature] [--mr] [目标分支] [feature分支] [remote]"
    exit 1
  fi

  if [ "$FEATURE_BRANCH" = "$TARGET_BRANCH" ]; then
    echo "当前分支不能和目标分支相同: $TARGET_BRANCH"
    exit 1
  fi

  echo "目标分支: $TARGET_BRANCH"
  echo "功能分支: $FEATURE_BRANCH"
  echo "远程仓库: $REMOTE"
  if [ "$SKIP_PUSH_FEATURE" -eq 0 ]; then
    echo "推送功能分支: 是"
  else
    echo "推送功能分支: 否"
  fi
  if [ "$CREATE_MR" -eq 1 ]; then
    echo "创建 Merge Request: 是"
  else
    echo "创建 Merge Request: 否"
  fi

  git fetch "$REMOTE"

  # 第一次rebase：merge前feature的准备
  git checkout "$FEATURE_BRANCH"
  git rebase "$REMOTE/$TARGET_BRANCH"
  if [ "$SKIP_PUSH_FEATURE" -eq 0 ]; then
    git push "$REMOTE" "$FEATURE_BRANCH" -f
  fi

  if [ "$CREATE_MR" -eq 1 ]; then
    git fetch "$REMOTE" "$TARGET_BRANCH:$TARGET_BRANCH" # 不切换分支就能--ff-only更新main分支
    glab mr create --fill --web --target-branch "$TARGET_BRANCH"
    echo "已创建 Merge Request"
    exit 0
  fi

  # merge前target的准备 
  git checkout "$TARGET_BRANCH"
  # git pull --ff-only "$REMOTE" "$TARGET_BRANCH"
  git pull "$REMOTE" "$TARGET_BRANCH"

  # 具体的merge操作 
  git merge --no-ff --no-edit "$FEATURE_BRANCH"
  git push "$REMOTE" "$TARGET_BRANCH"

  # 第二次rebase引入merge记录：基于target分支，来rebase feature分支
  git rebase "$REMOTE/$TARGET_BRANCH" "$FEATURE_BRANCH"

  if [ "$SKIP_PUSH_FEATURE" -eq 0 ]; then
    git push "$REMOTE" "$FEATURE_BRANCH" -f
  fi

  git checkout "$FEATURE_BRANCH"

  echo "完成"
