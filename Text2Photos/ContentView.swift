//
//  ContentView.swift
//  Text2Photos
//
//  Created by user on 9/24/25.
//

import SwiftUI
import Photos
import PhotosUI

struct ContentView: View {
    @State private var searchText = ""
    @State private var recentPhotos: [PHAsset] = []
    @State private var photoImages: [NSImage] = []
    @State private var isLoading = false
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    
    var body: some View {
        VStack(spacing: 30) {
            // App title or logo area
            Text("Text2Photos")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Search interface
            VStack(spacing: 16) {
                TextField("Enter your search text...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .submitLabel(.search)
                    .onSubmit {
                        performSearch()
                    }
                
                Button(isLoading ? "Loading..." : "Submit") {
                    performSearch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
            .padding(.horizontal, 40)
            
            // Photos display area
            if !photoImages.isEmpty {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                        ForEach(Array(photoImages.enumerated()), id: \.offset) { index, image in
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 150, height: 150)
                                .clipped()
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 40)
                }
                .frame(maxHeight: 400)
            }
            
            if authorizationStatus == .denied {
                Text("Photo access denied. Please enable in System Preferences > Security & Privacy > Privacy > Photos.")
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            checkPhotoLibraryPermission()
        }
    }
    
    private func performSearch() {
        // Handle the search action here
        let trimmedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        print("Searching for: \(trimmedText)")
        fetchRecentPhotos()
    }
    
    private func checkPhotoLibraryPermission() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch authorizationStatus {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    self.authorizationStatus = status
                    if status == .authorized || status == .limited {
                        print("Photo access granted")
                    } else {
                        print("Photo access denied")
                    }
                }
            }
        case .authorized, .limited:
            print("Photo access already granted")
        case .denied, .restricted:
            print("Photo access denied or restricted")
        @unknown default:
            print("Unknown photo authorization status")
        }
    }
    
    private func fetchRecentPhotos() {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            print("Photo access not authorized")
            return
        }
        
        isLoading = true
        photoImages = [] // Clear previous results
        
        Task {
            do {
                let images = try await loadRecentPhotos()
                await MainActor.run {
                    self.photoImages = images
                    self.isLoading = false
                }
            } catch {
                print("Error loading photos: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadRecentPhotos() async throws -> [NSImage] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 10
        
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        var fetchedAssets: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            fetchedAssets.append(asset)
        }
        
        self.recentPhotos = fetchedAssets
        
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = true
        requestOptions.isSynchronous = false
        
        var loadedImages: [NSImage] = []
        
        for asset in fetchedAssets {
            let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSImage, Error>) in
                imageManager.requestImage(for: asset,
                                        targetSize: CGSize(width: 300, height: 300),
                                        contentMode: .aspectFill,
                                        options: requestOptions) { image, info in
                    if let error = info?[PHImageErrorKey] as? Error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    if let image = image {
                        // On macOS, PHImageManager returns NSImage directly
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: NSError(domain: "PhotoError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No image returned"]))
                    }
                }
            }
            
            loadedImages.append(image)
        }
        
        return loadedImages
    }
}

#Preview {
    ContentView()
}
