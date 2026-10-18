import SwiftUI

extension View {
  @ViewBuilder func desktopSheet() -> some View {
    #if targetEnvironment(macCatalyst)
    self.frame(minWidth: 680, idealWidth: 760, minHeight: 600, idealHeight: 760)
    #else
    self
    #endif
  }
}
