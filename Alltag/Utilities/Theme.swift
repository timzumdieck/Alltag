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

    /// Gedecktes Terrakotta für Feiertage
    static let holiday = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.86, green: 0.55, blue: 0.48, alpha: 1)
        }
        return UIColor(red: 0.74, green: 0.38, blue: 0.32, alpha: 1)
    })

    /// Warmes Sandgelb für Urlaub
    static let vacation = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.86, green: 0.72, blue: 0.45, alpha: 1)
        }
        return UIColor(red: 0.72, green: 0.56, blue: 0.25, alpha: 1)
    })

    static let card = Color(uiColor: .secondarySystemBackground)
    static let field = Color(uiColor: .tertiarySystemFill)

    /// Einfarbige Abstufung (Salbei) für Satz 1 … 5+ in gestapelten Balken.
    /// Hell: Satz 1 am dunkelsten. Dunkel: Satz 1 am hellsten. Beide Reihen sind mit dem
    /// Palettenprüfer validiert (monotone Helligkeit, sichtbare Stufen, Kontrast zur Kartenfläche).
    static let setRamp: [Color] = {
        let light = [0x2C4632, 0x3F6146, 0x557C5C, 0x6F9875, 0x8FB093]
        let dark = [0xBCD6C0, 0x99BC9E, 0x79A07F, 0x5D8663, 0x4A7050]
        return zip(light, dark).map { pair in
            Color(uiColor: UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? pair.1 : pair.0)
            })
        }
    }()

    /// Zurückhaltendes Grau für Kontext-Markierungen (z. B. alle Sätze hinter der Hauptlinie).
    static let context = Color(uiColor: .systemGray3)
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

extension UIColor {
    convenience init(hex: Int) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
