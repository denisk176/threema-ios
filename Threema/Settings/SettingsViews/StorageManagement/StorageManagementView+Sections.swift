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

extension StorageManagementView {
    
    // MARK: - AllConversationSection
    
    struct AllConversationSection: View {
        @EnvironmentObject private var model: StorageManagementView.Model
        @Environment(\.appContainer.businessInjector)
        private var businessInjector: any BusinessInjectorProtocol
        
        @State private var conversations: [ConversationEntity] = []
        
        var body: some View {
            Section {
                ForEach(conversations) { conversation in
                    NavigationLink(
                        destination: StorageManagementConversationView(
                            businessInjector: businessInjector,
                            conversation: conversation
                        ),
                        label: {
                            StorageManagementConversationRow(
                                conversation: conversation
                            )
                        }
                    )
                }
                // needed for tasks to trigger because the Section is empty otherwise.
                if conversations.isEmpty {
                    VStack { }.hidden()
                }
            }
            .task(priority: .high) {
                let conversations = model.getAllConversations()
                await MainActor.run {
                    self.conversations = conversations
                }
            }
        }
        
        struct StorageManagementConversationRow: View {
            @EnvironmentObject private var model: StorageManagementView.Model
            @Environment(\.sizeCategory) private var sizeCategory
            @State private var profilePicture: UIImage = ProfilePictureGenerator.unknownContactImage
            @State private var metaData: StorageManagementView.Model.ConversationMetaData = (0, 0)
            private let conversation: ConversationEntity
            private let imageSize: CGFloat = 40
            
            init(conversation: ConversationEntity) {
                self.conversation = conversation
            }
            
            private var threemaTypeIconSize: CGFloat {
                sizeCategory.isAccessibilityCategory ? 20 : imageSize * 0.35
            }
            
            var body: some View {
                content
                    .accessibilityVStack(spacing: 8)
                    .task {
                        profilePicture = await model.profilePictureProvider(conversation)
                    }
            }
            
            @ViewBuilder
            private var content: some View {
                HStack(spacing: 8) {
                    if !sizeCategory.isAccessibilityCategory {
                        Image(uiImage: profilePicture)
                            .resizable()
                            .frame(width: imageSize, height: imageSize)
                            .clipShape(Circle())
                            .overlay(alignment: .bottomLeading) {
                                threemaTypeOverlay
                            }
                    }
                    Text(label)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .leading
                        )
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    VStack(spacing: 8) {
                        detailView
                    }
                    if sizeCategory.isAccessibilityCategory {
                        Spacer()
                    }
                }
            }
            
            private var threemaTypeOverlay: some View {
                if let contact = conversation.contact, contact.showOtherThreemaTypeIcon, !conversation.isGroup {
                    return AnyView(
                        Image(uiImage: ThreemaUtility.otherThreemaTypeIcon)
                            .resizable()
                            .frame(
                                width: threemaTypeIconSize,
                                height: threemaTypeIconSize
                            )
                            .accessibilityLabel(ThreemaUtility.otherThreemaTypeAccessibilityLabel)
                    )
                }
                return AnyView(EmptyView())
            }
            
            private var label: String {
                conversation.displayName
            }
            
            private var detailView: some View {
                VStack(alignment: sizeCategory.isAccessibilityCategory ? .leading : .trailing, spacing: 8) {
                    Text(verbatim: String.localizedStringWithFormat(
                        #localize("storage_number_of_messages"),
                        metaData.messageCount
                    ))
                    Text(verbatim: String.localizedStringWithFormat(
                        #localize("storage_number_of_files"),
                        metaData.fileCount
                    ))
                }
                .font(.callout)
                .lineLimit(sizeCategory.isAccessibilityCategory ? nil : 1)
                .foregroundColor(Color(uiColor: .secondaryLabel))
                .task {
                    metaData = await model.calcMetaData(for: conversation)
                }
            }
        }
    }
    
    // MARK: - ManageAllDataSection
    
    struct ManageAllDataSection: View {
        @EnvironmentObject private var model: StorageManagementView.Model
        @Environment(\.appContainer.businessInjector)
        private var businessInjector: any BusinessInjectorProtocol
        
        var body: some View {
            Section {
                NavigationLink(
                    destination: StorageManagementConversationView(
                        businessInjector: businessInjector
                    ),
                    label: {
                        Text(#localize("manage_all_conversations"))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                )
            }
        }
    }
    
    // MARK: - StorageSection
    
    struct StorageSection: View {
        @Environment(\.sizeCategory) private var sizeCategory
        @ObservedObject private var storageUsage = StorageUsage.shared

        var body: some View {
            Section {
                ForEach(StorageType.allCases) { type in
                    storageRow(type.label, value: type.valueKeyPath)
                }
            }
        }
        
        private func toValueString(_ value: Int64) -> String {
            value > 0 ? ByteCountFormatter
                .string(fromByteCount: value, countStyle: ByteCountFormatter.CountStyle.file) : "-"
        }
        
        private func storageRow(_ label: String, value: KeyPath<StorageUsage, Int64>) -> some View {
            Group {
                Text(label)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(toValueString(storageUsage[keyPath: value]))
                    .lineLimit(sizeCategory.isAccessibilityCategory ? nil : 1)
                    .foregroundColor(Color(uiColor: .secondaryLabel))
                    .frame(maxWidth: .infinity, alignment: sizeCategory.isAccessibilityCategory ? .leading : .trailing)
                    .copyLabel(value: toValueString(storageUsage[keyPath: value]))
                    .accessibilityValue(toValueString(storageUsage[keyPath: value]))
            }
            .font(.body)
            .accessibilityVStack(spacing: 8)
            .accessibilityElement(children: .combine)
            .fixedSize(horizontal: false, vertical: true)
            .task(priority: .userInitiated, storageUsage.calcDeviceStorage)
        }
    }
}

// MARK: - StorageManagementView.StorageSection.StorageType

extension StorageManagementView.StorageSection {
    enum StorageType: CaseIterable, Identifiable {
        var id: Self { self }
        
        case total
        case totalInUse
        case totalFree
        case threema
        
        var label: String {
            switch self {
            case .total:
                #localize("storage_total")
            case .totalInUse:
                #localize("storage_total_in_use")
            case .totalFree:
                #localize("storage_total_free")
            case .threema:
                String.localizedStringWithFormat(
                    #localize("storage_threema"),
                    ThreemaApp.currentName
                )
            }
        }
        
        var valueKeyPath: KeyPath<StorageManagementView.StorageUsage, Int64> {
            switch self {
            case .total:
                \.total
            case .totalInUse:
                \.totalInUse
            case .totalFree:
                \.totalFree
            case .threema:
                \.threema
            }
        }
    }
}
