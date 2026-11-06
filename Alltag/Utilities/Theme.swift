import SwiftUI
import UIKit

enum Theme {
    /// Salbeigrün #6B8F71, im Dark Mode etwas heller.
    static let accent = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.56, green: 0.71, blue: 0.59, alpha: 1)
        }
        return UIColor(red: 107 / 255, green: 143 / 255, blue: 113 / 255, alpha: 1)
    })

    /// Gedecktes Blaugrau für Termine
    static let appointment = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.56, green: 0.65, blue: 0.78, alpha: 1)
        }
        return UIColor(red: 0.42, green: 0.52, blue: 0.66, alpha: 1)
    })

    static let card = Color(uiColor: .secondarySystemBackground)
    static let field = Color(uiColor: .tertiarySystemFill)

    /// Gedeckte Farben für Diagrammlinien (je Satz).
    static let chartPalette: [Color] = [
        accent,
        Color(red: 0.42, green: 0.52, blue: 0.66),
        Color(red: 0.80, green: 0.63, blue: 0.40),
        Color(red: 0.58, green: 0.58, blue: 0.62),
        Color(red: 0.66, green: 0.48, blue: 0.58),
        Color(red: 0.30, green: 0.44, blue: 0.34),
        Color(red: 0.45, green: 0.66, blue: 0.70),
        Color(red: 0.72, green: 0.45, blue: 0.40)
    ]
}

@MainActor
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

@MainActor
func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

@MainActor
func hapticSuccess() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
}

extension Binding where Value == Date {
    /// Verbindet einen Uhrzeit-Picker mit "Minuten seit Mitternacht".
    static func minutes(_ source: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: { Day.date(Day.today, minutes: source.wrappedValue) },
            set: { source.wrappedValue = Day.minutes(of: $0) }
        )
    }
}
