//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2023-2025 Threema GmbH
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
import ThreemaFramework
import ThreemaMacros

struct ChatSettingsView: View {
    @EnvironmentObject var settingsVM: SettingsStore

    var body: some View {
        List {
            // MARK: - Wallpaper
    
            WallpaperSectionView()
                .environmentObject(settingsVM)
            
            // MARK: - Chat

            Section {
                Toggle(isOn: $settingsVM.useBigEmojis) {
                    Text(#localize("settings_chat_bigger_emojis"))
                }
                Toggle(isOn: $settingsVM.sendMessageFeedback) {
                    Text(#localize("settings_chat_send_message_feedback_label"))
                }
                Button(role: .destructive) {
                    UserSettings.shared().resetEmojiReactions()
                    NotificationPresenterWrapper.shared.present(type: .emojisReset)
                } label: {
                    Text(#localize("settings_chat_reset_emoji_label"))
                }
            } footer: {
                Text(#localize("settings_chat_reset_emoji_footer"))
            }
        }
        .navigationBarTitle(#localize("settings_list_chat_title"), displayMode: .inline)
        .tint(.accentColor)
    }
}

struct ChatSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ChatSettingsView()
    }
}

// MARK: - WallpaperSectionView

struct WallpaperSectionView: View {
    @EnvironmentObject var settingsVM: SettingsStore
    @State private var showingImagePicker = false
    @State private var showDeleteAlert = false
    
    @State var emptySelected = false
    @State var emptyImage: Image? = Image(uiImage: UIImage(ciImage: CIImage.empty()))

    @State var threemaSelected = false
    @State var threemaImage: Image? = Image(uiImage: WallpaperStore.shared.defaultWallPaper)

    @State var customSelected = false
    @State var isSelectingCustom = false
    @State var customImage: Image?
    @State var selectedUIImage: UIImage?
    
    var body: some View {
        
        Section(header: Text(#localize("settings_chat_wallpaper_title"))) {
            HStack(alignment: .center, spacing: 20) {
                WallpaperTypeView(
                    description: #localize("settings_chat_wallpaper_empty"),
                    image: $emptyImage,
                    isSelected: $emptySelected,
                    isSelectingCustom: $isSelectingCustom
                )
                .onTapGesture {
                    selectEmpty()
                }
                
                WallpaperTypeView(
                    description: TargetManager.appName,
                    image: $threemaImage,
                    isSelected: $threemaSelected,
                    isSelectingCustom: $isSelectingCustom
                )
                .onTapGesture {
                    selectThreema()
                }
                
                WallpaperTypeView(
                    description: #localize("settings_chat_wallpaper_custom"),
                    image: $customImage,
                    isSelected: $customSelected,
                    isSelectingCustom: $isSelectingCustom
                )
                .onTapGesture {
                    selectCustom()
                }
                .onChange(of: selectedUIImage) { image in
                    guard image != nil, isSelectingCustom else {
                        return
                    }
                    
                    settingsVM.wallpaperStore.saveDefaultWallpaper(selectedUIImage)
                    selectedUIImage = nil
                }
                .onReceive(
                    NotificationCenter.default
                        .publisher(for: Notification.Name(kNotificationWallpaperChanged))
                ) { _ in
                    loadImage()
                }
            }
            .edgesIgnoringSafeArea(.leading)
            
            HStack {
                Spacer()
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Text(#localize("settings_chat_wallpaper_reset"))
                }
                Spacer()
            }
            .sheet(isPresented: $showingImagePicker) {
                SwiftUIImagePicker(image: $selectedUIImage)
            }
        }
        
        .alert(isPresented: $showDeleteAlert, content: {
            Alert(
                title: Text(#localize("settings_chat_wallpaper_reset")),
                message: Text(#localize("settings_chat_wallpaper_reset_all_alert")),
                primaryButton: .destructive(Text(
                    #localize("settings_privacy_TIRR_reset_alert_action")
                )) {
                    settingsVM.wallpaperStore.deleteAllCustom()
                },
                secondaryButton: .default(Text(#localize("cancel"))) {
                    // Noop
                }
            )
        })
        
        .onAppear {
            if settingsVM.wallpaperStore.defaultIsEmptyWallpaper() {
                emptySelected = true
                customImage = nil
            }
            else if settingsVM.wallpaperStore.defaultIsThreemaWallpaper() {
                threemaSelected = true
                customImage = nil
            }
            else {
                selectedUIImage = settingsVM.wallpaperStore.currentDefaultWallpaper()
                customImage = Image(uiImage: selectedUIImage!)
                customSelected = true
            }
        }
    }
    
    // MARK: - Private Functions
    
    private func selectEmpty() {
        settingsVM.wallpaperStore.saveDefaultWallpaper(nil)
        withAnimation {
            emptySelected = true
            threemaSelected = false
            isSelectingCustom = false
            customSelected = false
            selectedUIImage = nil
            customImage = nil
        }
    }
    
    private func selectThreema() {
        settingsVM.wallpaperStore.saveDefaultWallpaper(settingsVM.wallpaperStore.defaultWallPaper)

        withAnimation {
            emptySelected = false
            threemaSelected = true
            isSelectingCustom = false
            customSelected = false
            selectedUIImage = nil
            customImage = nil
        }
    }
    
    private func selectCustom() {
        withAnimation {
            emptySelected = false
            threemaSelected = false
            customImage = nil
            isSelectingCustom = true
            customSelected = true
            showingImagePicker = true
        }
    }
    
    private func loadImage() {
        isSelectingCustom = false

        if settingsVM.wallpaperStore.defaultIsEmptyWallpaper() {
            emptySelected = true
            customImage = nil
        }
        else if settingsVM.wallpaperStore.defaultIsThreemaWallpaper() {
            threemaSelected = true
            customImage = nil
        }
        else {
            selectedUIImage = settingsVM.wallpaperStore.currentDefaultWallpaper()
            customImage = Image(uiImage: selectedUIImage!)
            customSelected = true
        }
    }
}

// MARK: - WallpaperTypeView

struct WallpaperTypeView: View {
    var description: String
    @Binding var image: Image?
    @Binding var isSelected: Bool
    @Binding var isSelectingCustom: Bool

    var body: some View {
        VStack(spacing: 5) {
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Rectangle()
                .foregroundColor(.clear)
                .frame(width: 80, height: 150)
                .background {
                  
                    if let image {
                        if let uiImage = image.getUIImage(newSize: CGSize(width: 240, height: 450)) {
                            Image(uiImage: MediaConverter.downscaleImage(
                                image: uiImage,
                                toSize: CGSize(width: 80, height: 150)
                            ))
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 150)
                            .cornerRadius(15)
                        }
                        else {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 150)
                                .cornerRadius(15)
                        }
                    }
                    else if isSelectingCustom, image == nil {
                        ProgressView()
                    }
                    else {
                        Image(systemName: "plus.circle")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(25)
                            .foregroundColor(.accentColor)
                    }
                }
                .cornerRadius(15)
                .clipped()
                .contentShape(Rectangle())
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(
                            Color(uiColor: isSelected ? .tintColor : .tertiaryLabel),
                            lineWidth: 2
                        )
                }
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .imageScale(.large)
                    .foregroundColor(.accentColor)
            }
            else {
                Image(systemName: "circle")
                    .imageScale(.large)
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
            }
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity)
    }
}

extension Image {
    @MainActor
    func getUIImage(newSize: CGSize) -> UIImage? {
        let image = resizable()
            .scaledToFill()
            .frame(width: newSize.width, height: newSize.height)
            .clipped()
        if #available(iOS 16.0, *) {
            return ImageRenderer(content: image).uiImage
        }
        else {
            // Fallback on earlier versions
            return nil
        }
    }
}
