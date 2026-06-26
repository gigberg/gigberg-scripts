#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
MARKER_START="<!-- codex-toc-inject:start -->"
MARKER_END="<!-- codex-toc-inject:end -->"
INJECT_FILE="codex-toc-inject.js"
DEFAULT_EXT_ID="openai.chatgpt"
RAIL_GATE_NEEDLE='c=St(`2551582477`)&&a,l,u;if'
RAIL_GATE_PATCHED='c=a,l,u;if'
TOC_BRIDGE_MARKER='__codexThreadTocSource'
TOC_BRIDGE_NEEDLE='});(0,Q.useEffect)(()=>to(f,e,{revealItem:Ue}),[e,Ue,f])'
TOC_BRIDGE_SNIPPET='globalThis.__codexThreadTocSource={conversationId:e,isConversationHistoryComplete:()=>f.get(ne,e)??!1,getItems:()=>Kf({isConversationHistoryComplete:!0,isAppgenEndCardEnabled:m,isBackgroundSubagentsEnabled:a,modelProvider:g,projectlessOutputDirectory:T,visibleTurnEntries:N}).map((e,t)=>({id:e.id,turnKey:e.turnKey,index:t,label:typeof e.getLabel==`function`?e.getLabel():``})),reveal:async t=>{let n=Kf({isConversationHistoryComplete:!0,isAppgenEndCardEnabled:m,isBackgroundSubagentsEnabled:a,modelProvider:g,projectlessOutputDirectory:T,visibleTurnEntries:N}).find(e=>e.id===t);n!=null&&await He(n)},loadOlderOnce:async()=>{if(f.get(ne,e)??!1)return!0;try{return await oe(`load-older-conversation-history-page`,{conversationId:e,dependentConversationIds:V==null?[]:[V]}),await Gn(),f.get(ne,e)??!1}catch(t){return!0}},loadAllHistory:async()=>{for(let t=0;t<80;t+=1){if(f.get(ne,e)??!1)return!0;try{await oe(`load-older-conversation-history-page`,{conversationId:e,dependentConversationIds:V==null?[]:[V]}),await Gn()}catch(n){return!0}}return f.get(ne,e)??!1}};(0,Q.useEffect)(()=>()=>{globalThis.__codexThreadTocSource?.conversationId===e&&(globalThis.__codexThreadTocSource=null)},[e]);'

usage() {
  cat <<'USAGE'
Patch the installed OpenAI Codex VS Code desktop extension webview with a
small, standalone in-thread TOC overlay.

Usage:
  ./patch-codex-toc.sh [options]

Options:
  --extension-dir PATH   Patch this extension directory directly.
  --dry-run              Print what would be changed.
  --unpatch              Remove the injected script tag and injected JS file.
  --force                Recreate backup even if one already exists.
  -h, --help             Show this help.

Examples:
  ./patch-codex-toc.sh
  ./patch-codex-toc.sh --extension-dir "$HOME/.vscode/extensions/openai.chatgpt-26.616.81150-linux-x64"
  ./patch-codex-toc.sh --unpatch

After patching, reload VS Code. Toggle the TOC with Ctrl+Alt+O or the TOC
button ☰ in the Codex conversation header.
By default this only searches ~/.vscode/extensions.
The patch also enables Codex's built-in user-message rail locally so the TOC
can read the full user-question index instead of the virtualized visible rows.
It also injects a small hidden bridge into the conversation bundle so opening
the TOC can ask Codex to load older history without manually scrolling.
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

find_rail_bundle() {
  local found=()
  [[ -d "$assets_dir" ]] || return 1
  while IFS= read -r path; do
    [[ -n "$path" ]] && found+=("$path")
  done < <(find "$assets_dir" -maxdepth 1 -type f -name 'local-conversation-thread-*.js' 2>/dev/null | sort -V)

  if [[ ${#found[@]} -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${found[-1]}"
}

extension_dir=""
dry_run=0
unpatch=0
force=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --extension-dir)
      [[ $# -ge 2 ]] || die "--extension-dir requires a path"
      extension_dir="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --unpatch)
      unpatch=1
      shift
      ;;
    --force)
      force=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

find_extension_dir() {
  local base
  local found=()

  base="$HOME/.vscode/extensions"
  [[ -d "$base" ]] || return 1
  while IFS= read -r path; do
    [[ -n "$path" ]] && found+=("$path")
  done < <(find "$base" -maxdepth 1 -type d -name "${DEFAULT_EXT_ID}-*" 2>/dev/null | sort -V)

  if [[ ${#found[@]} -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${found[-1]}"
}

if [[ -z "$extension_dir" ]]; then
  extension_dir="$(find_extension_dir)" || die "could not find ${DEFAULT_EXT_ID}-* under $HOME/.vscode/extensions; pass --extension-dir"
fi

extension_dir="${extension_dir%/}"
webview_dir="$extension_dir/webview"
assets_dir="$webview_dir/assets"
index_html="$webview_dir/index.html"
inject_js="$webview_dir/$INJECT_FILE"
backup_html="$index_html.codex-toc.bak"
rail_bundle="$(find_rail_bundle || true)"
rail_bundle_backup=""
if [[ -n "$rail_bundle" ]]; then
  rail_bundle_backup="$rail_bundle.codex-toc.bak"
fi
rail_bundle_backup_done=0

rail_gate_state() {
  if [[ -z "$rail_bundle" || ! -f "$rail_bundle" ]]; then
    printf 'missing\n'
    return
  fi

  if grep -Fq "$RAIL_GATE_PATCHED" "$rail_bundle"; then
    printf 'patched\n'
    return
  fi

  if grep -Fq "$RAIL_GATE_NEEDLE" "$rail_bundle"; then
    printf 'unpatched\n'
    return
  fi

  printf 'unsupported\n'
}

toc_bridge_state() {
  if [[ -z "$rail_bundle" || ! -f "$rail_bundle" ]]; then
    printf 'missing\n'
    return
  fi

  if grep -Fq "$TOC_BRIDGE_MARKER" "$rail_bundle"; then
    printf 'patched\n'
    return
  fi

  if grep -Fq "$TOC_BRIDGE_NEEDLE" "$rail_bundle"; then
    printf 'unpatched\n'
    return
  fi

  printf 'unsupported\n'
}

[[ -d "$extension_dir" ]] || die "extension directory does not exist: $extension_dir"
[[ -d "$webview_dir" ]] || die "webview directory does not exist: $webview_dir"
[[ -f "$index_html" ]] || die "index.html does not exist: $index_html"

if [[ $dry_run -eq 1 ]]; then
  info "dry-run: extension_dir=$extension_dir"
  info "dry-run: index_html=$index_html"
  info "dry-run: inject_js=$inject_js"
  if [[ -n "$rail_bundle" ]]; then
    info "dry-run: rail_bundle=$rail_bundle"
    info "dry-run: rail_gate_state=$(rail_gate_state)"
    info "dry-run: toc_bridge_state=$(toc_bridge_state)"
  else
    info "dry-run: rail_bundle=(not found)"
    info "dry-run: rail_gate_state=missing"
    info "dry-run: toc_bridge_state=missing"
  fi
fi

require_supported_rail_gate() {
  local state
  state="$(rail_gate_state)"

  case "$state" in
    patched)
      info "rail gate already enabled: $rail_bundle"
      ;;
    unpatched)
      info "rail gate can be enabled: $rail_bundle"
      ;;
    missing)
      die "could not find webview/assets/local-conversation-thread-*.js; refusing to patch without the full user-question rail"
      ;;
    unsupported)
      die "rail gate pattern not found in $rail_bundle; this Codex extension version is not supported by this patch"
      ;;
    *)
      die "unknown rail gate state: $state"
      ;;
  esac
}

require_supported_toc_bridge() {
  local state
  state="$(toc_bridge_state)"

  case "$state" in
    patched)
      info "TOC conversation bridge already installed: $rail_bundle"
      ;;
    unpatched)
      info "TOC conversation bridge can be installed: $rail_bundle"
      ;;
    missing)
      die "could not find webview/assets/local-conversation-thread-*.js; refusing to patch without the TOC conversation bridge"
      ;;
    unsupported)
      die "TOC bridge pattern not found in $rail_bundle; this Codex extension version is not supported by this patch"
      ;;
    *)
      die "unknown TOC bridge state: $state"
      ;;
  esac
}

write_inject_js() {
  [[ $dry_run -eq 1 ]] && {
    info "dry-run: would write $inject_js"
    return
  }

  cat > "$inject_js" <<'JS'
(() => {
  const HOTKEY = "KeyO";
  const TOC_ID = "codex-thread-toc-inject";
  const STYLE_ID = "codex-toc-style";
  const TOOLBAR_BUTTON_ID = "codex-thread-toc-toolbar-button";
  const RAIL_BUTTON_SELECTOR = "[data-thread-user-message-navigation-item-id]";
  const RAIL_LIST_SELECTOR = "[data-thread-user-message-navigation-rail-list]";
  const USER_ANCHOR_SELECTOR = "[data-local-conversation-user-anchor]";
  const SEARCH_UNIT_SELECTOR = "[data-content-search-unit-key]";
  const USER_BUBBLE_SELECTOR = "[data-user-message-bubble]";
  const MAX_ITEMS = 1000;

  let visible = false;
  let refreshTimer = 0;
  let routeKey = "";
  let railSignature = "";
  let modelSource = "empty";
  let items = [];
  let labelsById = new Map();
  let labelReadInFlight = false;
  let historyLoadInFlight = false;
  let historyLoadAttemptedKey = "";
  let collapsed = false;
  let dragState = null;

  function ensureStyle() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = `
      #${TOC_ID} {
        position: fixed;
        top: 56px;
        right: 12px;
        width: min(320px, calc(100vw - 24px));
        max-height: min(72vh, calc(100vh - 96px));
        z-index: 2147483647;
        overflow: auto;
        padding: 0 8px 8px;
        border: 1px solid color-mix(in srgb, currentColor 24%, transparent);
        border-radius: 8px;
        background: var(--vscode-sideBar-background, #1e1e1e);
        color: var(--vscode-sideBar-foreground, #ddd);
        box-shadow: 0 8px 24px rgba(0,0,0,.28);
        font: 12px/1.35 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        scrollbar-width: none;
      }
      #${TOC_ID}::-webkit-scrollbar {
        width: 0;
        height: 0;
      }
      #${TOC_ID}[hidden] { display: none; }
      #${TOC_ID} .toc-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        position: sticky;
        top: 0;
        z-index: 1;
        margin: 0 -2px 8px;
        padding: 8px 2px 6px;
        background: var(--vscode-sideBar-background, #1e1e1e);
        cursor: move;
        user-select: none;
      }
      #${TOC_ID} .toc-title {
        min-width: 0;
        flex: 1 1 auto;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-weight: 650;
      }
      #${TOC_ID} .toc-actions {
        display: flex;
        align-items: center;
        gap: 4px;
        flex: 0 0 auto;
      }
      #${TOC_ID} .toc-icon {
        width: 22px;
        height: 22px;
        flex: 0 0 22px;
        text-align: center;
        border: 0;
        border-radius: 5px;
        color: inherit;
        background: transparent;
        cursor: pointer;
      }
      #${TOC_ID} .toc-icon:hover,
      #${TOC_ID} .toc-item:hover {
        background: color-mix(in srgb, currentColor 14%, transparent);
      }
      #${TOC_ID} .toc-item {
        display: grid;
        grid-template-columns: auto 1fr;
        gap: 6px;
        width: 100%;
        text-align: left;
        border: 0;
        border-radius: 5px;
        padding: 5px 6px;
        margin: 2px 0;
        color: inherit;
        background: transparent;
        cursor: pointer;
      }
      #${TOC_ID} .toc-item.is-active .toc-kind {
        opacity: .95;
      }
      #${TOC_ID} .toc-kind {
        opacity: .72;
        font-variant-numeric: tabular-nums;
      }
      #${TOC_ID} .toc-text {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      #${TOC_ID} .toc-empty {
        margin: 6px 4px;
        opacity: .72;
      }
      #${TOOLBAR_BUTTON_ID} {
        width: 28px;
        height: 28px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        flex: 0 0 auto;
        border: 0;
        border-radius: 6px;
        color: inherit;
        background: transparent;
        cursor: pointer;
        font: inherit;
        opacity: .82;
      }
      #${TOOLBAR_BUTTON_ID}:hover,
      #${TOOLBAR_BUTTON_ID}.is-active {
        background: color-mix(in srgb, currentColor 12%, transparent);
        opacity: 1;
      }
      #${TOC_ID}[data-collapsed="true"] {
        max-height: none;
        overflow: hidden;
        padding-bottom: 0;
      }
      #${TOC_ID}[data-collapsed="true"] .toc-header {
        margin-bottom: 0;
      }
      #${TOC_ID}[data-collapsed="true"] .toc-body {
        display: none;
      }
      .codex-toc-hit {
        outline: 2px solid var(--vscode-focusBorder, #4da3ff) !important;
        outline-offset: 3px;
      }
    `;
    document.head.appendChild(style);
  }

  function ensurePanel() {
    ensureStyle();
    let el = document.getElementById(TOC_ID);
    if (el) return el;

    el = document.createElement("div");
    el.id = TOC_ID;
    el.hidden = true;
    document.body.appendChild(el);
    return el;
  }

  function hasClasses(el, classes) {
    if (!(el instanceof HTMLElement)) return false;
    return classes.every((name) => el.classList.contains(name));
  }

  function findHeaderRoot() {
    const roots = [...document.querySelectorAll(".draggable.extension\\:px-panel")]
      .filter((el) => el instanceof HTMLElement && el.offsetParent !== null)
      .map((el) => ({ el, rect: el.getBoundingClientRect() }))
      .filter(({ rect }) => rect.width > 0 && rect.height > 0 && rect.top < 120);
    return roots.sort((left, right) => left.rect.top - right.rect.top || right.rect.left - left.rect.left)[0]?.el || null;
  }

  function findHeaderActionGroup() {
    const root = findHeaderRoot();
    if (!root) return null;

    const rootRect = root.getBoundingClientRect();
    const groups = [...root.querySelectorAll("div")]
      .filter((el) => hasClasses(el, ["flex", "flex-shrink-0", "items-center", "gap-1"]))
      .map((el) => ({ el, rect: el.getBoundingClientRect() }))
      .filter(({ rect }) => rect.width > 0 && rect.height > 0 && rect.left >= rootRect.left && rect.right <= rootRect.right + 1);

    return groups.sort((left, right) => right.rect.right - left.rect.right || right.rect.width - left.rect.width)[0]?.el || null;
  }

  function updateToolbarButton() {
    const button = document.getElementById(TOOLBAR_BUTTON_ID);
    if (!(button instanceof HTMLElement)) return;
    button.classList.toggle("is-active", visible);
    button.setAttribute("aria-pressed", visible ? "true" : "false");
  }

  function ensureToolbarButton() {
    ensureStyle();
    const group = findHeaderActionGroup();
    if (!group) return null;

    let button = document.getElementById(TOOLBAR_BUTTON_ID);
    if (!(button instanceof HTMLButtonElement)) {
      button = document.createElement("button");
      button.id = TOOLBAR_BUTTON_ID;
      button.type = "button";
      button.title = "User Questions";
      button.setAttribute("aria-label", "Show user questions");
      button.textContent = "#";
      button.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        setVisible(!visible);
      });
    }

    if (button.parentElement !== group || group.firstElementChild !== button) {
      group.insertBefore(button, group.firstElementChild);
    }
    updateToolbarButton();
    return button;
  }

  function clamp(value, min, max) {
    return Math.min(Math.max(value, min), max);
  }

  function startDrag(event) {
    if (event.button !== 0) return;
    if (event.target?.closest?.("button")) return;

    const panel = ensurePanel();
    const rect = panel.getBoundingClientRect();
    dragState = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      moved: false
    };

    event.currentTarget.setPointerCapture?.(event.pointerId);
    event.preventDefault();
  }

  function moveDrag(event) {
    if (!dragState || event.pointerId !== dragState.pointerId) return;

    const panel = ensurePanel();
    const deltaX = event.clientX - dragState.startX;
    const deltaY = event.clientY - dragState.startY;
    if (Math.abs(deltaX) > 4 || Math.abs(deltaY) > 4) dragState.moved = true;

    const nextLeft = clamp(dragState.left + deltaX, 4, Math.max(4, window.innerWidth - dragState.width - 4));
    const nextTop = clamp(dragState.top + deltaY, 4, Math.max(4, window.innerHeight - 32));

    panel.style.left = `${nextLeft}px`;
    panel.style.top = `${nextTop}px`;
    panel.style.right = "auto";
    event.preventDefault();
  }

  function endDrag(event) {
    if (!dragState || event.pointerId !== dragState.pointerId) return;
    const wasClick = !dragState.moved;
    if (event.currentTarget.hasPointerCapture?.(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
    dragState = null;
    if (wasClick && event.type !== "pointercancel") {
      collapsed = !collapsed;
      refreshNow();
    }
  }

  function normalizedText(el) {
    return (el?.innerText || el?.textContent || "").replace(/\s+/g, " ").trim();
  }

  function cleanQuestionText(text) {
    return String(text || "")
      .replace(/^(User|You|Human|用户|我)\b[:：]?\s*/i, "")
      .replace(/\b(Copy|Edit|Retry|Fork|Regenerate)\b/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function cssEscape(value) {
    if (window.CSS && typeof CSS.escape === "function") return CSS.escape(value);
    return String(value).replace(/["\\]/g, "\\$&");
  }

  function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  function getBridgeSource() {
    const source = window.__codexThreadTocSource;
    if (!source || typeof source !== "object") return null;
    if (!source.conversationId || typeof source.getItems !== "function") return null;
    return source;
  }

  function bridgeComplete(source = getBridgeSource()) {
    if (!source) return null;
    try {
      const value = source.isConversationHistoryComplete;
      return typeof value === "function" ? Boolean(value()) : Boolean(value);
    } catch {
      return null;
    }
  }

  function readBridgeItems(source = getBridgeSource()) {
    if (!source) return [];
    let raw;
    try {
      raw = source.getItems();
    } catch {
      raw = [];
    }
    if (!Array.isArray(raw)) return [];

    const seen = new Set();
    const next = [];
    for (const entry of raw) {
      const id = entry?.id;
      if (!id || seen.has(id)) continue;
      const index = next.length;
      const label = cleanQuestionText(entry.label);
      next.push({
        id,
        index,
        label,
        turnKey: entry.turnKey || "",
        type: "bridge",
        conversationId: source.conversationId
      });
      seen.add(id);
      if (next.length >= MAX_ITEMS) break;
    }
    return next;
  }

  function contextKey() {
    const source = getBridgeSource();
    if (source) return `bridge:${source.conversationId}`;
    return `href:${location.href}`;
  }

  function resetModel(nextKey = contextKey()) {
    routeKey = nextKey;
    railSignature = "";
    modelSource = "empty";
    items = [];
    labelsById = new Map();
  }

  function ensureContext() {
    const nextKey = contextKey();
    if (routeKey !== nextKey) resetModel(nextKey);
  }

  function getRailRoot() {
    return document.querySelector(RAIL_LIST_SELECTOR) || document;
  }

  function getRailButtons() {
    return [...getRailRoot().querySelectorAll(RAIL_BUTTON_SELECTOR)]
      .filter((button) => button instanceof HTMLElement)
      .slice(0, MAX_ITEMS);
  }

  function getRailButtonById(id) {
    return document.querySelector(`${RAIL_BUTTON_SELECTOR}[data-thread-user-message-navigation-item-id="${cssEscape(id)}"]`);
  }

  function railIdsFromButtons(buttons) {
    const ids = [];
    const seen = new Set();
    for (const button of buttons) {
      const id = button.dataset.threadUserMessageNavigationItemId;
      if (!id || seen.has(id)) continue;
      ids.push(id);
      seen.add(id);
    }
    return ids.slice(0, MAX_ITEMS);
  }

  function getUserAnchors() {
    const anchors = [...document.querySelectorAll(USER_ANCHOR_SELECTOR)]
      .filter((anchor) => anchor instanceof HTMLElement && !anchor.closest(`#${TOC_ID}`));
    if (anchors.length > 0) return anchors.slice(0, MAX_ITEMS);

    return [...document.querySelectorAll(USER_BUBBLE_SELECTOR)]
      .map((bubble) => bubble.closest(SEARCH_UNIT_SELECTOR) || bubble)
      .filter((anchor, index, all) => anchor instanceof HTMLElement && all.indexOf(anchor) === index && !anchor.closest(`#${TOC_ID}`))
      .slice(0, MAX_ITEMS);
  }

  function getExactAnchorById(id) {
    const unit = document.querySelector(`${SEARCH_UNIT_SELECTOR}[data-content-search-unit-key="${cssEscape(id)}"]`);
    return unit instanceof HTMLElement ? unit : null;
  }

  function readAnchorLabel(id) {
    const anchor = getExactAnchorById(id);
    if (!anchor) return "";
    const bubble = anchor.querySelector(USER_BUBBLE_SELECTOR) || anchor;
    return cleanQuestionText(normalizedText(bubble));
  }

  function anchorId(anchor, index) {
    const unit = anchor.closest(SEARCH_UNIT_SELECTOR);
    if (unit?.dataset.contentSearchUnitKey) return unit.dataset.contentSearchUnitKey;
    if (anchor.dataset.contentSearchUnitKey) return anchor.dataset.contentSearchUnitKey;
    return `mounted:${index}:${cleanQuestionText(normalizedText(anchor)).slice(0, 80)}`;
  }

  function readMountedAnchorLabel(anchor) {
    const bubble = anchor.querySelector(USER_BUBBLE_SELECTOR) || anchor;
    return cleanQuestionText(normalizedText(bubble));
  }

  function getMountedAnchorById(id) {
    return getUserAnchors().find((anchor, index) => anchorId(anchor, index) === id) || null;
  }

  function defaultLabel(index) {
    return `Question ${index + 1}`;
  }

  function itemLabel(item) {
    return labelsById.get(item.id) || defaultLabel(item.index);
  }

  function pruneLabels(ids, source) {
    const next = new Map();
    for (const id of ids) {
      if (source.has(id)) next.set(id, source.get(id));
    }
    return next;
  }

  function syncBridgeItems(source) {
    routeKey = `bridge:${source.conversationId}`;
    railSignature = "";
    modelSource = "bridge";

    const oldLabels = labelsById;
    const nextItems = readBridgeItems(source);
    const ids = nextItems.map((item) => item.id);
    labelsById = pruneLabels(ids, oldLabels);
    for (const entry of nextItems) {
      if (entry.label) labelsById.set(entry.id, entry.label);
    }
    items = nextItems;
  }

  function syncRailItems(ids) {
    const signature = ids.join("\0");
    const oldLabels = labelsById;
    labelsById = pruneLabels(ids, oldLabels);
    items = ids.map((id, index) => ({ id, index, type: "rail" }));
    railSignature = signature;
    modelSource = ids.length > 0 ? "rail" : "empty";
    routeKey = contextKey();
    ids.forEach((id) => {
      const label = readAnchorLabel(id);
      if (label) labelsById.set(id, label);
    });
  }

  function syncAnchorItems(anchors) {
    const nextItems = [];
    const nextLabels = new Map();
    const seen = new Set();

    anchors.forEach((anchor, anchorIndex) => {
      const id = anchorId(anchor, anchorIndex);
      if (!id || seen.has(id)) return;
      const label = readMountedAnchorLabel(anchor);
      const index = nextItems.length;
      nextItems.push({ id, index, type: "anchor" });
      seen.add(id);
      if (label) nextLabels.set(id, label);
    });

    routeKey = contextKey();
    railSignature = "";
    modelSource = nextItems.length > 0 ? "fallback" : "empty";
    items = nextItems;
    labelsById = nextLabels;
  }

  function syncItems() {
    ensureContext();

    const source = getBridgeSource();
    if (source) {
      syncBridgeItems(source);
      return;
    }

    const railIds = railIdsFromButtons(getRailButtons());
    if (railIds.length > 0) {
      if (modelSource !== "rail" || railSignature !== railIds.join("\0")) syncRailItems(railIds);
      return;
    }

    const anchors = getUserAnchors();
    if (anchors.length > 0) {
      syncAnchorItems(anchors);
      return;
    }

    resetModel();
  }

  function refreshVisibleLabels() {
    for (const item of items) {
      if (labelsById.has(item.id)) continue;
      const label = readAnchorLabel(item.id);
      if (label) labelsById.set(item.id, label);
    }
  }

  async function readTooltipLabel(button) {
    try {
      button.focus({ preventScroll: true });
    } catch {
      button.focus?.();
    }
    button.dispatchEvent(new MouseEvent("mouseenter", { bubbles: true, cancelable: true }));
    await sleep(180);
    const tooltip = document.querySelector("[data-thread-user-message-navigation-tooltip-preview]");
    const label = tooltip?.querySelector(".font-medium") || tooltip;
    const text = cleanQuestionText(normalizedText(label));
    button.dispatchEvent(new MouseEvent("mouseleave", { bubbles: true, cancelable: true }));
    button.blur?.();
    return text;
  }

  async function fillMissingLabels() {
    if (labelReadInFlight) return;
    labelReadInFlight = true;
    try {
      for (const item of items) {
        if (labelsById.has(item.id)) continue;
        const direct = readAnchorLabel(item.id);
        if (direct) {
          labelsById.set(item.id, direct);
          scheduleRefresh();
          continue;
        }
        if (item.type !== "rail") continue;
        const button = getRailButtonById(item.id);
        if (!button) continue;
        const tooltip = await readTooltipLabel(button);
        if (tooltip) {
          labelsById.set(item.id, tooltip);
          scheduleRefresh();
        }
      }
    } finally {
      labelReadInFlight = false;
    }
  }

  function highlightAnchor(anchor) {
    const target = anchor?.querySelector?.(USER_BUBBLE_SELECTOR) || anchor;
    if (!target?.classList) return;
    target.classList.add("codex-toc-hit");
    setTimeout(() => target.classList.remove("codex-toc-hit"), 950);
  }

  function clickRailButtonById(id) {
    const button = getRailButtonById(id);
    if (!button) return false;
    button.click();
    return true;
  }

  async function revealViaBridge(item) {
    const source = getBridgeSource();
    if (!source || source.conversationId !== item.conversationId) return false;
    if (typeof source.reveal !== "function") return false;
    try {
      await source.reveal(item.id);
      await finishTargetReveal(item.id);
      return true;
    } catch {
      return false;
    }
  }

  async function finishTargetReveal(id) {
    await sleep(160);
    const label = readAnchorLabel(id);
    if (label) labelsById.set(id, label);
    highlightAnchor(getExactAnchorById(id));
    refreshNow();
  }

  function revealKnownItem(item) {
    if (clickRailButtonById(item.id)) return true;
    const anchor = getExactAnchorById(item.id) || getMountedAnchorById(item.id);
    if (!anchor) return false;
    anchor.scrollIntoView({ block: "start", behavior: "smooth" });
    highlightAnchor(anchor);
    return true;
  }

  function revealNearestKnownItem(target) {
    const targetIndex = Math.max(0, items.findIndex((item) => item.id === target.id));
    const candidates = items
      .map((item, index) => ({ item, index, distance: Math.abs(index - targetIndex) }))
      .sort((left, right) => left.distance - right.distance || left.index - right.index);

    for (const candidate of candidates) {
      if (candidate.item.id === target.id) continue;
      if (revealKnownItem(candidate.item)) return true;
    }
    return false;
  }

  async function scrollToItem(item) {
    const current = items.find((candidate) => candidate.id === item.id) || item;
    if (!current) {
      refreshNow();
      return;
    }

    if (await revealViaBridge(current)) return;

    if (clickRailButtonById(current.id)) {
      await finishTargetReveal(current.id);
      return;
    }

    const bridged = revealNearestKnownItem(current);
    if (!bridged) return;

    await sleep(260);
    if (await revealViaBridge(current)) return;
    if (clickRailButtonById(current.id)) {
      await finishTargetReveal(current.id);
      return;
    }

    const targetAnchor = getExactAnchorById(current.id) || getMountedAnchorById(current.id);
    if (targetAnchor) {
      targetAnchor.scrollIntoView({ block: "start", behavior: "smooth" });
      highlightAnchor(targetAnchor);
      refreshNow();
    }
  }

  function isActive(item) {
    return getRailButtonById(item.id)?.getAttribute("aria-current") === "true";
  }

  async function loadBridgeHistoryIfNeeded() {
    const source = getBridgeSource();
    if (!visible || !source || bridgeComplete(source) !== false) return;
    const key = source.conversationId;
    if (historyLoadInFlight || historyLoadAttemptedKey === key) return;
    if (typeof source.loadAllHistory !== "function") return;

    historyLoadInFlight = true;
    historyLoadAttemptedKey = key;
    try {
      await source.loadAllHistory();
      await sleep(240);
    } finally {
      historyLoadInFlight = false;
    }

    if (getBridgeSource()?.conversationId === key) {
      syncItems();
      refreshNow();
    }
  }

  function renderPanel() {
    const el = ensurePanel();
    el.innerHTML = "";
    el.dataset.collapsed = collapsed ? "true" : "false";

    const header = document.createElement("div");
    header.className = "toc-header";
    header.addEventListener("pointerdown", startDrag);
    header.addEventListener("pointermove", moveDrag);
    header.addEventListener("pointerup", endDrag);
    header.addEventListener("pointercancel", endDrag);
    header.addEventListener("lostpointercapture", endDrag);

    const title = document.createElement("div");
    title.className = "toc-title";
    title.textContent = `User Questions (${items.length})`;

    const actions = document.createElement("div");
    actions.className = "toc-actions";

    const close = document.createElement("button");
    close.className = "toc-icon";
    close.textContent = "x";
    close.title = "Hide TOC (Ctrl+Alt+O)";
    close.addEventListener("click", () => setVisible(false));

    actions.append(close);
    header.append(title, actions);
    el.appendChild(header);

    const body = document.createElement("div");
    body.className = "toc-body";
    el.appendChild(body);

    if (items.length === 0) {
      const empty = document.createElement("div");
      empty.className = "toc-empty";
      empty.textContent = "No user questions found yet.";
      body.appendChild(empty);
      return;
    }

    items.forEach((item, index) => {
      const btn = document.createElement("button");
      btn.className = `toc-item${isActive(item) ? " is-active" : ""}`;
      btn.title = itemLabel(item);

      const kind = document.createElement("span");
      kind.className = "toc-kind";
      kind.textContent = String(index + 1).padStart(2, "0");

      const text = document.createElement("span");
      text.className = "toc-text";
      text.textContent = itemLabel(item).slice(0, 120);

      btn.append(kind, text);
      btn.addEventListener("click", () => scrollToItem(item));
      body.appendChild(btn);
    });
  }

  function refreshNow() {
    if (!visible) return;
    syncItems();
    refreshVisibleLabels();
    renderPanel();
    fillMissingLabels();
    loadBridgeHistoryIfNeeded();
  }

  function scheduleRefresh() {
    if (!visible) return;
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(refreshNow, 120);
  }

  function mutationTouchesToc(mutation) {
    const panel = document.getElementById(TOC_ID);
    if (!panel) return false;
    if (mutation.target === panel || panel.contains(mutation.target)) return true;
    const nodes = [...mutation.addedNodes, ...mutation.removedNodes];
    return nodes.some((node) => node === panel || (node instanceof Node && panel.contains(node)));
  }

  function handleMutations(mutations) {
    if (mutations.length > 0 && mutations.every(mutationTouchesToc)) return;
    ensureToolbarButton();
    syncItems();
    scheduleRefresh();
  }

  function setVisible(next) {
    visible = next;
    if (visible) collapsed = false;
    const el = ensurePanel();
    el.hidden = !visible;
    if (visible) refreshNow();
    updateToolbarButton();
  }

  document.addEventListener("keydown", (event) => {
    if (event.ctrlKey && event.altKey && event.code === HOTKEY) {
      event.preventDefault();
      event.stopPropagation();
      setVisible(!visible);
    }
  }, true);

  const observer = new MutationObserver(handleMutations);

  function boot() {
    ensurePanel();
    ensureToolbarButton();
    routeKey = contextKey();
    observer.observe(document.body, {
      childList: true,
      subtree: true,
      characterData: true,
      attributes: true,
      attributeFilter: ["aria-current", "data-thread-user-message-navigation-item-id"]
    });
    syncItems();
    window.__codexThreadToc = {
      show: () => setVisible(true),
      hide: () => setVisible(false),
      toggle: () => setVisible(!visible),
      refresh: () => {
        historyLoadAttemptedKey = "";
        refreshNow();
      },
      state: () => {
        const source = getBridgeSource();
        return {
          source: modelSource,
          count: items.length,
          bridgeCount: source ? readBridgeItems(source).length : 0,
          bridgeComplete: bridgeComplete(source),
          conversationId: source?.conversationId || null,
          railButtonCount: railIdsFromButtons(getRailButtons()).length,
          hasRailModel: modelSource === "rail",
          historyLoadInFlight,
          routeKey
        };
      }
    };
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();

JS
}

patch_index() {
  if grep -Fq "$MARKER_START" "$index_html"; then
    info "index.html already contains Codex TOC marker"
    return
  fi

  if ! grep -Fq '</head>' "$index_html"; then
    die "index.html does not contain </head>; refusing to patch"
  fi

  if [[ ! -f "$backup_html" || $force -eq 1 ]]; then
    if [[ $dry_run -eq 1 ]]; then
      info "dry-run: would backup $index_html to $backup_html"
    else
      cp "$index_html" "$backup_html"
      info "created backup: $backup_html"
    fi
  else
    info "backup already exists: $backup_html"
  fi

  if [[ $dry_run -eq 1 ]]; then
    info "dry-run: would inject script tag into $index_html"
    return
  fi

  python3 - "$index_html" "$MARKER_START" "$MARKER_END" "$INJECT_FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
marker_start = sys.argv[2]
marker_end = sys.argv[3]
inject_file = sys.argv[4]
text = path.read_text(encoding="utf-8")
snippet = f'    {marker_start}\n    <script defer src="./{inject_file}"></script>\n    {marker_end}\n'
if marker_start in text:
    raise SystemExit(0)
if "</head>" not in text:
    raise SystemExit("missing </head>")
text = text.replace("</head>", snippet + "  </head>", 1)
path.write_text(text, encoding="utf-8")
PY
}

patch_rail_gate() {
  if [[ -z "$rail_bundle" ]]; then
    die "could not find webview/assets/local-conversation-thread-*.js; refusing to patch rail gate"
  fi

  if grep -Fq "$RAIL_GATE_PATCHED" "$rail_bundle"; then
    info "rail gate already patched: $rail_bundle"
    return
  fi

  if ! grep -Fq "$RAIL_GATE_NEEDLE" "$rail_bundle"; then
    die "rail gate pattern not found in $rail_bundle"
  fi

  ensure_rail_bundle_backup

  if [[ $dry_run -eq 1 ]]; then
    info "dry-run: would enable built-in user-message rail in $rail_bundle"
    return
  fi

  python3 - "$rail_bundle" "$RAIL_GATE_NEEDLE" "$RAIL_GATE_PATCHED" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
needle = sys.argv[2]
patched = sys.argv[3]
text = path.read_text(encoding="utf-8")
if patched in text:
    raise SystemExit(0)
if needle not in text:
    raise SystemExit("rail gate pattern not found")
text = text.replace(needle, patched, 1)
path.write_text(text, encoding="utf-8")
PY
}

ensure_rail_bundle_backup() {
  if [[ -z "$rail_bundle" ]]; then
    die "could not find webview/assets/local-conversation-thread-*.js"
  fi

  if [[ $rail_bundle_backup_done -eq 1 ]]; then
    return
  fi
  rail_bundle_backup_done=1

  if [[ ! -f "$rail_bundle_backup" || $force -eq 1 ]]; then
    if [[ $dry_run -eq 1 ]]; then
      info "dry-run: would backup $rail_bundle to $rail_bundle_backup"
    else
      cp "$rail_bundle" "$rail_bundle_backup"
      info "created backup: $rail_bundle_backup"
    fi
  else
    info "backup already exists: $rail_bundle_backup"
  fi
}

patch_toc_bridge() {
  if [[ -z "$rail_bundle" ]]; then
    die "could not find webview/assets/local-conversation-thread-*.js; refusing to patch TOC bridge"
  fi

  if grep -Fq "$TOC_BRIDGE_MARKER" "$rail_bundle"; then
    info "TOC bridge already patched: $rail_bundle"
    return
  fi

  if ! grep -Fq "$TOC_BRIDGE_NEEDLE" "$rail_bundle"; then
    die "TOC bridge pattern not found in $rail_bundle"
  fi

  ensure_rail_bundle_backup

  if [[ $dry_run -eq 1 ]]; then
    info "dry-run: would install TOC conversation bridge in $rail_bundle"
    return
  fi

  python3 - "$rail_bundle" "$TOC_BRIDGE_NEEDLE" "$TOC_BRIDGE_SNIPPET" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
needle = sys.argv[2]
snippet = sys.argv[3]
text = path.read_text(encoding="utf-8")
if "__codexThreadTocSource" in text:
    raise SystemExit(0)
if needle not in text:
    raise SystemExit("TOC bridge pattern not found")
patched = "});" + snippet + needle[3:]
text = text.replace(needle, patched, 1)
path.write_text(text, encoding="utf-8")
PY
}

unpatch_index() {
  if [[ $dry_run -eq 1 ]]; then
    info "dry-run: would remove injected block from $index_html"
    info "dry-run: would remove $inject_js"
    return
  fi

  python3 - "$index_html" "$MARKER_START" "$MARKER_END" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
marker_start = re.escape(sys.argv[2])
marker_end = re.escape(sys.argv[3])
text = path.read_text(encoding="utf-8")
pattern = re.compile(r"\n?[ \t]*" + marker_start + r".*?" + marker_end + r"\n?", re.S)
text, count = pattern.subn("\n", text, count=1)
path.write_text(text, encoding="utf-8")
print(f"removed injected block: {count}")
PY

  if [[ -f "$inject_js" ]]; then
    rm "$inject_js"
    info "removed $inject_js"
  fi
}

unpatch_rail_gate() {
  if [[ -z "$rail_bundle" ]]; then
    info "rail bundle not found; skipping rail gate unpatch"
    return
  fi

  if [[ $dry_run -eq 1 ]]; then
    info "dry-run: would restore rail gate in $rail_bundle"
    return
  fi

  if grep -Fq "$RAIL_GATE_PATCHED" "$rail_bundle"; then
    python3 - "$rail_bundle" "$RAIL_GATE_NEEDLE" "$RAIL_GATE_PATCHED" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
needle = sys.argv[2]
patched = sys.argv[3]
text = path.read_text(encoding="utf-8")
text = text.replace(patched, needle, 1)
path.write_text(text, encoding="utf-8")
PY
    info "restored rail gate: $rail_bundle"
  else
    info "rail gate is not patched: $rail_bundle"
  fi
}

unpatch_toc_bridge() {
  if [[ -z "$rail_bundle" ]]; then
    info "rail bundle not found; skipping TOC bridge unpatch"
    return
  fi

  if [[ $dry_run -eq 1 ]]; then
    info "dry-run: would remove TOC conversation bridge from $rail_bundle"
    return
  fi

  if grep -Fq "$TOC_BRIDGE_MARKER" "$rail_bundle"; then
    python3 - "$rail_bundle" "$TOC_BRIDGE_NEEDLE" "$TOC_BRIDGE_SNIPPET" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
needle = sys.argv[2]
snippet = sys.argv[3]
text = path.read_text(encoding="utf-8")
patched = "});" + snippet + needle[3:]
text = text.replace(patched, needle, 1)
path.write_text(text, encoding="utf-8")
PY
    info "removed TOC bridge: $rail_bundle"
  else
    info "TOC bridge is not patched: $rail_bundle"
  fi
}

if [[ $unpatch -eq 1 ]]; then
  unpatch_toc_bridge
  unpatch_rail_gate
  unpatch_index
  info "unpatch complete. Reload VS Code."
  exit 0
fi

require_supported_rail_gate
require_supported_toc_bridge
patch_index
patch_rail_gate
patch_toc_bridge
write_inject_js

if [[ $dry_run -eq 1 ]]; then
  info "dry-run complete: no files were changed"
else
  info "patch complete: $extension_dir"
  info "Reload VS Code, then press Ctrl+Alt+O or the TOC header button inside the Codex panel."
  info "To remove: $SCRIPT_NAME --extension-dir \"$extension_dir\" --unpatch"
fi
