import Foundation

enum AppStatus: Equatable {
    case idle
    case recording
    case transcribing
    case processing  // diarization + cleanup
    case error(String)

    var isIdle: Bool { self == .idle }
    var isBusy: Bool {
        switch self {
        case .recording, .transcribing, .processing: return true
        default: return false
        }
    }
}
