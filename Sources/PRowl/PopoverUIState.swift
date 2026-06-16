import Combine
import SwiftUI

/// Shared popover UI mode (PR list vs inline settings).
@MainActor
final class PopoverUIState: ObservableObject {
    @Published var showingSettings = false
}
