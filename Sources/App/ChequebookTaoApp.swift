import SwiftUI
import UniformTypeIdentifiers

// NOTE: The app target compiles Sources/Core and Sources/App together, so Core
// types (RegisterFile, RegisterEngine, DateOrder, ...) are used directly with
// no import. The ChequebookCore module only exists for `swift test` on CI.

@main
struct ChequebookTaoApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { RegisterDocument() }) { configuration in
            RegisterWindowView(document: configuration.document)
        }

        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage(AppSettings.dateOrderKey) private var dateOrderRaw = AppSettings.defaultDateOrder.rawValue

    var body: some View {
        Form {
            Picker("Date entry order:", selection: $dateOrderRaw) {
                Text("Month first (2/5 = Feb 5)").tag("monthFirst")
                Text("Day first (2/5 = 2 May)").tag("dayFirst")
            }
            .pickerStyle(.radioGroup)
            Text("Currency symbol and date display follow your macOS language & region settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(appVersionLabel)
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 380)
    }
}

private var appVersionLabel: String {
    let info = Bundle.main.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    return "Version \(short) (\(build))"
}

enum AppSettings {
    static let dateOrderKey = "dateOrder"

    /// Default to the macOS region's convention: UK/EU regions get day-first.
    static var defaultDateOrder: DateOrder {
        let format = DateFormatter.dateFormat(fromTemplate: "Mdy", options: 0, locale: .current) ?? "M/d/y"
        if let dayIndex = format.firstIndex(of: "d"), let monthIndex = format.firstIndex(of: "M") {
            return dayIndex < monthIndex ? .dayFirst : .monthFirst
        }
        return .monthFirst
    }

    static var dateOrder: DateOrder {
        let raw = UserDefaults.standard.string(forKey: dateOrderKey) ?? defaultDateOrder.rawValue
        return DateOrder(rawValue: raw) ?? .monthFirst
    }
}
