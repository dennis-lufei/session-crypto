// Copyright © 2024 Rangeproof Pty Ltd. All rights reserved.

import SwiftUI
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit
import SignalUtilitiesKit
import SessionNetworkingKit

struct AddFriendScreen: View {
    @EnvironmentObject var host: HostWrapper
    private let dependencies: Dependencies
    
    @State private var accountIdOrONS: String = ""
    @State private var errorString: String? = nil
    
    init(using dependencies: Dependencies) {
        self.dependencies = dependencies
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(
                alignment: .center,
                spacing: Values.mediumSpacing
            ) {
                SessionTextField(
                    $accountIdOrONS,
                    placeholder: "accountIdOrOnsEnter".localized(),
                    error: $errorString,
                    accessibility: Accessibility(
                        identifier: "Session id input box",
                        label: "Session id input box"
                    ),
                    explanationView: {
                        ZStack {
                            (Text("messageNewDescriptionMobile".localized()) + Text(Image(systemName: "questionmark.circle")))
                                .font(.system(size: Values.verySmallFontSize))
                                .foregroundColor(themeColor: .textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .accessibility(
                            Accessibility(
                                identifier: "Help desk link",
                                label: "Help desk link"
                            )
                        )
                        .padding(.horizontal, Values.smallSpacing)
                        .padding(.top, Values.smallSpacing)
                        .onTapGesture {
                            if let url: URL = URL(string: "https://sessionapp.zendesk.com/hc/en-us/articles/4439132747033-How-do-Session-ID-usernames-work-") {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                )
                
                Spacer()
                
                if !accountIdOrONS.isEmpty {
                    Button {
                        continueWithAccountIdOrONS()
                    } label: {
                        Text("next".localized())
                            .bold()
                            .font(.system(size: Values.smallFontSize))
                            .foregroundColor(themeColor: .sessionButton_text)
                            .frame(
                                maxWidth: 160,
                                maxHeight: Values.largeButtonHeight,
                                alignment: .center
                            )
                            .overlay(
                                Capsule()
                                    .stroke(themeColor: .sessionButton_border)
                            )
                    }
                    .accessibility(
                        Accessibility(
                            identifier: "Next",
                            label: "Next"
                        )
                    )
                    .padding(.horizontal, Values.massiveSpacing)
                }
            }
            .padding(.all, Values.largeSpacing)
        }
        .backgroundColor(themeColor: .backgroundSecondary)
    }
    
    func continueWithAccountIdOrONS() {
        let maybeSessionId: SessionId? = try? SessionId(from: accountIdOrONS)
        
        if KeyPair.isValidHexEncodedPublicKey(candidate: accountIdOrONS) {
            switch maybeSessionId?.prefix {
                case .standard:
                    startNewDM(with: accountIdOrONS)
                    
                default:
                    errorString = "accountIdErrorInvalid".localized()
            }
            return
        }
        
        // This could be an ONS name
        ModalActivityIndicatorViewController
            .present(fromViewController: self.host.controller?.navigationController!, canCancel: false) { modalActivityIndicator in
            Network.SnodeAPI
                .getSessionID(for: accountIdOrONS, using: dependencies)
                .subscribe(on: DispatchQueue.global(qos: .userInitiated))
                .receive(on: DispatchQueue.main)
                .sinkUntilComplete(
                    receiveCompletion: { result in
                        switch result {
                            case .finished: break
                            case .failure(let error):
                                modalActivityIndicator.dismiss {
                                    let message: String = {
                                        switch error {
                                            case SnodeAPIError.onsNotFound:
                                                return "onsErrorNotRecognized".localized()
                                            default:
                                                return "onsErrorUnableToSearch".localized()
                                        }
                                    }()
                                    
                                    errorString = message
                                }
                        }
                    },
                    receiveValue: { sessionId in
                        modalActivityIndicator.dismiss {
                            self.startNewDM(with: sessionId)
                        }
                    }
                )
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

#Preview {
    AddFriendScreen(using: Dependencies.createEmpty())
}

