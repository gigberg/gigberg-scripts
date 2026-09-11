#!/usr/bin/env sh
#
# 假设执行前提交图为：
#
#   A---B---C                 target
#        \
#         D---E              feature
#
# 1. temp（默认）：feature 本地和远程均不改变
#
#   A---B---C---------M       target
#            \       /
#             D'---E'         临时分支（合并成功后删除）
#        \
#         D---E               feature
#
# 2. temp-update-feature：合并后 feature 更新到 target 的 merge commit
#
#   A---B---C---------M       target、feature
#            \       /
#             D'---E'         临时分支（合并成功后删除）
#
# 3. direct：直接 rebase feature，再合并；最后 feature 更新到 target
#
#   A---B---C---------M       target、feature
#            \       /
#             D'---E'
#
set -eu

MODE=temp
SKIP_PUSH_FEATURE=0
CREATE_MR=0
TARGET_BRANCH=
FEATURE_BRANCH=
REMOTE=
TEMP_BRANCH=

usage() {
  cat <<EOF
用法: $0 [选项] [目标分支] [feature分支] [remote]

模式:
  --mode=temp                 临时分支 rebase 后合并，feature 不变（默认）
  --mode=temp-update-feature  临时分支合并后，将 feature 更新到目标分支
  --mode=direct               直接 rebase feature，保留原有流程

其他选项:
  --skip-push-feature  不推送 feature 分支
  --mr                 创建 Merge Request，不在本地合并
  -h, --help           显示帮助

常用命令:
  # 创建测试用的空提交
  git commit --allow-empty -m "chore: empty commit"

  # tagent 项目：通过临时分支合并到 dev，feature 保持不变
  bash ../merge_feature.sh --mode=temp dev

  # tagent 项目：合并到 test，并将 feature 对齐到 test
  bash ../merge_feature.sh --mode=temp-update-feature test

  # uup 项目：对齐到 main 并创建 MR/PR（网页中需要手动操作）
  bash /home/charming/ubtcode/tiangong/agent2026/merge_feature.sh --mode=direct --mr main
  # 等价准备步骤: git fetch origin main:main && git rebase main && git push

注意: --mr 不能与 --mode=temp-update-feature 同时使用，因为 MR 尚未合并。
EOF
}

die() {
  echo "错误: $*" >&2
  exit 1
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode)
        [ "$#" -ge 2 ] || die "--mode 缺少参数"
        MODE="$2"
        shift 2
        ;;
      --mode=*)
        MODE=${1#--mode=}
        shift
        ;;
      --skip-push-feature)
        SKIP_PUSH_FEATURE=1
        shift
        ;;
      --mr)
        CREATE_MR=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --*)
        echo "未知选项: $1" >&2
        usage >&2
        exit 2
        ;;
      *)
        if [ -z "$TARGET_BRANCH" ]; then
          TARGET_BRANCH="$1"
        elif [ -z "$FEATURE_BRANCH" ]; then
          FEATURE_BRANCH="$1"
        elif [ -z "$REMOTE" ]; then
          REMOTE="$1"
        else
          echo "未知参数: $1" >&2
          usage >&2
          exit 2
        fi
        shift
        ;;
    esac
  done
}

validate_args() {
  case "$MODE" in
    temp|temp-update-feature|direct) ;;
    *) die "未知模式: $MODE" ;;
  esac

  [ -n "$FEATURE_BRANCH" ] || die "无法识别当前分支，请手动传入 feature 分支名"
  [ "$FEATURE_BRANCH" != "$TARGET_BRANCH" ] || die "feature 分支不能和目标分支相同: $TARGET_BRANCH"
  git show-ref --verify --quiet "refs/heads/$FEATURE_BRANCH" || die "本地 feature 分支不存在: $FEATURE_BRANCH"
  git remote get-url "$REMOTE" >/dev/null 2>&1 || die "远程仓库不存在: $REMOTE"

  if [ "$CREATE_MR" -eq 1 ] && [ "$MODE" = temp-update-feature ]; then
    die "--mr 不能与 --mode=temp-update-feature 同时使用"
  fi

  if [ -n "$(git status --porcelain)" ]; then
    die "工作区不干净，请先提交或暂存当前改动"
  fi
}

mode_description() {
  case "$MODE" in
    temp) echo "临时分支（feature 不变）" ;;
    temp-update-feature) echo "临时分支 + 更新 feature 到目标分支" ;;
    direct) echo "原有模式（直接 rebase feature）" ;;
  esac
}

print_summary() {
  echo "合并模式: $(mode_description)"
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
}

make_temp_branch_name() {
  safe_feature=$(printf '%s' "$FEATURE_BRANCH" | tr '/ ' '--')
  TEMP_BRANCH="merge-${safe_feature}-$$"
  if git show-ref --verify --quiet "refs/heads/$TEMP_BRANCH"; then
    die "临时分支已存在: $TEMP_BRANCH"
  fi
}

prepare_rebased_branch() {
  case "$MODE" in
    direct)
      git checkout "$FEATURE_BRANCH"
      git rebase "$REMOTE/$TARGET_BRANCH"
      ;;
    temp|temp-update-feature)
      make_temp_branch_name
      git checkout -b "$TEMP_BRANCH" "$FEATURE_BRANCH"
      git rebase "$REMOTE/$TARGET_BRANCH"
      ;;
  esac
}

rebased_branch() {
  if [ "$MODE" = direct ]; then
    echo "$FEATURE_BRANCH"
  else
    echo "$TEMP_BRANCH"
  fi
}

push_rebased_feature_if_needed() {
  [ "$MODE" = direct ] || return 0
  [ "$SKIP_PUSH_FEATURE" -eq 1 ] || git push --force-with-lease "$REMOTE" "$FEATURE_BRANCH"
}

create_merge_request() {
  source_branch=$(rebased_branch)

  if [ "$MODE" = temp ]; then
    git push --set-upstream "$REMOTE" "$source_branch"
  fi

  git fetch "$REMOTE" "$TARGET_BRANCH:$TARGET_BRANCH"
  glab mr create --fill --web --source-branch "$source_branch" --target-branch "$TARGET_BRANCH"

  if [ "$MODE" = temp ]; then
    git checkout "$FEATURE_BRANCH"
    git branch -D "$TEMP_BRANCH"
  fi

  echo "已创建 Merge Request，源分支: $source_branch"
}

merge_into_target() {
  source_branch=$(rebased_branch)
  git checkout "$TARGET_BRANCH"
  git pull --ff-only "$REMOTE" "$TARGET_BRANCH"
  git merge --no-ff --no-edit "$source_branch"
  git push "$REMOTE" "$TARGET_BRANCH"
}

update_feature_after_merge() {
  case "$MODE" in
    temp)
      git branch -D "$TEMP_BRANCH"
      git checkout "$FEATURE_BRANCH"
      ;;
    temp-update-feature)
      git branch -f "$FEATURE_BRANCH" "$TARGET_BRANCH"
      git branch -D "$TEMP_BRANCH"
      if [ "$SKIP_PUSH_FEATURE" -eq 0 ]; then
        git push --force-with-lease "$REMOTE" "$FEATURE_BRANCH"
      fi
      git checkout "$FEATURE_BRANCH"
      ;;
    direct)
      git rebase "$REMOTE/$TARGET_BRANCH" "$FEATURE_BRANCH"
      if [ "$SKIP_PUSH_FEATURE" -eq 0 ]; then
        git push --force-with-lease "$REMOTE" "$FEATURE_BRANCH"
      fi
      git checkout "$FEATURE_BRANCH"
      ;;
  esac
}

main() {
  parse_args "$@"

  TARGET_BRANCH=${TARGET_BRANCH:-dev}
  FEATURE_BRANCH=${FEATURE_BRANCH:-$(git branch --show-current)}
  REMOTE=${REMOTE:-origin}

  validate_args
  print_summary
  git fetch "$REMOTE"
  prepare_rebased_branch
  push_rebased_feature_if_needed

  if [ "$CREATE_MR" -eq 1 ]; then
    create_merge_request
    exit 0
  fi

  merge_into_target
  update_feature_after_merge
  echo "完成"
}

main "$@"
