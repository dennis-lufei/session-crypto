// Copyright © 2024 Rangeproof Pty Ltd. All rights reserved.

import SwiftUI
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit
import SignalUtilitiesKit
import SessionNetworkingKit
import PhotosUI
import CoreImage

struct ScanQRCodePage: View {
    @EnvironmentObject var host: HostWrapper
    private let dependencies: Dependencies
    
    @State private var scannedResult: String = ""
    @State private var errorString: String? = nil
    @State private var showImagePicker: Bool = false
    
    init(using dependencies: Dependencies) {
        self.dependencies = dependencies
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                ScanQRCodeScreen(
                    $scannedResult,
                    error: $errorString,
                    continueAction: continueWithScannedQRCode,
                    using: dependencies
                )
                
                // 相册按钮
                Button {
                    showImagePicker = true
                } label: {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 24))
                        .foregroundColor(themeColor: .textPrimary)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(themeColor: .backgroundPrimary)
                        )
                }
                .padding(.trailing, 24)
                .padding(.bottom, geometry.safeAreaInsets.bottom + 24)
            }
            .backgroundColor(themeColor: .backgroundSecondary)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(onImagePicked: handleImagePicked)
        }
    }
    
    func continueWithScannedQRCode(onSuccess: (() -> ())?, onError: (() -> ())?) {
        startNewPrivateChatIfPossible(with: scannedResult, onError: onError)
    }
    
    func handleImagePicked(image: UIImage) {
        // 从图片中识别二维码
        guard let qrCodeString = detectQRCode(from: image) else {
            errorString = "识别二维码失败"
            return
        }
        
        // 识别成功，走添加好友流程
        scannedResult = qrCodeString
        continueWithScannedQRCode(onSuccess: nil, onError: nil)
    }
    
    func detectQRCode(from image: UIImage) -> String? {
        guard let ciImage = CIImage(image: image) else {
            return nil
        }
        
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: ciImage)
        
        guard let qrCodeFeatures = features as? [CIQRCodeFeature],
              let firstFeature = qrCodeFeatures.first,
              let messageString = firstFeature.messageString else {
            return nil
        }
        
        return messageString
    }
    
    fileprivate func startNewPrivateChatIfPossible(with sessionId: String, onError: (() -> ())?) {
        if !KeyPair.isValidHexEncodedPublicKey(candidate: sessionId) {
            errorString = "qrNotAccountId".localized()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                onError?()
            }
        }
        else {
            startNewDM(with: sessionId)
        }
    }
    
    private func startNewDM(with sessionId: String) {
        dependencies[singleton: .app].presentConversationCreatingIfNeeded(
            for: sessionId,
            variant: .contact,
            action: .compose,
            dismissing: self.host.controller,
            animated: false
        )
    }
}

// MARK: - ImagePickerView

struct ImagePickerView: UIViewControllerRepresentable {
    var onImagePicked: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 1
        configuration.filter = .images
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // No update needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var onImagePicked: (UIImage) -> Void
        
        init(onImagePicked: @escaping (UIImage) -> Void) {
            self.onImagePicked = onImagePicked
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let result = results.first else { return }
            
            if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        // Error loading image, silently fail
                        return
                    }
                    
                    guard let image = object as? UIImage else {
                        return
                    }
                    
                    DispatchQueue.main.async {
                        self.onImagePicked(image)
                    }
                }
            }
        }
    }
}

#Preview {
    ScanQRCodePage(using: Dependencies.createEmpty())
}
