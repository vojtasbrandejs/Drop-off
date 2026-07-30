import CoreGraphics
import Foundation

struct ShakeGestureRecognizer {
    struct Configuration {
        var requiredDirectionChanges = 3
        var minimumTotalDistance: CGFloat = 120
        var maximumDuration: TimeInterval = 0.45
        var minimumSegmentDistance: CGFloat = 6
    }

    private(set) var configuration: Configuration
    private var startTime: TimeInterval?
    private var lastPoint: CGPoint?
    private var lastDirection: Int?
    private var directionChanges = 0
    private var totalDistance: CGFloat = 0
    private var didTrigger = false

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    mutating func reset() {
        startTime = nil
        lastPoint = nil
        lastDirection = nil
        directionChanges = 0
        totalDistance = 0
        didTrigger = false
    }

    mutating func process(point: CGPoint, timestamp: TimeInterval) -> Bool {
        guard !didTrigger else { return false }

        guard let previousPoint = lastPoint, let startedAt = startTime else {
            startTime = timestamp
            lastPoint = point
            return false
        }

        if timestamp - startedAt > configuration.maximumDuration {
            reset()
            startTime = timestamp
            lastPoint = point
            return false
        }

        let dx = point.x - previousPoint.x
        let dy = point.y - previousPoint.y
        let distance = hypot(dx, dy)
        lastPoint = point

        guard distance >= configuration.minimumSegmentDistance else { return false }
        totalDistance += distance

        let dominantDelta = abs(dx) >= abs(dy) ? dx : dy
        let direction = dominantDelta >= 0 ? 1 : -1
        if let lastDirection, lastDirection != direction {
            directionChanges += 1
        }
        self.lastDirection = direction

        if directionChanges >= configuration.requiredDirectionChanges,
           totalDistance >= configuration.minimumTotalDistance {
            didTrigger = true
            return true
        }
        return false
    }
}
