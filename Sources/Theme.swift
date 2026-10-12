import SwiftUI

extension RGBAColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

extension Double {
    /// 95.5 -> "1:35"
    var timecode: String {
        guard isFinite, self > 0 else { return "0:00" }
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
