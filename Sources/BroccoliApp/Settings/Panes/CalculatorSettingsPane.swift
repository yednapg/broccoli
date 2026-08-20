import SwiftUI

struct CalculatorSettingsPane: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        calculator
    }

    private var calculator: some View {
        Group {
            SpotlightSettingsCard("Calculator") {
                SpotlightSettingsRow(symbol: "function", title: "Enable Calculator", subtitle: "Detect expressions automatically while searching") {
                    Toggle("", isOn: Binding(
                        get: { preferences.calculator.enabled },
                        set: { var value = preferences.calculator; value.enabled = $0; preferences.calculator = value }
                    ))
                    .labelsHidden()
                    .settingsToggleAccessibility("Enable Calculator", isOn: preferences.calculator.enabled)
                }
                SpotlightSettingsRow(title: "Significant Digits", subtitle: "Maximum precision used to format answers") {
                    Picker("Significant Digits", selection: calculatorBinding(\.significantDigits)) {
                        Text("6").tag(6)
                        Text("9").tag(9)
                        Text("12").tag(12)
                    }
                    .labelsHidden()
                    .frame(width: 92)
                }
                .disabled(!preferences.calculator.enabled)
                SpotlightSettingsRow(title: "Grouping Separators", subtitle: "Format large results using your regional settings") {
                    Toggle("", isOn: calculatorBinding(\.usesGroupingSeparator))
                        .labelsHidden()
                        .settingsToggleAccessibility(
                            "Use Grouping Separators",
                            isOn: preferences.calculator.usesGroupingSeparator
                        )
                }
                .disabled(!preferences.calculator.enabled)
            }
            SpotlightSettingsCard("Copying Results") {
                SpotlightSettingsRow(title: "Return Key", subtitle: "Copies the formatted answer and closes Broccoli") {
                    SettingsStatusAccessory(title: "Copy Answer")
                }
                .disabled(!preferences.calculator.enabled)
            }
            SpotlightSettingsCard("Supported") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210), alignment: .leading)],
                    alignment: .leading,
                    spacing: 2
                ) {
                    calculatorCapability("Arithmetic", symbol: "plus.forwardslash.minus")
                    calculatorCapability("Scientific Functions", symbol: "function")
                    calculatorCapability("Length & Area", symbol: "ruler")
                    calculatorCapability("Volume & Mass", symbol: "cube")
                    calculatorCapability("Temperature & Time", symbol: "thermometer.medium")
                    calculatorCapability("Speed & Angle", symbol: "speedometer")
                    calculatorCapability("Data Size", symbol: "externaldrive")
                }
                HStack {
                    Text("10 km in mi").font(.system(size: 12, design: .monospaced))
                    Spacer()
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Text("6.21371 mi").font(.system(size: 12, design: .monospaced))
                }
                .frame(height: 44)
            }
            SettingsFootnote(symbol: "network.slash", text: "All calculations run offline.")
        }
    }

    private func calculatorCapability(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11))
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    private func calculatorBinding<Value>(_ keyPath: WritableKeyPath<CalculatorPreferences, Value>) -> Binding<Value> {
        Binding(get: { preferences.calculator[keyPath: keyPath] }) { newValue in
            var value = preferences.calculator
            value[keyPath: keyPath] = newValue
            value.sanitize()
            preferences.calculator = value
        }
    }

}

