import Darwin
import Foundation

final class SingleInstanceLock {
    private let fileDescriptor: Int32

    convenience init?() {
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.vojtechbrandejs.drop-off.instance.lock")
        self.init(url: lockURL)
    }

    init?(url: URL) {
        let descriptor = url.path.withCString {
            Darwin.open(
                $0,
                O_CREAT | O_RDWR | O_CLOEXEC | O_EXLOCK | O_NONBLOCK,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else { return nil }
        fileDescriptor = descriptor
    }

    deinit {
        Darwin.close(fileDescriptor)
    }
}
