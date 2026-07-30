import CoreGraphics
import Testing
@testable import DropOff

@Test func ordinaryMovementDoesNotTrigger() {
    var recognizer = ShakeGestureRecognizer()
    let points = stride(from: CGFloat(0), through: 180, by: 30).map {
        CGPoint(x: $0, y: $0 * 0.25)
    }
    let results = points.enumerated().map { index, point in
        recognizer.process(point: point, timestamp: Double(index) * 0.04)
    }
    #expect(!results.contains(true))
}

@Test func slowWavingDoesNotTrigger() {
    var recognizer = ShakeGestureRecognizer()
    let points = [0, 50, 0, 50, 0].map { CGPoint(x: $0, y: 0) }
    let results = points.enumerated().map { index, point in
        recognizer.process(point: point, timestamp: Double(index) * 0.2)
    }
    #expect(!results.contains(true))
}

@Test func fastShakeTriggers() {
    var recognizer = ShakeGestureRecognizer()
    let points = [0, 42, 0, 42, 0].map { CGPoint(x: $0, y: 0) }
    let results = points.enumerated().map { index, point in
        recognizer.process(point: point, timestamp: Double(index) * 0.06)
    }
    #expect(results.filter { $0 }.count == 1)
}

@Test func onlyOneTriggerUntilReset() {
    var recognizer = ShakeGestureRecognizer()
    let firstShake = [0, 42, 0, 42, 0].enumerated().map { index, x in
        recognizer.process(point: CGPoint(x: x, y: 0), timestamp: Double(index) * 0.05)
    }
    let repeated = recognizer.process(point: CGPoint(x: 42, y: 0), timestamp: 0.3)
    #expect(firstShake.filter { $0 }.count == 1)
    #expect(!repeated)
}

@Test func resetAllowsNextDragToTrigger() {
    var recognizer = ShakeGestureRecognizer()
    let points = [0, 42, 0, 42, 0]
    for (index, x) in points.enumerated() {
        _ = recognizer.process(point: CGPoint(x: x, y: 0), timestamp: Double(index) * 0.05)
    }
    recognizer.reset()
    let secondResults = points.enumerated().map { index, x in
        recognizer.process(point: CGPoint(x: x, y: 0), timestamp: 1 + Double(index) * 0.05)
    }
    #expect(secondResults.filter { $0 }.count == 1)
}

@Test func touchpadDragWithoutNewFilePasteboardIsIgnored() {
    var state = DragActivationState()
    state.begin(pasteboardChangeCount: 10, beganInsideDropOff: false)
    #expect(!state.shouldProcessDrag(
        currentPasteboardChangeCount: 10,
        pasteboardContainsFiles: true
    ))
}

@Test func actualFileDragIsAcceptedAfterPasteboardChanges() {
    var state = DragActivationState()
    state.begin(pasteboardChangeCount: 10, beganInsideDropOff: false)
    #expect(state.shouldProcessDrag(
        currentPasteboardChangeCount: 11,
        pasteboardContainsFiles: true
    ))
}

@Test func dragBeginningInsideDropOffIsAlwaysIgnored() {
    var state = DragActivationState()
    state.begin(pasteboardChangeCount: 10, beganInsideDropOff: true)
    #expect(!state.shouldProcessDrag(
        currentPasteboardChangeCount: 11,
        pasteboardContainsFiles: true
    ))
}
