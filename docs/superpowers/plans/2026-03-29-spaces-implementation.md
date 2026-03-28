# Spaces (Workspace Grouping) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add collapsible named "Spaces" to the cmux sidebar that group workspaces by project, with drag & drop, notification badges, and session persistence.

**Architecture:** Spaces are lightweight `Space` structs stored in `TabManager.spaces`. Each `Workspace` gets an optional `spaceId: UUID?`. The flat `tabs` array remains the source of truth for ordering. The sidebar groups workspaces by `spaceId` at render time. Session persistence adds optional fields with backward-compatible defaults.

**Tech Stack:** Swift, SwiftUI, AppKit, XCTest

**Build & test isolation:** All builds use `./scripts/reload.sh --tag spaces` to produce an isolated `cmux DEV spaces.app` that runs side-by-side with production cmux.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/TabManager.swift` | Modify | Add `Space` struct, `spaces` array, CRUD methods, reorder clamping |
| `Sources/Workspace.swift` | Modify | Add `spaceId` property, snapshot/restore |
| `Sources/SessionPersistence.swift` | Modify | Add `SessionSpaceSnapshot`, extend snapshot structs |
| `Sources/ContentView.swift` | Modify | Sidebar grouped rendering, Space header view, drag & drop |
| `cmuxTests/SpacesUnitTests.swift` | Create | All Space-related unit tests |

---

### Task 1: Space Model and TabManager CRUD

**Files:**
- Modify: `Sources/TabManager.swift` (add Space struct at ~line 10, add properties at ~line 692, add methods)
- Create: `cmuxTests/SpacesUnitTests.swift`

- [ ] **Step 1: Write failing tests for Space CRUD**

Create `cmuxTests/SpacesUnitTests.swift`:

```swift
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class SpacesCRUDTests: XCTestCase {
    func testAddSpaceAppendsToSpacesArray() {
        let manager = TabManager()
        let space = manager.addSpace(name: "Project A")
        XCTAssertEqual(manager.spaces.count, 1)
        XCTAssertEqual(manager.spaces[0].id, space.id)
        XCTAssertEqual(manager.spaces[0].name, "Project A")
        XCTAssertNil(manager.spaces[0].color)
        XCTAssertFalse(manager.spaces[0].isCollapsed)
    }

    func testAddMultipleSpacesPreservesOrder() {
        let manager = TabManager()
        let spaceA = manager.addSpace(name: "A")
        let spaceB = manager.addSpace(name: "B")
        XCTAssertEqual(manager.spaces.map(\.id), [spaceA.id, spaceB.id])
    }

    func testRenameSpace() {
        let manager = TabManager()
        let space = manager.addSpace(name: "Old Name")
        manager.renameSpace(spaceId: space.id, name: "New Name")
        XCTAssertEqual(manager.spaces[0].name, "New Name")
    }

    func testSetSpaceColor() {
        let manager = TabManager()
        let space = manager.addSpace(name: "Project")
        manager.setSpaceColor(spaceId: space.id, color: "#8b5cf6")
        XCTAssertEqual(manager.spaces[0].color, "#8B5CF6")
    }

    func testClearSpaceColor() {
        let manager = TabManager()
        let space = manager.addSpace(name: "Project")
        manager.setSpaceColor(spaceId: space.id, color: "#8b5cf6")
        manager.setSpaceColor(spaceId: space.id, color: nil)
        XCTAssertNil(manager.spaces[0].color)
    }

    func testToggleSpaceCollapsed() {
        let manager = TabManager()
        let space = manager.addSpace(name: "Project")
        XCTAssertFalse(manager.spaces[0].isCollapsed)
        manager.toggleSpaceCollapsed(spaceId: space.id)
        XCTAssertTrue(manager.spaces[0].isCollapsed)
        manager.toggleSpaceCollapsed(spaceId: space.id)
        XCTAssertFalse(manager.spaces[0].isCollapsed)
    }

    func testRemoveSpaceClearsWorkspaceSpaceIds() {
        let manager = TabManager()
        let space = manager.addSpace(name: "Project")
        let workspace = manager.addWorkspace()
        manager.moveWorkspaceToSpace(workspaceId: workspace.id, spaceId: space.id)
        XCTAssertEqual(workspace.spaceId, space.id)

        manager.removeSpace(spaceId: space.id)
        XCTAssertEqual(manager.spaces.count, 0)
        XCTAssertNil(workspace.spaceId)
    }

    func testRemoveSpaceWithUnknownIdIsNoOp() {
        let manager = TabManager()
        manager.addSpace(name: "Project")
        manager.removeSpace(spaceId: UUID())
        XCTAssertEqual(manager.spaces.count, 1)
    }

    func testReorderSpaces() {
        let manager = TabManager()
        let spaceA = manager.addSpace(name: "A")
        let spaceB = manager.addSpace(name: "B")
        let spaceC = manager.addSpace(name: "C")
        manager.reorderSpace(spaceId: spaceB.id, toIndex: 0)
        XCTAssertEqual(manager.spaces.map(\.id), [spaceB.id, spaceA.id, spaceC.id])
    }

    func testMaxSpacesCap() {
        let manager = TabManager()
        for i in 0..<32 {
            manager.addSpace(name: "Space \(i)")
        }
        XCTAssertEqual(manager.spaces.count, 32)
        manager.addSpace(name: "Over limit")
        XCTAssertEqual(manager.spaces.count, 32)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-spaces build-for-testing 2>&1 | tail -20`

Expected: Compilation errors — `Space`, `addSpace`, `moveWorkspaceToSpace` etc. don't exist yet.

- [ ] **Step 3: Add Space struct and TabManager methods**

In `Sources/TabManager.swift`, after the `typealias Tab = Workspace` line (line 10), add:

```swift
// MARK: - Spaces (Workspace Grouping)

struct Space: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var color: String?
    var isCollapsed: Bool

    init(id: UUID = UUID(), name: String, color: String? = nil, isCollapsed: Bool = false) {
        self.id = id
        self.name = name
        self.color = color
        self.isCollapsed = isCollapsed
    }
}
```

In the TabManager class, after `@Published var selectedTabId: UUID?` (around line 703), add:

```swift
@Published var spaces: [Space] = []
private static let maxSpacesPerWindow: Int = 32
```

At the end of the TabManager class (before the closing `}`), add a new MARK section:

```swift
// MARK: - Space Management

@discardableResult
func addSpace(name: String, color: String? = nil) -> Space {
    guard spaces.count < Self.maxSpacesPerWindow else { return spaces.last! }
    let space = Space(name: name, color: color.flatMap { WorkspaceTabColorSettings.normalizedHex($0) })
    spaces.append(space)
    return space
}

func renameSpace(spaceId: UUID, name: String) {
    guard let index = spaces.firstIndex(where: { $0.id == spaceId }) else { return }
    spaces[index].name = name
}

func setSpaceColor(spaceId: UUID, color: String?) {
    guard let index = spaces.firstIndex(where: { $0.id == spaceId }) else { return }
    spaces[index].color = color.flatMap { WorkspaceTabColorSettings.normalizedHex($0) }
}

func toggleSpaceCollapsed(spaceId: UUID) {
    guard let index = spaces.firstIndex(where: { $0.id == spaceId }) else { return }
    spaces[index].isCollapsed.toggle()
}

func removeSpace(spaceId: UUID) {
    guard spaces.contains(where: { $0.id == spaceId }) else { return }
    for tab in tabs where tab.spaceId == spaceId {
        tab.spaceId = nil
    }
    spaces.removeAll { $0.id == spaceId }
}

func reorderSpace(spaceId: UUID, toIndex targetIndex: Int) {
    guard let currentIndex = spaces.firstIndex(where: { $0.id == spaceId }) else { return }
    let clamped = max(0, min(targetIndex, spaces.count - 1))
    if currentIndex == clamped { return }
    let space = spaces.remove(at: currentIndex)
    spaces.insert(space, at: clamped)
}

func moveWorkspaceToSpace(workspaceId: UUID, spaceId: UUID?) {
    guard let workspace = tabs.first(where: { $0.id == workspaceId }) else { return }
    if let spaceId, !spaces.contains(where: { $0.id == spaceId }) { return }
    workspace.spaceId = spaceId
}

func expandSpaceIfNeeded(containingWorkspaceId workspaceId: UUID) {
    guard let workspace = tabs.first(where: { $0.id == workspaceId }),
          let spaceId = workspace.spaceId,
          let index = spaces.firstIndex(where: { $0.id == spaceId }),
          spaces[index].isCollapsed else { return }
    spaces[index].isCollapsed = false
}
```

- [ ] **Step 4: Add spaceId to Workspace**

In `Sources/Workspace.swift`, after `@Published var customColor: String?` (line 5436), add:

```swift
@Published var spaceId: UUID?
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-spaces build-for-testing 2>&1 | tail -20`

Then: `xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-spaces test-without-building -only-testing:cmuxTests/SpacesCRUDTests 2>&1 | tail -30`

Expected: All 10 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/TabManager.swift Sources/Workspace.swift cmuxTests/SpacesUnitTests.swift
git commit -m "feat(spaces): add Space model and TabManager CRUD methods

Add Space struct with id, name, color, isCollapsed.
Add spaceId property to Workspace.
Add TabManager methods: addSpace, renameSpace, setSpaceColor,
toggleSpaceCollapsed, removeSpace, reorderSpace, moveWorkspaceToSpace,
expandSpaceIfNeeded."
```

---

### Task 2: Session Persistence

**Files:**
- Modify: `Sources/SessionPersistence.swift` (add SessionSpaceSnapshot, extend existing structs)
- Modify: `Sources/TabManager.swift` (update sessionSnapshot/restoreSessionSnapshot)
- Modify: `Sources/Workspace.swift` (update sessionSnapshot/restoreSessionSnapshot)
- Modify: `cmuxTests/SpacesUnitTests.swift` (add persistence tests)

- [ ] **Step 1: Write failing tests for persistence**

Append to `cmuxTests/SpacesUnitTests.swift`:

```swift
@MainActor
final class SpacesSessionPersistenceTests: XCTestCase {
    func testSessionSnapshotRoundTripPreservesSpaces() {
        let manager = TabManager()
        let space = manager.addSpace(name: "Project A", color: "#8b5cf6")
        let workspace = manager.addWorkspace()
        manager.moveWorkspaceToSpace(workspaceId: workspace.id, spaceId: space.id)
        manager.toggleSpaceCollapsed(spaceId: space.id)

        let snapshot = manager.sessionSnapshot(includeScrollback: false)
        XCTAssertEqual(snapshot.spaces.count, 1)
        XCTAssertEqual(snapshot.spaces[0].name, "Project A")
        XCTAssertEqual(snapshot.spaces[0].color, "#8B5CF6")
        XCTAssertTrue(snapshot.spaces[0].isCollapsed)

        let restored = TabManager()
        restored.restoreSessionSnapshot(snapshot)
        XCTAssertEqual(restored.spaces.count, 1)
        XCTAssertEqual(restored.spaces[0].name, "Project A")
        XCTAssertTrue(restored.spaces[0].isCollapsed)

        let restoredWorkspace = restored.tabs.first { $0.spaceId != nil }
        XCTAssertNotNil(restoredWorkspace)
        XCTAssertEqual(restoredWorkspace?.spaceId, restored.spaces[0].id)
    }

    func testSessionSnapshotBackwardCompatNoSpaces() {
        let snapshot = SessionTabManagerSnapshot(
            selectedWorkspaceIndex: 0,
            workspaces: [
                SessionWorkspaceSnapshot(
                    processTitle: "Terminal",
                    customTitle: nil,
                    customColor: nil,
                    isPinned: false,
                    currentDirectory: "~",
                    focusedPanelId: nil,
                    layout: SessionWorkspaceLayoutSnapshot(tree: .pane(SessionPaneLayoutSnapshot(panelId: UUID(), panelType: .terminal))),
                    panels: [],
                    statusEntries: [],
                    logEntries: [],
                    progress: nil,
                    gitBranch: nil
                )
            ]
        )

        let manager = TabManager()
        manager.restoreSessionSnapshot(snapshot)
        XCTAssertEqual(manager.spaces.count, 0)
        XCTAssertEqual(manager.tabs.count, 1)
        XCTAssertNil(manager.tabs[0].spaceId)
    }

    func testSessionSnapshotOrphanedSpaceIdFallsBackToRoot() {
        let manager = TabManager()
        let space = manager.addSpace(name: "Will Be Removed")
        let workspace = manager.addWorkspace()
        manager.moveWorkspaceToSpace(workspaceId: workspace.id, spaceId: space.id)

        var snapshot = manager.sessionSnapshot(includeScrollback: false)
        // Remove the space from snapshot but keep the workspace's spaceId
        snapshot.spaces = []

        let restored = TabManager()
        restored.restoreSessionSnapshot(snapshot)
        XCTAssertEqual(restored.spaces.count, 0)
        // Workspace should fall back to root (spaceId cleared)
        XCTAssertTrue(restored.tabs.allSatisfy { $0.spaceId == nil })
    }

    func testSessionSnapshotSpaceIdJsonCoding() throws {
        let snapshot = SessionSpaceSnapshot(
            id: UUID(),
            name: "Test",
            color: "#FF0000",
            isCollapsed: true
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSpaceSnapshot.self, from: data)
        XCTAssertEqual(decoded.id, snapshot.id)
        XCTAssertEqual(decoded.name, snapshot.name)
        XCTAssertEqual(decoded.color, snapshot.color)
        XCTAssertTrue(decoded.isCollapsed)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: Compilation errors — `SessionSpaceSnapshot`, `snapshot.spaces` don't exist yet.

- [ ] **Step 3: Add SessionSpaceSnapshot to SessionPersistence.swift**

In `Sources/SessionPersistence.swift`, before the `SessionTabManagerSnapshot` struct (line 345), add:

```swift
struct SessionSpaceSnapshot: Codable, Sendable {
    var id: UUID
    var name: String
    var color: String?
    var isCollapsed: Bool
}
```

- [ ] **Step 4: Extend SessionTabManagerSnapshot**

In `Sources/SessionPersistence.swift`, modify `SessionTabManagerSnapshot` (line 345-348) to add spaces:

```swift
struct SessionTabManagerSnapshot: Codable, Sendable {
    var selectedWorkspaceIndex: Int?
    var workspaces: [SessionWorkspaceSnapshot]
    var spaces: [SessionSpaceSnapshot]

    init(selectedWorkspaceIndex: Int? = nil, workspaces: [SessionWorkspaceSnapshot], spaces: [SessionSpaceSnapshot] = []) {
        self.selectedWorkspaceIndex = selectedWorkspaceIndex
        self.workspaces = workspaces
        self.spaces = spaces
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedWorkspaceIndex = try container.decodeIfPresent(Int.self, forKey: .selectedWorkspaceIndex)
        workspaces = try container.decode([SessionWorkspaceSnapshot].self, forKey: .workspaces)
        spaces = try container.decodeIfPresent([SessionSpaceSnapshot].self, forKey: .spaces) ?? []
    }
}
```

- [ ] **Step 5: Extend SessionWorkspaceSnapshot**

In `Sources/SessionPersistence.swift`, add `spaceId` to `SessionWorkspaceSnapshot` (line 330-343):

Add after `var gitBranch: SessionGitBranchSnapshot?`:

```swift
var spaceId: UUID?
```

Add a custom `init(from:)` to ensure backward compat:

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    processTitle = try container.decode(String.self, forKey: .processTitle)
    customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
    customColor = try container.decodeIfPresent(String.self, forKey: .customColor)
    isPinned = try container.decode(Bool.self, forKey: .isPinned)
    currentDirectory = try container.decode(String.self, forKey: .currentDirectory)
    focusedPanelId = try container.decodeIfPresent(UUID.self, forKey: .focusedPanelId)
    layout = try container.decode(SessionWorkspaceLayoutSnapshot.self, forKey: .layout)
    panels = try container.decode([SessionPanelSnapshot].self, forKey: .panels)
    statusEntries = try container.decode([SessionStatusEntrySnapshot].self, forKey: .statusEntries)
    logEntries = try container.decode([SessionLogEntrySnapshot].self, forKey: .logEntries)
    progress = try container.decodeIfPresent(SessionProgressSnapshot.self, forKey: .progress)
    gitBranch = try container.decodeIfPresent(SessionGitBranchSnapshot.self, forKey: .gitBranch)
    spaceId = try container.decodeIfPresent(UUID.self, forKey: .spaceId)
}
```

- [ ] **Step 6: Update TabManager.sessionSnapshot()**

In `Sources/TabManager.swift`, modify `sessionSnapshot(includeScrollback:)` (line 5497-5510). Replace the return statement:

```swift
func sessionSnapshot(includeScrollback: Bool) -> SessionTabManagerSnapshot {
    let restorableTabs = tabs
        .filter { !$0.isRemoteWorkspace }
        .prefix(SessionPersistencePolicy.maxWorkspacesPerWindow)
    let workspaceSnapshots = restorableTabs
        .map { $0.sessionSnapshot(includeScrollback: includeScrollback) }
    let selectedWorkspaceIndex = selectedTabId.flatMap { selectedTabId in
        restorableTabs.firstIndex(where: { $0.id == selectedTabId })
    }
    let spaceSnapshots = spaces.map { space in
        SessionSpaceSnapshot(
            id: space.id,
            name: space.name,
            color: space.color,
            isCollapsed: space.isCollapsed
        )
    }
    return SessionTabManagerSnapshot(
        selectedWorkspaceIndex: selectedWorkspaceIndex,
        workspaces: workspaceSnapshots,
        spaces: spaceSnapshots
    )
}
```

- [ ] **Step 7: Update Workspace.sessionSnapshot()**

In `Sources/Workspace.swift`, inside `sessionSnapshot(includeScrollback:)` (line 235), ensure `spaceId` is included in the returned snapshot. After the existing fields, add:

Find the `return SessionWorkspaceSnapshot(` call and add `spaceId: spaceId` to its arguments.

- [ ] **Step 8: Update Workspace.restoreSessionSnapshot()**

In `Sources/Workspace.swift`, inside `restoreSessionSnapshot(_ snapshot:)` (line 296), add after other property restorations:

```swift
spaceId = snapshot.spaceId
```

- [ ] **Step 9: Update TabManager.restoreSessionSnapshot()**

In `Sources/TabManager.swift`, inside `restoreSessionSnapshot(_ snapshot:)` (line 5522), after the `tabs = newTabs` / `selectedTabId = newSelectedId` block, add:

```swift
// Restore spaces and reconcile orphaned spaceIds.
let restoredSpaces = snapshot.spaces.map { spaceSnapshot in
    Space(
        id: spaceSnapshot.id,
        name: spaceSnapshot.name,
        color: spaceSnapshot.color,
        isCollapsed: spaceSnapshot.isCollapsed
    )
}
spaces = restoredSpaces
let validSpaceIds = Set(restoredSpaces.map(\.id))
for tab in newTabs where tab.spaceId != nil {
    if !validSpaceIds.contains(tab.spaceId!) {
        tab.spaceId = nil
    }
}
```

- [ ] **Step 10: Run tests to verify they pass**

Run: build then test `SpacesSessionPersistenceTests`.

Expected: All 4 tests PASS.

- [ ] **Step 11: Commit**

```bash
git add Sources/SessionPersistence.swift Sources/TabManager.swift Sources/Workspace.swift cmuxTests/SpacesUnitTests.swift
git commit -m "feat(spaces): add session persistence for Spaces

Add SessionSpaceSnapshot. Extend SessionTabManagerSnapshot with spaces
array and SessionWorkspaceSnapshot with spaceId. Both use optional
fields with defaults for backward compatibility with old session files.
Orphaned spaceIds are cleared on restore."
```

---

### Task 3: Workspace Move Tests and expandSpaceIfNeeded

**Files:**
- Modify: `cmuxTests/SpacesUnitTests.swift`

- [ ] **Step 1: Write tests for workspace-space assignment**

Append to `cmuxTests/SpacesUnitTests.swift`:

```swift
@MainActor
final class SpacesWorkspaceMoveTests: XCTestCase {
    func testMoveWorkspaceToSpace() {
        let manager = TabManager()
        let space = manager.addSpace(name: "Project")
        let workspace = manager.addWorkspace()
        manager.moveWorkspaceToSpace(workspaceId: workspace.id, spaceId: space.id)
        XCTAssertEqual(workspace.spaceId, space.id)
    }

    func testMoveWorkspaceToRootClearsSpaceId() {
        let manager = TabManager()
        let space = manager.addSpace(name: "Project")
        let workspace = manager.addWorkspace()
        manager.moveWorkspaceToSpace(workspaceId: workspace.id, spaceId: space.id)
        manager.moveWorkspaceToSpace(workspaceId: workspace.id, spaceId: nil)
        XCTAssertNil(workspace.spaceId)
    }

    func testMoveWorkspaceToInvalidSpaceIsNoOp() {
        let manager = TabManager()
        let workspace = manager.addWorkspace()
        manager.moveWorkspaceToSpace(workspaceId: workspace.id, spaceId: UUID())
        XCTAssertNil(workspace.spaceId)
    }

    func testExpandSpaceIfNeededExpandsCollapsedSpace() {
        let manager = TabManager()
        let space = manager.addSpace(name: "Project")
        let workspace = manager.addWorkspace()
        manager.moveWorkspaceToSpace(workspaceId: workspace.id, spaceId: space.id)
        manager.toggleSpaceCollapsed(spaceId: space.id)
        XCTAssertTrue(manager.spaces[0].isCollapsed)

        manager.expandSpaceIfNeeded(containingWorkspaceId: workspace.id)
        XCTAssertFalse(manager.spaces[0].isCollapsed)
    }

    func testExpandSpaceIfNeededNoOpForUngroupedWorkspace() {
        let manager = TabManager()
        let workspace = manager.addWorkspace()
        manager.expandSpaceIfNeeded(containingWorkspaceId: workspace.id)
        // No crash, no-op
    }

    func testExpandSpaceIfNeededNoOpForAlreadyExpandedSpace() {
        let manager = TabManager()
        let space = manager.addSpace(name: "Project")
        let workspace = manager.addWorkspace()
        manager.moveWorkspaceToSpace(workspaceId: workspace.id, spaceId: space.id)
        XCTAssertFalse(manager.spaces[0].isCollapsed)

        manager.expandSpaceIfNeeded(containingWorkspaceId: workspace.id)
        XCTAssertFalse(manager.spaces[0].isCollapsed)
    }
}
```

- [ ] **Step 2: Run tests to verify they pass**

Expected: All 6 tests PASS (the implementation was added in Task 1).

- [ ] **Step 3: Commit**

```bash
git add cmuxTests/SpacesUnitTests.swift
git commit -m "test(spaces): add workspace-space assignment and expand tests"
```

---

### Task 4: Sidebar Grouped Rendering

**Files:**
- Modify: `Sources/ContentView.swift` (VerticalTabsSidebar, add SpaceHeaderView, modify ForEach)

This is the core UI task. We replace the flat `ForEach` with a grouped rendering that shows ungrouped workspaces at root, then each Space with its workspaces.

- [ ] **Step 1: Add SidebarRenderItem enum**

In `Sources/ContentView.swift`, before the `VerticalTabsSidebar` struct (line 8495), add:

```swift
private enum SidebarRenderItem: Identifiable {
    case workspace(index: Int, workspace: Workspace)
    case spaceHeader(space: Space, unreadCount: Int)

    var id: String {
        switch self {
        case .workspace(_, let workspace):
            return "ws-\(workspace.id.uuidString)"
        case .spaceHeader(let space, _):
            return "sp-\(space.id.uuidString)"
        }
    }
}
```

- [ ] **Step 2: Add computed sidebarRenderItems to VerticalTabsSidebar**

Inside the `VerticalTabsSidebar` struct, add a computed property before `body`:

```swift
private func sidebarRenderItems(notificationStore: TerminalNotificationStore) -> [SidebarRenderItem] {
    var items: [SidebarRenderItem] = []
    let indexedTabs = Array(tabManager.tabs.enumerated())

    // Ungrouped workspaces first
    for (index, workspace) in indexedTabs where workspace.spaceId == nil {
        items.append(.workspace(index: index, workspace: workspace))
    }

    // Then each space
    for space in tabManager.spaces {
        let spaceWorkspaces = indexedTabs.filter { $0.element.spaceId == space.id }
        let unreadCount = spaceWorkspaces.reduce(0) { sum, pair in
            sum + notificationStore.unreadCount(forTabId: pair.element.id)
        }
        items.append(.spaceHeader(space: space, unreadCount: unreadCount))
        if !space.isCollapsed {
            for (index, workspace) in spaceWorkspaces {
                items.append(.workspace(index: index, workspace: workspace))
            }
        }
    }

    return items
}
```

- [ ] **Step 3: Add SpaceHeaderView**

In `Sources/ContentView.swift`, before `VerticalTabsSidebar`, add:

```swift
private struct SpaceHeaderView: View {
    let space: Space
    let unreadCount: Int
    let onToggleCollapse: () -> Void
    let onRename: (String) -> Void
    let onSetColor: (String?) -> Void
    let onRemove: () -> Void
    @State private var isEditing = false
    @State private var editName: String = ""

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggleCollapse) {
                Image(systemName: space.isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)

            if let color = space.color {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: color) ?? .gray)
                    .frame(width: 10, height: 10)
            }

            if isEditing {
                TextField("", text: $editName, onCommit: {
                    let trimmed = editName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onRename(trimmed)
                    }
                    isEditing = false
                })
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
            } else {
                Text(space.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if space.isCollapsed && unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.blue))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onToggleCollapse() }
        .contextMenu {
            Button(String(localized: "space.contextMenu.rename", defaultValue: "Rename Space")) {
                editName = space.name
                isEditing = true
            }
            Menu(String(localized: "space.contextMenu.setColor", defaultValue: "Set Color")) {
                ForEach(WorkspaceTabColorSettings.palette(), id: \.self) { hex in
                    Button {
                        onSetColor(hex)
                    } label: {
                        Label(hex, systemImage: "circle.fill")
                            .foregroundColor(Color(hex: hex) ?? .gray)
                    }
                }
                Divider()
                Button(String(localized: "space.contextMenu.clearColor", defaultValue: "Clear Color")) {
                    onSetColor(nil)
                }
            }
            Divider()
            Button(String(localized: "space.contextMenu.remove", defaultValue: "Remove Space"), role: .destructive) {
                onRemove()
            }
        }
    }
}
```

- [ ] **Step 4: Replace the flat ForEach with grouped rendering**

In `VerticalTabsSidebar.body` (line 8562-8606), replace the `ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id)` block with:

```swift
let renderItems = sidebarRenderItems(notificationStore: notificationStore)
ForEach(renderItems) { item in
    switch item {
    case .spaceHeader(let space, let unreadCount):
        SpaceHeaderView(
            space: space,
            unreadCount: unreadCount,
            onToggleCollapse: { tabManager.toggleSpaceCollapsed(spaceId: space.id) },
            onRename: { tabManager.renameSpace(spaceId: space.id, name: $0) },
            onSetColor: { tabManager.setSpaceColor(spaceId: space.id, color: $0) },
            onRemove: { tabManager.removeSpace(spaceId: space.id) }
        )

    case .workspace(let index, let tab):
        let selectedContextIds: Set<UUID> = selectedTabIds.contains(tab.id) ? selectedTabIds : [tab.id]
        let contextTargetIds = tabManager.tabs.compactMap { workspace in
            selectedContextIds.contains(workspace.id) ? workspace.id : nil
        }
        let remoteContextMenuTargets = tabManager.tabs.filter { workspace in
            contextTargetIds.contains(workspace.id) && workspace.isRemoteWorkspace
        }
        let isInSpace = tab.spaceId != nil
        HStack(spacing: 0) {
            if isInSpace {
                if let spaceColor = tabManager.spaces.first(where: { $0.id == tab.spaceId })?.color {
                    Rectangle()
                        .fill(Color(hex: spaceColor) ?? .gray)
                        .frame(width: 2)
                        .padding(.vertical, -tabRowSpacing / 2)
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2)
                        .padding(.vertical, -tabRowSpacing / 2)
                }
                Spacer().frame(width: 10)
            }
            TabItemView(
                tabManager: tabManager,
                notificationStore: notificationStore,
                tab: tab,
                index: index,
                isActive: tabManager.selectedTabId == tab.id,
                workspaceShortcutDigit: WorkspaceShortcutMapper.digitForWorkspace(
                    at: index,
                    workspaceCount: workspaceCount
                ),
                workspaceShortcutModifierSymbol: workspaceNumberShortcut.modifierDisplayString,
                canCloseWorkspace: canCloseWorkspace,
                accessibilityWorkspaceCount: workspaceCount,
                unreadCount: notificationStore.unreadCount(forTabId: tab.id),
                latestNotificationText: {
                    guard showsSidebarNotificationMessage,
                          let notification = notificationStore.latestNotification(forTabId: tab.id) else {
                        return nil
                    }
                    let text = notification.body.isEmpty ? notification.title : notification.body
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }(),
                rowSpacing: tabRowSpacing,
                setSelectionToTabs: { selection = .tabs },
                selectedTabIds: $selectedTabIds,
                lastSidebarSelectionIndex: $lastSidebarSelectionIndex,
                showsModifierShortcutHints: modifierKeyMonitor.isModifierPressed,
                dragAutoScrollController: dragAutoScrollController,
                draggedTabId: $draggedTabId,
                dropIndicator: $dropIndicator,
                remoteContextMenuWorkspaceIds: remoteContextMenuTargets.map(\.id),
                allRemoteContextMenuTargetsConnecting: !remoteContextMenuTargets.isEmpty && remoteContextMenuTargets.allSatisfy { $0.remoteConnectionState == .connecting },
                allRemoteContextMenuTargetsDisconnected: !remoteContextMenuTargets.isEmpty && remoteContextMenuTargets.allSatisfy { $0.remoteConnectionState == .disconnected }
            )
            .equatable()
        }
    }
}
```

- [ ] **Step 5: Build to verify compilation**

Run: `xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-spaces build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED (warnings are ok).

- [ ] **Step 6: Build and launch the isolated app to visual test**

Run: `./scripts/reload.sh --tag spaces --launch`

Verify: App launches, sidebar shows workspaces as before (no Spaces created yet, so behavior is identical). No crashes.

- [ ] **Step 7: Commit**

```bash
git add Sources/ContentView.swift
git commit -m "feat(spaces): add sidebar grouped rendering with SpaceHeaderView

Replace flat ForEach with grouped rendering. Ungrouped workspaces
render at root, then each Space with its header and indented
workspaces. Collapsed Spaces show aggregated notification badge.
Vertical tree line connects workspaces to their Space."
```

---

### Task 5: Drag & Drop — Workspace into/out of Spaces

**Files:**
- Modify: `Sources/ContentView.swift` (SpaceHeaderView drop target, modify SidebarTabDropDelegate)

- [ ] **Step 1: Add drop target to SpaceHeaderView**

In `SpaceHeaderView`, after the `.contextMenu` modifier, add:

```swift
.onDrop(of: SidebarTabDragPayload.dropContentTypes, isTargeted: nil) { providers in
    guard let draggedId = draggedTabId else { return false }
    tabManager.moveWorkspaceToSpace(workspaceId: draggedId, spaceId: space.id)
    if space.isCollapsed {
        tabManager.toggleSpaceCollapsed(spaceId: space.id)
    }
    return true
}
```

Note: `SpaceHeaderView` needs access to `draggedTabId`. Add a binding:

```swift
@Binding var draggedTabId: UUID?
```

Update all call sites of `SpaceHeaderView` to pass the binding.

- [ ] **Step 2: Make SidebarEmptyArea drop clear spaceId**

In the `SidebarEmptyArea`'s `SidebarTabDropDelegate` `performDrop` (or in the existing drop logic), after reordering, also clear the workspace's spaceId:

In the `SidebarTabDropDelegate.performDrop` method (line 13214-13271), after the `tabManager.reorderWorkspace(tabId:toIndex:)` call, add:

```swift
// If dropped on empty area (targetTabId == nil), clear spaceId
if targetTabId == nil {
    tabManager.moveWorkspaceToSpace(workspaceId: sourceTabId, spaceId: nil)
}
```

- [ ] **Step 3: Add "New Space from Workspace" to workspace context menu**

In the `workspaceContextMenu` computed property of `TabItemView` (line 11660-11861), add after the "Move to Window" menu:

```swift
Divider()
Button(String(localized: "workspace.contextMenu.newSpaceFromWorkspace", defaultValue: "New Space from Workspace...")) {
    let space = tabManager.addSpace(name: tab.customTitle ?? tab.title)
    tabManager.moveWorkspaceToSpace(workspaceId: tab.id, spaceId: space.id)
}
```

- [ ] **Step 4: Build and visual test**

Run: `./scripts/reload.sh --tag spaces --launch`

Test manually:
1. Right-click workspace → "New Space from Workspace..." → creates Space with workspace inside
2. Drag another workspace onto the Space header → moves it in
3. Drag workspace to empty area → removes from Space

- [ ] **Step 5: Commit**

```bash
git add Sources/ContentView.swift
git commit -m "feat(spaces): add drag & drop for workspace-to-space assignment

Workspace can be dragged onto SpaceHeaderView to assign it.
Dropping on empty area clears spaceId. Right-click workspace offers
'New Space from Workspace...' to create a Space and assign in one step."
```

---

### Task 6: Space Drag & Drop Reordering

**Files:**
- Modify: `Sources/ContentView.swift` (add SidebarSpaceDragPayload, make SpaceHeaderView draggable)
- Modify: `Resources/Info.plist` (register new UTType)

- [ ] **Step 1: Register the UTType in Info.plist**

In `Resources/Info.plist`, inside the `UTExportedTypeDeclarations` array, add a new entry:

```xml
<dict>
    <key>UTTypeConformsTo</key>
    <array>
        <string>public.data</string>
    </array>
    <key>UTTypeDescription</key>
    <string>cmux Sidebar Space Reorder</string>
    <key>UTTypeIdentifier</key>
    <string>com.cmux.sidebar-space-reorder</string>
</dict>
```

- [ ] **Step 2: Add SidebarSpaceDragPayload**

In `Sources/ContentView.swift`, near `SidebarTabDragPayload` (line 13042), add:

```swift
private enum SidebarSpaceDragPayload {
    static let typeIdentifier = "com.cmux.sidebar-space-reorder"
    static let dropContentType = UTType(exportedAs: typeIdentifier)
    static let dropContentTypes: [UTType] = [dropContentType]
    private static let prefix = "cmux.sidebar-space."

    static func provider(for spaceId: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        let payload = "\(prefix)\(spaceId.uuidString)"
        provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .ownProcess) { completion in
            completion(payload.data(using: .utf8), nil)
            return nil
        }
        return provider
    }
}
```

- [ ] **Step 3: Make SpaceHeaderView draggable and a drop target for space reordering**

Add to `SpaceHeaderView`:

```swift
.onDrag {
    SidebarSpaceDragPayload.provider(for: space.id)
}
.onDrop(of: SidebarSpaceDragPayload.dropContentTypes, isTargeted: nil) { providers in
    guard let provider = providers.first else { return false }
    provider.loadDataRepresentation(forTypeIdentifier: SidebarSpaceDragPayload.typeIdentifier) { data, _ in
        guard let data, let str = String(data: data, encoding: .utf8),
              str.hasPrefix("cmux.sidebar-space."),
              let sourceId = UUID(uuidString: String(str.dropFirst("cmux.sidebar-space.".count))) else { return }
        let targetId = space.id
        guard sourceId != targetId else { return }
        DispatchQueue.main.async {
            guard let targetIndex = tabManager.spaces.firstIndex(where: { $0.id == targetId }) else { return }
            tabManager.reorderSpace(spaceId: sourceId, toIndex: targetIndex)
        }
    }
    return true
}
```

- [ ] **Step 4: Build and visual test**

Run: `./scripts/reload.sh --tag spaces --launch`

Test: Create two Spaces, drag one header above/below the other. Order should update.

- [ ] **Step 5: Commit**

```bash
git add Sources/ContentView.swift Resources/Info.plist
git commit -m "feat(spaces): add Space header drag & drop reordering

Register com.cmux.sidebar-space-reorder UTType. Space headers are
draggable and accept drops from other Space headers to reorder."
```

---

### Task 7: Command Palette "New Space" Action

**Files:**
- Modify: `Sources/ContentView.swift` (or wherever command palette commands are registered — likely `Sources/AppDelegate.swift`)

- [ ] **Step 1: Find command palette registration**

The command palette uses `CommandPaletteCommandContribution` registered in `ContentView.swift` (line 5319). Add a "New Space" command near the existing "New Workspace" command.

Search for `palette.newWorkspace` and add nearby:

```swift
CommandPaletteCommandContribution(
    commandId: "palette.newSpace",
    title: constant(String(localized: "command.newSpace.title", defaultValue: "New Space")),
    subtitle: constant(String(localized: "command.newSpace.subtitle", defaultValue: "Space")),
    keywords: ["create", "new", "space", "group", "folder"]
) {
    // Trigger a rename-inline flow or simple alert for the Space name
    let alert = NSAlert()
    alert.messageText = String(localized: "space.newAlert.title", defaultValue: "New Space")
    alert.informativeText = String(localized: "space.newAlert.message", defaultValue: "Enter a name for the new space:")
    alert.addButton(withTitle: String(localized: "space.newAlert.create", defaultValue: "Create"))
    alert.addButton(withTitle: String(localized: "space.newAlert.cancel", defaultValue: "Cancel"))
    let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    textField.placeholderString = String(localized: "space.newAlert.placeholder", defaultValue: "Space name")
    alert.accessoryView = textField
    alert.window.initialFirstResponder = textField
    if alert.runModal() == .alertFirstButtonReturn {
        let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            tabManager.addSpace(name: name)
        }
    }
}
```

Note: The exact registration pattern depends on how the command palette is wired. Adapt the closure style to match the existing `palette.newWorkspace` pattern.

- [ ] **Step 2: Build and visual test**

Run: `./scripts/reload.sh --tag spaces --launch`

Test: Open Command Palette (Cmd+K or Cmd+Shift+P), type "New Space", select it, enter a name.

- [ ] **Step 3: Commit**

```bash
git add Sources/ContentView.swift
git commit -m "feat(spaces): add 'New Space' command palette action

Users can create Spaces via Command Palette with a name prompt dialog."
```

---

### Task 8: Wire expandSpaceIfNeeded to Jump-to-Unread

**Files:**
- Modify: `Sources/TabManager.swift` or `Sources/AppDelegate.swift` (wherever Cmd+Shift+U handler lives)

- [ ] **Step 1: Find the jump-to-unread handler**

Search for `Cmd+Shift+U` or `jumpToUnread` or `nextUnread` in AppDelegate.swift or TabManager.swift. The handler selects the workspace with the latest unread notification.

- [ ] **Step 2: Add expandSpaceIfNeeded call**

Before or after the workspace selection in the jump-to-unread handler, add:

```swift
tabManager.expandSpaceIfNeeded(containingWorkspaceId: targetWorkspaceId)
```

This ensures that if the target workspace is inside a collapsed Space, the Space auto-expands.

- [ ] **Step 3: Build and test**

Run: `./scripts/reload.sh --tag spaces --launch`

Test: Create a Space, move a workspace in, collapse the Space, trigger a notification on that workspace, press Cmd+Shift+U → Space should expand and workspace should be selected.

- [ ] **Step 4: Commit**

```bash
git add Sources/TabManager.swift Sources/AppDelegate.swift
git commit -m "feat(spaces): auto-expand collapsed Space on jump-to-unread

When Cmd+Shift+U targets a workspace inside a collapsed Space,
the Space is automatically expanded before selecting the workspace."
```

---

### Task 9: Final Build and Visual Verification

**Files:** None (verification only)

- [ ] **Step 1: Full build**

Run: `./scripts/reload.sh --tag spaces --launch`

- [ ] **Step 2: Run all Space tests**

Run: `xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-spaces test-without-building -only-testing:cmuxTests/SpacesCRUDTests -only-testing:cmuxTests/SpacesSessionPersistenceTests -only-testing:cmuxTests/SpacesWorkspaceMoveTests 2>&1 | tail -30`

Expected: All tests PASS.

- [ ] **Step 3: Run existing tests to check for regressions**

Run: `xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-spaces test-without-building -only-testing:cmuxTests/TabManagerSessionSnapshotTests -only-testing:cmuxTests/WorkspaceReorderTests 2>&1 | tail -30`

Expected: All existing tests still PASS.

- [ ] **Step 4: Manual visual test checklist**

In the running `cmux DEV spaces.app`:
1. Create a Space via Command Palette → "New Space"
2. Right-click workspace → "New Space from Workspace..."
3. Drag workspace onto Space header → assigns
4. Drag workspace to empty area → unassigns
5. Collapse Space → badge shows notification count
6. Expand Space → workspaces visible again
7. Set color on Space → vertical line changes color
8. Rename Space via right-click
9. Remove Space → workspaces go back to root
10. Drag Space headers to reorder
11. Quit and relaunch → Spaces and assignments restored
12. Verify production cmux is unaffected

- [ ] **Step 5: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix(spaces): address visual test findings"
```
