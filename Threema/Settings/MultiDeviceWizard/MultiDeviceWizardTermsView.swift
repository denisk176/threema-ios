//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2022-2025 Threema GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License, version 3,
// as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import SwiftUI
import ThreemaMacros

struct MultiDeviceWizardTermsView: View {
    @Environment(\.openURL) var openURL
    
    @ObservedObject var wizardVM: MultiDeviceWizardViewModel
    @Binding var dismiss: Bool
    var hasPFSEnabledContacts: Bool
    
    @State var didAcceptTerms = false
    @State var shouldShowAlert = false
    
    let bulletImageName = "info.circle.fill"
    let paddingSize: CGFloat = 8
    
    var body: some View {
        
        VStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading) {
                    // MARK: - Banner
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text(#localize("md_wizard_terms_note_text"))
                        }
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(uiColor: Colors.backgroundWizardBox))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .padding(.bottom)
                    
                    // MARK: - Bullet Points
                    
                    VStack(alignment: .leading, spacing: 0) {
                        
                        MultiDeviceWizardBulletPointView(
                            text: #localize("md_wizard_terms_backup"),
                            imageName: bulletImageName
                        )
                        .padding(.bottom, paddingSize)
                        .accessibilityAction(named: Text(String.localizedStringWithFormat(
                            #localize("accessibility_action_open_link"),
                            ThreemaURLProvider.iOSBackupManualEN.absoluteString
                        ))) {
                            openURL(ThreemaURLProvider.iOSBackupManualEN)
                        }
                        
                        MultiDeviceWizardBulletPointView(
                            text: #localize("md_wizard_terms_support"),
                            imageName: bulletImageName
                        )
                        .padding(.bottom, paddingSize)
                        
                        MultiDeviceWizardBulletPointView(
                            text: #localize("md_wizard_terms_issues"),
                            imageName: bulletImageName
                        )
                        .padding(.bottom, paddingSize)
                        .accessibilityAction(named: Text(String.localizedStringWithFormat(
                            #localize("accessibility_action_open_link"),
                            ThreemaURLProvider.multiDeviceLimit.absoluteString
                        ))) {
                            openURL(ThreemaURLProvider.multiDeviceLimit)
                        }
                        
                        MultiDeviceWizardBulletPointView(
                            text: #localize("md_wizard_terms_bugs"),
                            imageName: bulletImageName
                        )
                        .padding(.bottom, paddingSize)
                    }
                    .padding(.vertical)
                    
                    // MARK: - Terms Toggle
                    
                    Toggle(isOn: $didAcceptTerms) {
                        Text(#localize("md_wizard_terms_accept"))
                            .font(.headline)
                    }
                    .tint(.accentColor)
                    .padding(.trailing)
                    .onChange(of: didAcceptTerms) { newValue in
                        if hasPFSEnabledContacts {
                            shouldShowAlert = newValue
                        }
                    }
                    
                    Spacer()
                }
          
                HStack {
                    Button {
                        didAcceptTerms = false
                        dismiss = true
                        wizardVM.cancelLinking()
                    } label: {
                        Text(#localize("md_wizard_cancel"))
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                
                    Spacer()
                
                    NavigationLink {
                        MultiDeviceWizardInformationView(wizardVM: wizardVM, dismiss: $dismiss)
                    
                    } label: {
                        Text(#localize("md_wizard_next"))
                            .bold()
                    }
                    .disabled(!didAcceptTerms)
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical)
            }
        }
        
        .alert(#localize("forward_security"), isPresented: $shouldShowAlert, actions: {
            Button(#localize("md_wizard_disable_pfs_confirm"), role: .destructive) {
                // Termination will be sent when linking completes
            }
            Button(#localize("cancel"), role: .cancel) {
                didAcceptTerms = false
            }
            
        }, message: {
            Text(#localize("md_wizard_pfs_warning"))
        })
        .onDisappear {
            didAcceptTerms = false
        }
    }
}

// MARK: - Preview

struct MultiDeviceWizardIntroView_Previews: PreviewProvider {
    static var previews: some View {
        MultiDeviceWizardTermsView(
            wizardVM: MultiDeviceWizardViewModel(), dismiss: .constant(false), hasPFSEnabledContacts: true
        )
    }
}
