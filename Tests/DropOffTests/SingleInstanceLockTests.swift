import Foundation
import Testing
@testable import DropOff

@Test
func secondAppInstanceIsRejectedAndLockRecoversAfterExit() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let lockURL = directory.appendingPathComponent("drop-off-instance.lock")

    var firstInstance: SingleInstanceLock? = SingleInstanceLock(url: lockURL)
    #expect(firstInstance != nil)
    #expect(SingleInstanceLock(url: lockURL) == nil)

    firstInstance = nil
    #expect(SingleInstanceLock(url: lockURL) != nil)
}
