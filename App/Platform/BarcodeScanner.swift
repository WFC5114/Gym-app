import SwiftUI
import Vision
import VisionKit

/// Camera window inside the intake inset. Where the camera scanner is not
/// available (simulator, no permission), the barcode can be typed instead.
struct BarcodePanel: View {
    @Binding var barcode: String
    var message: String?
    let onCode: @MainActor (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if BarcodeScannerView.isAvailable {
                BarcodeScannerView { code in onCode(code) }
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityLabel("Camera barcode scanner")
            } else {
                Engraved(text: "CAMERA SCANNER NOT AVAILABLE · TYPE THE BARCODE", size: 8.5, color: .white.opacity(0.5))
            }
            HStack(spacing: 8) {
                TextField("", text: $barcode, prompt: Text("BARCODE DIGITS").foregroundStyle(.white.opacity(0.35)))
                    .keyboardType(.numberPad)
                    .font(TypeKit.label(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(InsetFieldWell())
                    .accessibilityLabel("Barcode digits")
                Button("LOOK UP") { onCode(barcode) }
                    .buttonStyle(MachineButtonStyle())
                    .frame(width: 96, height: 44)
                    .disabled(barcode.filter(\.isNumber).count < 6)
            }
            if let message {
                Text(message).font(TypeKit.label(9.5, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

struct BarcodeScannerView: UIViewControllerRepresentable {
    let onCode: @MainActor (String) -> Void

    @MainActor static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: @MainActor (String) -> Void
        private var lastCode: String?

        init(onCode: @escaping @MainActor (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let code = barcode.payloadStringValue, code != lastCode {
                    lastCode = code
                    HapticEngine.shared.tick(intensity: 0.7, sharpness: 0.6)
                    onCode(code)
                    return
                }
            }
        }
    }
}

/// Camera window that reads a nutrition facts panel (on-device text
/// recognition: nothing leaves the phone). Point it at the panel; once the
/// energy and macros are read it offers them to log.
struct LabelPanel: View {
    let onLabel: @MainActor (NutritionLabel) -> Void
    @State private var found: NutritionLabel?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if LabelScannerView.isAvailable {
                LabelScannerView { lines in
                    if let label = NutritionLabel.parse(lines), label != found {
                        if found == nil { HapticEngine.shared.tick(intensity: 0.7, sharpness: 0.6) }
                        found = label
                    }
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityLabel("Camera nutrition label reader")
            } else {
                Engraved(text: "LABEL READING NEEDS THE PHONE'S CAMERA", size: 8.5, color: .white.opacity(0.5))
            }
            if let found {
                HStack(spacing: 8) {
                    Text(summary(found))
                        .font(TypeKit.label(10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Button("USE") { onLabel(found) }
                        .buttonStyle(MachineButtonStyle())
                        .frame(width: 78, height: 44)
                        .accessibilityLabel("Use these label values")
                }
            } else {
                Text("POINT AT THE NUTRITION PANEL")
                    .font(TypeKit.label(9.5, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func summary(_ l: NutritionLabel) -> String {
        let g = { (v: Double?) in v.map { String(format: "%.0f", $0) } ?? "?" }
        let basis = l.basisAssumed ? "PER 100 G ASSUMED" : l.per100g ? "PER 100 G" : "PER SERVING"
        return "\(Int(l.kcal.rounded())) KCAL · P \(g(l.protein)) C \(g(l.carbs)) F \(g(l.fat)) · \(basis)"
    }
}

struct LabelScannerView: UIViewControllerRepresentable {
    let onText: @MainActor ([String]) -> Void

    @MainActor static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onText: onText) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onText: @MainActor ([String]) -> Void

        init(onText: @escaping @MainActor ([String]) -> Void) { self.onText = onText }

        /// Every line in view, top to bottom, so a value can be read with its name.
        private func report(_ items: [RecognizedItem]) {
            let lines = items.compactMap { item -> (CGFloat, String)? in
                if case .text(let text) = item { return (text.bounds.topLeft.y, text.transcript) }
                return nil
            }
            onText(lines.sorted { $0.0 < $1.0 }.flatMap { $0.1.components(separatedBy: .newlines) })
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }
    }
}
