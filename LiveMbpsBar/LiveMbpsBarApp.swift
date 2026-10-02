import SwiftUI
import UIKit

private enum SharedSettings {
    static let appGroupIdentifier = "group.com.Hitoshi.LiveMbpsBar"
    static let colorKey = "bar-color-hex"
    static let maximumMbpsKey = "bar-maximum-mbps"
    static let showSpeedKey = "show-speed"

    static let defaultColorHex = "58DE2F"
    static let defaultMaximumMbps = 20.0
    static let defaultShowSpeed = true
}

private struct BarColorChoice: Identifiable, Hashable {
    let name: String
    let hex: String

    var id: String { hex }
    var color: Color { Color(hex: hex) }

    static let choices: [BarColorChoice] = [
        .init(name: "Black", hex: "000000"),
        .init(name: "Blue", hex: "1545F5"),
        .init(name: "Brown", hex: "B87C3E"),
        .init(name: "Cyan", hex: "08D7E6"),
        .init(name: "Green", hex: "58DE2F"),
        .init(name: "Magenta", hex: "EC35D5"),
        .init(name: "Gray", hex: "A5A5A5"),
        .init(name: "Orange", hex: "FF9412"),
        .init(name: "Purple", hex: "9B2494"),
        .init(name: "Red", hex: "FF2B18"),
        .init(name: "Yellow", hex: "FFF10A"),
        .init(name: "White", hex: "FFFFFF")
    ]
}

@MainActor
private final class AppSettings: ObservableObject {
    @Published private(set) var colorHex: String
    @Published private(set) var maximumMbps: Double
    @Published private(set) var showSpeed: Bool

    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: SharedSettings.appGroupIdentifier) ?? .standard

        let storedColor = defaults.string(forKey: SharedSettings.colorKey)?.uppercased()
        if let storedColor, BarColorChoice.choices.contains(where: { $0.hex == storedColor }) {
            colorHex = storedColor
        } else {
            colorHex = SharedSettings.defaultColorHex
        }

        let storedMaximum = defaults.object(forKey: SharedSettings.maximumMbpsKey) as? NSNumber
        let candidate = storedMaximum?.doubleValue ?? SharedSettings.defaultMaximumMbps
        maximumMbps = candidate.isFinite && (0.1 ... 1_000).contains(candidate)
            ? candidate
            : SharedSettings.defaultMaximumMbps

        if defaults.object(forKey: SharedSettings.showSpeedKey) == nil {
            showSpeed = SharedSettings.defaultShowSpeed
        } else {
            showSpeed = defaults.bool(forKey: SharedSettings.showSpeedKey)
        }

        persistCurrentValues()
    }

    func selectColor(_ choice: BarColorChoice) {
        colorHex = choice.hex
        defaults.set(choice.hex, forKey: SharedSettings.colorKey)
    }

    func setShowSpeed(_ value: Bool) {
        showSpeed = value
        defaults.set(value, forKey: SharedSettings.showSpeedKey)
    }

    func saveMaximum(from input: String) -> String? {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)

        guard
            !normalized.isEmpty,
            parts.count <= 2,
            parts.first?.isEmpty == false,
            parts.allSatisfy({ part in part.allSatisfy(\.isNumber) }),
            parts.count == 1 || parts[1].count <= 1,
            let value = Double(normalized),
            value.isFinite,
            (0.1 ... 1_000).contains(value)
        else {
            return "Enter a value from 0.1 to 1,000.0 using no more than one decimal place."
        }

        maximumMbps = value
        defaults.set(value, forKey: SharedSettings.maximumMbpsKey)
        return nil
    }

    func formattedMaximum() -> String {
        String(format: "%.1f", maximumMbps)
    }

    private func persistCurrentValues() {
        defaults.set(colorHex, forKey: SharedSettings.colorKey)
        defaults.set(maximumMbps, forKey: SharedSettings.maximumMbpsKey)
        defaults.set(showSpeed, forKey: SharedSettings.showSpeedKey)
    }
}

@main
struct LiveMbpsBarApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = AppSettings()
    @State private var rootIdentity = UUID()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(settings)
                .id(rootIdentity)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { previousPhase, newPhase in
            if newPhase == .active && previousPhase != .active {
                rootIdentity = UUID()
            }
        }
    }
}

private enum AppRoute: Hashable {
    case detail
    case information
}

private struct AppRootView: View {
    var body: some View {
        NavigationStack {
            TopView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .detail:
                        ActivationDetailView()
                            .modifier(SwipeBackModifier())
                    case .information:
                        InformationView()
                            .modifier(SwipeBackModifier())
                    }
                }
        }
        .tint(Color(hex: SharedSettings.defaultColorHex))
    }
}

private struct SwipeBackModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 30, coordinateSpace: .local)
                    .onEnded { value in
                        let horizontal = value.translation.width
                        let vertical = abs(value.translation.height)
                        guard horizontal >= 80, horizontal > vertical * 1.5 else { return }
                        dismiss()
                    }
            )
            .accessibilityAction(.escape) {
                dismiss()
            }
    }
}

private struct TopView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var maximumDraft = ""
    @State private var maximumFieldIsFocused = false
    @State private var validationMessage: String?

    private let previewSpeedMbps = 10.0
    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 6)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    SafariPreview(
                        speedMbps: previewSpeedMbps,
                        maximumMbps: settings.maximumMbps,
                        color: Color(hex: settings.colorHex),
                        showSpeed: settings.showSpeed
                    )

                    colorCard
                    maximumCard
                        .id("maximum-card")
                    speedVisibilityCard
                    activationCard
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.black.ignoresSafeArea())
            .navigationBarHidden(true)
            .onAppear {
                maximumDraft = settings.formattedMaximum()
            }
            .onChange(of: maximumFieldIsFocused) { wasFocused, isFocused in
                if isFocused {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo("maximum-card", anchor: .bottom)
                        }
                    }
                } else if wasFocused {
                    commitMaximum()
                }
            }
            .alert("Invalid Max Mbps", isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationMessage ?? "")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Live Mbps Bar")
                    .font(.system(size: 34, weight: .medium))
                Text("Show live net speed as a bar at the top of Safari.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)
            }

            Spacer(minLength: 8)

            NavigationLink(value: AppRoute.information) {
                Image(systemName: "info.circle")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(Color(white: 0.76))
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Information")
            }
            .buttonStyle(.plain)
        }
    }

    private var colorCard: some View {
        settingCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Color")
                    .font(.system(size: 24, weight: .medium))

                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(BarColorChoice.choices) { choice in
                        Button {
                            settings.selectColor(choice)
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        choice.hex == settings.colorHex ? Color.white.opacity(0.72) : .clear,
                                        lineWidth: 2
                                    )
                                    .frame(width: 48, height: 48)

                                Circle()
                                    .fill(choice.color)
                                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.5))
                                    .frame(width: 38, height: 38)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.name)
                        .accessibilityValue(choice.hex == settings.colorHex ? "Selected" : "")
                    }
                }
            }
        }
    }

    private var maximumCard: some View {
        settingCard {
            HStack(spacing: 12) {
                Text("Max Mbps")
                    .font(.system(size: 24, weight: .medium))

                Spacer(minLength: 10)

                DecimalInputField(
                    text: $maximumDraft,
                    onFocusChange: { isFocused in
                        maximumFieldIsFocused = isFocused
                    }
                )
                    .padding(.horizontal, 9)
                    .frame(width: 105, height: 42)
                    .background(Color.white.opacity(0.2))
                    .accessibilityLabel("Maximum speed in megabits per second")

                Text("Mbps")
                    .font(.system(size: 21))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var speedVisibilityCard: some View {
        settingCard {
            HStack(spacing: 13) {
                Text("Show speed")
                    .font(.system(size: 24, weight: .medium))

                Spacer(minLength: 6)

                radioButton(title: "ON", selected: settings.showSpeed) {
                    settings.setShowSpeed(true)
                }
                radioButton(title: "OFF", selected: !settings.showSpeed) {
                    settings.setShowSpeed(false)
                }
            }
        }
    }

    private var activationCard: some View {
        settingCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("How to activate")
                    .font(.system(size: 24, weight: .medium))
                Text("Enable Live Mbps Bar in Safari Extensions.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    NavigationLink(value: AppRoute.detail) {
                        HStack(spacing: 5) {
                            Text("Details")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 18, weight: .medium))
                    }
                }
            }
        }
    }

    private func settingCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.13))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func radioButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 21, height: 21)
                    if selected {
                        Circle()
                            .fill(Color(white: 0.25))
                            .frame(width: 9, height: 9)
                    }
                }
                Text(title)
                    .foregroundStyle(selected ? Color.white : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "Selected" : "")
    }

    private func commitMaximum() {
        if let message = settings.saveMaximum(from: maximumDraft) {
            validationMessage = message
            maximumDraft = settings.formattedMaximum()
        } else {
            maximumDraft = settings.formattedMaximum()
        }
    }
}

private struct DecimalInputField: UIViewRepresentable {
    @Binding var text: String
    let onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.keyboardType = .decimalPad
        textField.textAlignment = .right
        textField.textColor = .white
        textField.tintColor = UIColor(Color(hex: SharedSettings.defaultColorHex))
        textField.font = .monospacedDigitSystemFont(ofSize: 24, weight: .regular)
        textField.backgroundColor = .clear
        textField.adjustsFontSizeToFitWidth = true
        textField.minimumFontSize = 17
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )

        let accessory = UIToolbar()
        accessory.sizeToFit()
        accessory.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(
                title: "Done",
                style: .done,
                target: context.coordinator,
                action: #selector(Coordinator.finishEditing)
            )
        ]
        textField.inputAccessoryView = accessory
        context.coordinator.textField = textField
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self
        if textField.text != text {
            textField.text = text
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: DecimalInputField
        weak var textField: UITextField?

        init(parent: DecimalInputField) {
            self.parent = parent
        }

        @objc func textChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        @objc func finishEditing() {
            textField?.resignFirstResponder()
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onFocusChange(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.text = textField.text ?? ""
            parent.onFocusChange(false)
        }
    }
}

private struct SafariPreview: View {
    let speedMbps: Double
    let maximumMbps: Double
    let color: Color
    let showSpeed: Bool

    private var widthRatio: Double {
        min(1, max(0, speedMbps / maximumMbps))
    }

    var body: some View {
        GeometryReader { geometry in
            let viewportLeft = geometry.size.width * (73 / 630)
            let viewportWidth = geometry.size.width * (482 / 630)
            let barTop = geometry.size.height * (198 / 260)

            ZStack(alignment: .topLeading) {
                Image("SafariPreviewChrome")
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)

                Rectangle()
                    .fill(Color(white: 0.99))
                    .frame(
                        width: geometry.size.width * (150 / 630),
                        height: geometry.size.height * (30 / 260)
                    )
                    .position(
                        x: geometry.size.width * 0.5,
                        y: geometry.size.height * (156 / 260)
                    )

                Rectangle()
                    .fill(color)
                    .frame(width: viewportWidth * widthRatio, height: 3)
                    .offset(x: viewportLeft, y: barTop)

                if showSpeed {
                    Text(String(format: "%.1f Mbps", speedMbps))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.68))
                        .offset(x: viewportLeft, y: barTop + 3)
                }
            }
        }
        .aspectRatio(630 / 260, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Safari preview at 10.0 megabits per second")
    }
}

private struct ActivationDetailView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [ActivationStep] = [
        .init(title: "Open Safari from Settings list", imageName: "ActivationSafari"),
        .init(
            title: "Select Extensions at General",
            imageName: "ActivationExtensions",
            arrows: [.init(x: 0.334, y: 0.623)]
        ),
        .init(
            title: "Turn this apps button on",
            imageName: "ActivationEnable",
            arrows: [.init(x: 0.926, y: 0.13)]
        ),
        .init(
            title: "Turn two button on and allow all Websites",
            imageName: "ActivationPermissions",
            arrows: [
                .init(x: 0.926, y: 0.01),
                .init(x: 0.926, y: 0.15),
                .init(x: 0.917, y: 0.825)
            ]
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .center) {
                    Text("How to activate")
                        .font(.system(size: 30, weight: .medium))

                    Spacer()

                    Button("back") {
                        dismiss()
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(Color(white: 0.72))
                    .padding(.horizontal, 17)
                    .padding(.vertical, 7)
                    .background(Color(white: 0.28))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.45), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                }

                ForEach(steps) { step in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(step.title)
                            .font(.system(size: 17))
                            .foregroundStyle(Color(white: 0.68))

                        ActivationScreenshot(step: step)
                    }
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(20)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}

private struct ActivationStep: Identifiable {
    let title: String
    let imageName: String
    var arrows: [UnitPoint] = []

    var id: String { imageName }
}

private struct ActivationScreenshot: View {
    let step: ActivationStep

    var body: some View {
        Group {
            if step.imageName == "ActivationEnable" {
                ExtensionEnableScreenshot()
            } else {
                Image(step.imageName)
                    .resizable()
                    .scaledToFit()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            GeometryReader { geometry in
                ForEach(Array(step.arrows.enumerated()), id: \.offset) { _, point in
                    Image(systemName: "arrow.down.left")
                        .font(.system(
                            size: geometry.size.width * 0.10,
                            weight: .black
                        ))
                        .foregroundStyle(Color.red)
                        .position(
                            x: geometry.size.width * point.x,
                            y: geometry.size.height * point.y
                        )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.title)
    }
}

private struct ExtensionEnableScreenshot: View {
    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 462

            VStack(alignment: .leading, spacing: 5 * scale) {
                Text("Allow these extensions")
                    .font(.system(size: 18 * scale, weight: .semibold))
                    .foregroundStyle(Color(white: 0.54))
                    .padding(.leading, 30 * scale)

                HStack(spacing: 12 * scale) {
                    Image("ActivationAppIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34 * scale, height: 34 * scale)
                        .clipShape(RoundedRectangle(cornerRadius: 7 * scale))

                    Text("Live Mbps Bar")
                        .font(.system(size: 22 * scale))
                        .foregroundStyle(Color.black)

                    Spacer(minLength: 4 * scale)

                    Text("On")
                        .font(.system(size: 21 * scale))
                        .foregroundStyle(Color(white: 0.56))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 18 * scale, weight: .semibold))
                        .foregroundStyle(Color(white: 0.78))
                }
                .padding(.horizontal, 24 * scale)
                .frame(height: 64 * scale)
                .background(Color.white)
                .clipShape(Capsule())
                .padding(.horizontal, 12 * scale)
            }
            .padding(.vertical, 5 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(red: 0.95, green: 0.95, blue: 0.98))
        }
        .aspectRatio(462 / 116, contentMode: .fit)
    }
}

private struct InformationView: View {
    @State private var expandedItems: Set<String> = []

    private let contents: [String: String] = [
        "What’s Live Mbps Bar": """
        Live Mbps Bar shows your current network receive speed while you browse Safari.
        It displays the speed as a simple bar at the top of the screen, with an optional Mbps value.
        No network history is stored.
        """,
        "Privacy Policy": """
        Network speed history is not stored.
        This app does not use a VPN.
        App settings are stored only on your device.
        No account is required.
        No personal information is collected.
        No analytics are used.
        """,
        "Disclaimer": """
        Live Mbps Bar shows the current receive rate based on network traffic measured on your device.
        It is not an internet speed test and does not measure the maximum speed of your network connection.
        Displayed values may vary depending on network conditions, device activity, and the network environment.
        The displayed values are for informational purposes only.
        """,
        "Version": """
        Live Mbps Bar
        Version 1.0.0
        © 2026 Hitoshi Masui
        """
    ]

    private let items = [
        "What’s Live Mbps Bar",
        "Support",
        "Privacy Policy",
        "Disclaimer",
        "Version"
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(items, id: \.self) { item in
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                if expandedItems.contains(item) {
                                    expandedItems.remove(item)
                                } else {
                                    expandedItems.insert(item)
                                }
                            }
                        } label: {
                            informationRowLabel(
                                item,
                                expanded: expandedItems.contains(item)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(
                            expandedItems.contains(item) ? "Expanded" : "Collapsed"
                        )

                        if expandedItems.contains(item) {
                            if item == "Support" {
                                supportContent
                            } else if let content = contents[item] {
                                Text(content)
                                    .font(.system(size: 18))
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 20)
                            } else {
                                Color.clear
                                    .frame(height: 64)
                                    .accessibilityHidden(true)
                            }
                        }
                    }

                    if item != items.last {
                        Divider()
                    }
                }
            }
            .background(Color(white: 0.07))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Information")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Information")
                    .font(.title3.weight(.semibold))
            }
        }
    }

    private var supportContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("""
            Need help?
            Visit the Live Mbps Bar support page for FAQs and contact information.

            Website
            """)

            Link("https://sonocam.app/", destination: URL(string: "https://sonocam.app/")!)
                .foregroundStyle(.blue)

            Text("""

            Email
            """)

            Link(
                "sonocam.support@gmail.com",
                destination: URL(string: "mailto:sonocam.support@gmail.com")!
            )
            .foregroundStyle(.blue)
        }
        .font(.system(size: 18))
        .foregroundStyle(.secondary)
        .lineSpacing(4)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }

    private func informationRowLabel(_ item: String, expanded: Bool) -> some View {
        HStack {
            Text(item)
                .font(.title3)
                .foregroundStyle(.white)

            Spacer()

            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
