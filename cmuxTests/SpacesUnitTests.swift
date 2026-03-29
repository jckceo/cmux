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
        // Create a snapshot WITHOUT spaces (simulating old format)
        let manager = TabManager()
        let snapshot = manager.sessionSnapshot(includeScrollback: false)

        // Manually verify the snapshot can be encoded and decoded
        let encoder = JSONEncoder()
        let data = try! encoder.encode(snapshot)
        // Remove "spaces" key to simulate old format
        var json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "spaces")
        // Also remove spaceId from workspaces
        if var workspaces = json["workspaces"] as? [[String: Any]] {
            for i in workspaces.indices {
                workspaces[i].removeValue(forKey: "spaceId")
            }
            json["workspaces"] = workspaces
        }
        let modifiedData = try! JSONSerialization.data(withJSONObject: json)

        let decoded = try! JSONDecoder().decode(SessionTabManagerSnapshot.self, from: modifiedData)
        XCTAssertEqual(decoded.spaces.count, 0)
        XCTAssertEqual(decoded.workspaces.count, snapshot.workspaces.count)
        XCTAssertNil(decoded.workspaces[0].spaceId)
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

    func testSessionSpaceSnapshotJsonCoding() throws {
        let id = UUID()
        let snapshot = SessionSpaceSnapshot(
            id: id,
            name: "Test",
            color: "#FF0000",
            isCollapsed: true
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSpaceSnapshot.self, from: data)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.name, "Test")
        XCTAssertEqual(decoded.color, "#FF0000")
        XCTAssertTrue(decoded.isCollapsed)
    }
}

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
