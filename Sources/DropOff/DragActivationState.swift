struct DragActivationState {
    private var initialPasteboardChangeCount: Int?
    private var beganInsideDropOff = false

    mutating func begin(pasteboardChangeCount: Int, beganInsideDropOff: Bool) {
        initialPasteboardChangeCount = pasteboardChangeCount
        self.beganInsideDropOff = beganInsideDropOff
    }

    mutating func reset() {
        initialPasteboardChangeCount = nil
        beganInsideDropOff = false
    }

    func shouldProcessDrag(
        currentPasteboardChangeCount: Int,
        pasteboardContainsFiles: Bool
    ) -> Bool {
        guard let initialPasteboardChangeCount else { return false }
        return !beganInsideDropOff
            && pasteboardContainsFiles
            && currentPasteboardChangeCount != initialPasteboardChangeCount
    }
}
