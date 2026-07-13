import CoreLocationUI
import MapKit
import SwiftUI

struct LocationView: View {
    
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var viewModel: LocationViewModel
    
    init(entity: LocationMessageEntity) {
        _viewModel = StateObject(wrappedValue: LocationViewModel(objectID: entity.objectID))
    }
    
    var body: some View {
        NavigationView {
            MapView()
                .environmentObject(viewModel)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        CloseButton {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            if viewModel.canOpenGoogleMaps {
                                Button(viewModel.showInGoogleMapsButtonText) {
                                    viewModel.showInGoogleMaps()
                                }
                            }

                            Button(viewModel.showInMapsButtonText) {
                                viewModel.showInMaps()
                            }

                            Button(viewModel.calculateRouteButtonText) {
                                viewModel.calculateRoute()
                            }
                        } label: {
                            Label(viewModel.shareMenuText, systemImage: viewModel.shareImageName)
                        }
                    }
                }
                .onAppear {
                    viewModel.load()
                    viewModel.checkPermission()
                }
                .navigationTitle(viewModel.navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .navigationViewStyle(.stack)
        }
    }
}

struct MapView: View {
    @EnvironmentObject var viewModel: LocationViewModel
    @State private var position = MapCameraPosition.automatic
    @State private var mapStyle: MapStyle = .standard
    @Namespace private var namespace

    var body: some View {
        ZStack(alignment: .bottomTrailing,) {
            Map(position: $position) {
                if let pointOfInterest = viewModel.pointOfInterest {
                    Marker(pointOfInterest.name ?? "", coordinate: pointOfInterest.clLocationCoordinate)
                        .tint(Color.accentColor)
                    if let accuracy = pointOfInterest.accuracy {
                        MapCircle(center: pointOfInterest.clLocationCoordinate, radius: accuracy)
                            .foregroundStyle(UIColor.tintColor.color.opacity(0.5))
                            .stroke(UIColor.tintColor.color, lineWidth: 1)
                    }
                }
            }
            .mapStyle(mapStyle)
            .mapControls {
                if viewModel.isAuthorized {
                    MapUserLocationButton()
                }
            }
            .onChange(of: viewModel.pointOfInterest) {
                if let coordinate = viewModel.pointOfInterest {
                    position = .camera(MapCamera(centerCoordinate: coordinate.clLocationCoordinate, distance: 1000))
                }
            }

            if #available(iOS 26, *) {
                iOS26MapControlPanel
            }
            else {
                mapControlPanel
            }
        }
        .overlay(alignment: .bottom) {
            if [.denied].contains(viewModel.authorizationStatus) {
                LocationButton(.currentLocation) { }
                    .labelStyle(.titleAndIcon)
                    .symbolVariant(.fill)
                    .tint(.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(.capsule)
                    .padding(.vertical, 5)
            }
        }
    }
    
    @ViewBuilder
    private var mapControlPanel: some View {
        VStack(spacing: 4) {
            MapControlMenu(systemImage: viewModel.mapImageName) {
                Button(viewModel.mapStyleStandardText) { mapStyle = .standard }
                Button(viewModel.mapStyleHybridText) { mapStyle = .hybrid }
                Button(viewModel.mapStyleSatelliteText) { mapStyle = .imagery }
            }

            if let coord = viewModel.pointOfInterest {
                MapControlButton(systemImage: viewModel.centerMapPinImageName) {
                    withAnimation {
                        position = .camera(MapCamera(centerCoordinate: coord.clLocationCoordinate, distance: 1000))
                    }
                }
                .accessibilityLabel(viewModel.centerMapPinAccessibilityLabel)
            }
        }
        .padding(5)
        .padding(.bottom, 8)
    }

    private let unionID = UUID()

    @available(iOS 26, *) @ViewBuilder
    private var iOS26MapControlPanel: some View {
        GlassEffectContainer {
            VStack(spacing: 12.0) {
                Menu {
                    Button(viewModel.mapStyleStandardText) { mapStyle = .standard }
                    Button(viewModel.mapStyleHybridText) { mapStyle = .hybrid }
                    Button(viewModel.mapStyleSatelliteText) { mapStyle = .imagery }
                } label: {
                    Label("", systemImage: viewModel.mapImageName)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Color.primary)
                        .padding(.top, 8)
                        .padding(.horizontal, 2)
                }
                .buttonStyle(.glass)
                .glassEffectUnion(id: unionID, namespace: namespace)

                if let coordinate = viewModel.pointOfInterest {
                    Button {
                        withAnimation {
                            position = .camera(
                                MapCamera(centerCoordinate: coordinate.clLocationCoordinate, distance: 1000)
                            )
                        }
                    } label: {
                        Label("", systemImage: viewModel.centerMapPinImageName)
                            .labelStyle(.iconOnly)
                            .foregroundStyle(Color.primary)
                            .padding(.bottom, 8)
                            .padding(.horizontal, 2)
                    }
                    .buttonStyle(.glass)
                    .glassEffectUnion(id: unionID, namespace: namespace)
                    .accessibilityLabel(viewModel.centerMapPinAccessibilityLabel)
                }
            }
        }
        .padding(.trailing, 14)
        .padding(.bottom)
    }
}
