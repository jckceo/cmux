# Spaces: Workspace Grouping in the Sidebar

## Summary

Add "Spaces" to the cmux sidebar — collapsible named groups that organize workspaces by project. Ungrouped workspaces remain at root level as they do today. Spaces show an aggregated notification badge when collapsed.

## Motivation

Users working on multiple projects simultaneously end up with many workspaces in a flat list. Spaces let them visually organize workspaces by project, collapse groups they're not actively using, and still see at a glance which groups have pending notifications.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Ungrouped workspaces | Stay at root level (not forced into a Space) | Zero change for users who don't use Spaces |
| Nesting depth | Single level only (Space → Workspace) | Keeps it simple, like Discord categories |
| Visual style | Colored tree line (optional color) | Lightweight, clear grouping without heavy chrome |
| Creation | Both "+" / Command Palette AND right-click on workspace | Maximum discoverability |
| Moving workspaces | Drag & drop only | Consistent with existing workspace reordering |
| Collapsed notifications | Badge count only (no glow, no workspace names) | Minimalist, not noisy |

## Data Model

### New: `Space` struct (in TabManager.swift)

```swift
struct Space: Identifiable, Codable {
    let id: UUID
    var name: String
    var color: String?       // optional hex, e.g. "#8b5cf6"
    var isCollapsed: Bool
}
```

### Modified: `Workspace`

```swift
@Published var spaceId: UUID?   // nil = ungrouped (root level)
```

### Modified: `TabManager`

```swift
@Published var spaces: [Space] = []   // order = sidebar order
```

The flat `tabs: [Workspace]` array remains the source of truth for workspace ordering. A workspace's position within its Space is determined by its relative position in the flat array. For example, if `tabs = [A, B, C, D, E]` and B, D have `spaceId = X`, then Space X shows B then D.

## Session Persistence

### New: `SessionSpaceSnapshot`

```swift
struct SessionSpaceSnapshot: Codable, Sendable {
    var id: UUID
    var name: String
    var color: String?
    var isCollapsed: Bool
}
```

### Modified: `SessionTabManagerSnapshot`

```swift
var spaces: [SessionSpaceSnapshot]   // default [] for backward compat
```

### Modified: `SessionWorkspaceSnapshot`

```swift
var spaceId: UUID?   // default nil for backward compat
```

Schema version remains 1 — all new fields are optional with defaults, so old session files load without migration.

## Sidebar UI

### Rendering order

1. Ungrouped workspaces (spaceId == nil) in flat array order
2. Each Space (in `tabManager.spaces` order), containing its workspaces filtered from the flat array preserving relative order

### Space header

- Collapse toggle arrow (▼/▶) + optional color square + name + notification badge (when collapsed)
- Click header or arrow → toggle collapse
- Right-click → context menu: Rename, Set Color, Remove Space (moves workspaces back to root)
- Badge shows sum of unread notifications across contained workspaces, only visible when collapsed

### Workspace indentation

- Workspaces inside a Space are indented with a vertical line
- If the Space has a color, the line uses that color; otherwise a subtle gray

### Drag & drop

- **Workspace → Space header**: sets `workspace.spaceId = space.id`
- **Workspace → ungrouped area / SidebarEmptyArea**: sets `workspace.spaceId = nil`
- **Workspace within a Space**: normal flat array reorder, clamped to Space boundaries
- **Space header drag**: reorder Spaces among themselves (new UTType `com.cmux.sidebar-space-reorder`)

### Creation

- Command Palette / sidebar "+": "New Space" action — prompts for name, creates empty Space
- Right-click workspace: "New Space from Workspace..." — creates a new Space and assigns this workspace to it

### Localization

All user-facing strings use `String(localized:defaultValue:)` per project conventions.

## Edge Cases

- **Empty Space after closing workspaces**: Space persists until manually removed
- **Last workspace**: cannot close the last workspace regardless of Spaces (existing behavior)
- **Pinned + Space**: pinned workspaces can belong to a Space. Pinned clamping takes priority over Space clamping (pinned stays at top of its Space)
- **Auto-reorder on notification**: reorders within the workspace's Space only, never moves across Spaces
- **Orphaned spaceId on restore**: if a workspace's spaceId doesn't match any Space, workspace falls back to root (graceful degradation)
- **Cmd+Shift+U (jump to unread)**: if target workspace is in a collapsed Space, auto-expand that Space
- **Max Spaces**: capped at 32 per window

## Performance

- `TabItemView.equatable()` is untouched — Space headers are separate components that don't interfere with typing latency
- Grouped list computation is O(n) on the flat array — negligible with max 128 workspaces
- Space headers receive precomputed badge counts, not workspace `@ObservedObject` references, to avoid cascade re-renders

## Testing

- Space CRUD on TabManager (create, rename, set color, delete, reorder)
- Workspace move to/from Space, verify flat array order preserved
- Badge aggregation count for collapsed Space
- Session persistence round-trip with Spaces (save → restore → verify)
- Backward compat: restore session without Spaces (old format)
- Graceful fallback for orphaned spaceId
- Pinned workspace clamping within a Space

## Build & Test Isolation

All development builds use `./scripts/reload.sh --tag spaces` to create an isolated app (`cmux DEV spaces.app`) with its own bundle ID, socket, and derived data path. This runs side-by-side with the production cmux without interference.
