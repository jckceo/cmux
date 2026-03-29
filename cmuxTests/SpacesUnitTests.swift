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
