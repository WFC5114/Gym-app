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
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.1)))
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
