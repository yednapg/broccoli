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
                SpotlightSettingsRow(title: "Tax or Tip Rate", subtitle: "Used for “400 + vat” and “400 + tip”") {
                    Picker("Tax or Tip Rate", selection: calculatorBinding(\.taxPercent)) {
                        Text("Off").tag(0.0)
                        Text("5%").tag(5.0)
                        Text("10%").tag(10.0)
                        Text("12%").tag(12.0)
                        Text("18%").tag(18.0)
                        Text("20%").tag(20.0)
                    }
                    .labelsHidden()
                    .frame(width: 92)
                }
                .disabled(!preferences.calculator.enabled)
                SpotlightSettingsRow(title: "Gallon", subtitle: "Automatic uses imperial gallons in the UK and Ireland") {
                    Picker("Gallon", selection: calculatorBinding(\.gallonChoice)) {
                        Text("Automatic").tag("")
                        Text("US").tag("us")
                        Text("Imperial").tag("imperial")
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                .disabled(!preferences.calculator.enabled)
                SpotlightSettingsRow(title: "Pixels per Inch", subtitle: "Used when converting inches and points to pixels") {
                    Picker("Pixels per Inch", selection: calculatorBinding(\.pixelsPerInch)) {
                        Text("72").tag(72.0)
                        Text("96").tag(96.0)
                        Text("144").tag(144.0)
                    }
                    .labelsHidden()
                    .frame(width: 92)
                }
                .disabled(!preferences.calculator.enabled)
                SpotlightSettingsRow(title: "Base Font Size", subtitle: "Used when converting pixels to em and rem") {
                    Picker("Base Font Size", selection: calculatorBinding(\.baseFontPixels)) {
                        Text("14px").tag(14.0)
                        Text("16px").tag(16.0)
                        Text("18px").tag(18.0)
                    }
                    .labelsHidden()
                    .frame(width: 92)
                }
                .disabled(!preferences.calculator.enabled)
                SpotlightSettingsRow(
                    title: "Natural Phrasing",
                    subtitle: "Apple Intelligence can interpret unfamiliar wording. \(CalculatorIntentInterpreter.availabilityLabel())"
                ) {
                    Toggle("", isOn: calculatorBinding(\.naturalPhrasingEnabled))
                        .labelsHidden()
                        .settingsToggleAccessibility(
                            "Natural Phrasing",
                            isOn: preferences.calculator.naturalPhrasingEnabled
                        )
                }
                .disabled(!preferences.calculator.enabled)
            }
            SpotlightSettingsCard("Currency") {
                SpotlightSettingsRow(title: "Home Currency", subtitle: "Used when an amount has no target currency") {
                    Picker("Home Currency", selection: calculatorBinding(\.homeCurrencyCode)) {
                        Text("Automatic").tag("")
                        Text("USD").tag("USD")
                        Text("EUR").tag("EUR")
                        Text("GBP").tag("GBP")
                        Text("INR").tag("INR")
                        Text("JPY").tag("JPY")
                        Text("CAD").tag("CAD")
                        Text("AUD").tag("AUD")
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                .disabled(!preferences.calculator.enabled)
                SpotlightSettingsRow(title: "Extra Currency", subtitle: "Shown when the amount is already in your home currency") {
                    Picker("Extra Currency", selection: calculatorBinding(\.secondaryCurrencyCode)) {
                        Text("Automatic").tag("")
                        Text("USD").tag("USD")
                        Text("EUR").tag("EUR")
                        Text("GBP").tag("GBP")
                        Text("INR").tag("INR")
                        Text("JPY").tag("JPY")
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                .disabled(!preferences.calculator.enabled)
                SpotlightSettingsRow(title: "Currency Rates", subtitle: "Download a daily rate table. Amounts stay on this Mac.") {
                    Toggle("", isOn: calculatorBinding(\.onlineRatesEnabled))
                        .labelsHidden()
                        .settingsToggleAccessibility(
                            "Download Currency Rates",
                            isOn: preferences.calculator.onlineRatesEnabled
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
                VStack(alignment: .leading, spacing: 8) {
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
                        calculatorCapability("Percentages", symbol: "percent")
                        calculatorCapability("Dates & Time Zones", symbol: "clock")
                        calculatorCapability("Currency", symbol: "coloncurrencysign")
                    }
                    ExamplePill("10 km in mi", detail: "6.21371 mi")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            SettingsFootnote(symbol: "lock", text: "Calculations run on this Mac. Currency rates download daily, and nothing you type is sent.")
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

