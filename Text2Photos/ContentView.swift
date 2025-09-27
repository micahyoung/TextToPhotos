//
//  ContentView.swift
//  Text2Photos
//
//  Created by user on 9/24/25.
//

import SwiftUI
import Photos
import PhotosUI
import FoundationModels
import CoreLocation
import SQLite3


struct ContentView: View {
    @State private var searchText = ""
    @State private var recentPhotos: [PHAsset] = []
    @State private var photoImages: [NSImage] = []
    @State private var isLoading = false
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var foundationModelsAvailable = false
    @State private var searchError: String?
    
    // SQLite database path for macOS Photos
    private var photosDBPath: String {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        return homeDirectory.appendingPathComponent("Pictures/Photos Library.photoslibrary/database/Photos.sqlite").path
    }
    
    var body: some View {
        VStack(spacing: 30) {
            // App title or logo area
            Text("Text2Photos")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Search interface
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    TextField("Enter your search text...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .submitLabel(.search)
                        .onSubmit {
                            performSearch()
                        }
                    
                    HStack {
                        Image(systemName: foundationModelsAvailable ? "brain.head.profile" : "brain.head.profile.fill")
                            .foregroundColor(foundationModelsAvailable ? .green : .orange)
                        Text(foundationModelsAvailable ? "AI-powered search enabled" : "Using fallback search")
                            .font(.caption)
                            .foregroundColor(foundationModelsAvailable ? .green : .orange)
                    }
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
            
            if let error = searchError {
                Text(error)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            checkPhotoLibraryPermission()
            checkFoundationModelsAvailability()
            validatePhotosDatabase()
        }
    }
    
    private func performSearch() {
        // Handle the search action here
        let trimmedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        searchError = nil // Clear any previous error
        print("Searching for: \(trimmedText)")
        fetchRecentPhotos()
    }
    
    private func checkFoundationModelsAvailability() {
        let model = SystemLanguageModel.default
        foundationModelsAvailable = model.availability == .available
        
        switch model.availability {
        case .available:
            print("Foundation Models available - AI-powered search enabled")
        case .unavailable(.deviceNotEligible):
            print("Foundation Models unavailable - device not eligible")
        case .unavailable(.appleIntelligenceNotEnabled):
            print("Foundation Models unavailable - Apple Intelligence not enabled")
        case .unavailable(.modelNotReady):
            print("Foundation Models unavailable - model not ready")
        case .unavailable(let other):
            print("Foundation Models unavailable - unknown reason: \(other)")
        }
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
            searchError = "Photo access not authorized. Please grant permission to access your photo library."
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
                    if let searchError = error as? SearchError {
                        self.searchError = searchError.localizedDescription
                    } else {
                        self.searchError = "Error loading photos: \(error.localizedDescription)"
                    }
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadRecentPhotos() async throws -> [NSImage] {
        // Generate dynamic search filter (SQL query + location) from search text using Foundation Models
        let searchSQL = try await generateDynamicSearchFilter(from: searchText)
        
        // Query SQLite database for UUIDs
        let photoUUIDs = try await queryPhotosDatabase(with: searchSQL)
        print("📊 SQLite query returned \(photoUUIDs.count) UUIDs")
        
        // Convert UUIDs to PHAssets
        var fetchedAssets: [PHAsset] = []
        if !photoUUIDs.isEmpty {
            let fetchOptions = PHFetchOptions()
            let uuidStrings = photoUUIDs.map { $0.uuidString }
            fetchOptions.predicate = NSPredicate(format: "uuid IN %@", uuidStrings)
            
            let assets = PHAsset.fetchAssets(with: fetchOptions)
            assets.enumerateObjects { asset, _, _ in
                fetchedAssets.append(asset)
            }
        }
        
        print("📊 Found \(fetchedAssets.count) PHAssets from UUIDs")
        
        // Limit final results
        if fetchedAssets.count > 10 {
            fetchedAssets = Array(fetchedAssets.prefix(10))
            print("📊 Limited to 10 assets")
        }
        
        self.recentPhotos = fetchedAssets
        
        // Load images from PHAssets
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = true
        requestOptions.isSynchronous = false
        
        var loadedImages: [NSImage] = []
        
        print("🖼️ Starting to load \(fetchedAssets.count) images...")
        
        for (index, asset) in fetchedAssets.enumerated() {
            let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSImage, Error>) in
                imageManager.requestImage(for: asset,
                                        targetSize: CGSize(width: 300, height: 300),
                                        contentMode: .aspectFill,
                                        options: requestOptions) { image, info in
                    if let error = info?[PHImageErrorKey] as? Error {
                        print("❌ Error loading image \(index + 1): \(error)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    if let image = image {
                        print("✅ Successfully loaded image \(index + 1)")
                        continuation.resume(returning: image)
                    } else {
                        print("❌ No image returned for asset \(index + 1)")
                        continuation.resume(throwing: NSError(domain: "PhotoError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No image returned"]))
                    }
                }
            }
            
            loadedImages.append(image)
        }
        
        print("🎉 Successfully loaded \(loadedImages.count) images")
        return loadedImages
    }
    
    // MARK: - SQLite Database Query
    
    private func queryPhotosDatabase(with searchSQL: String) async throws -> [UUID] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var db: OpaquePointer?
                    
                    // Check if database file exists
                    guard FileManager.default.fileExists(atPath: self.photosDBPath) else {
                        throw SearchError.predicateCreationFailed("Photos database not found at \(self.photosDBPath)")
                    }
                    
                    // Open SQLite database
                    if sqlite3_open_v2(self.photosDBPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
                        throw SearchError.predicateCreationFailed("Cannot open Photos database")
                    }
                    
                    defer {
                        sqlite3_close(db)
                    }
                    
                    // Build SQL query
                    print("🗄️ Executing SQL query: \(searchSQL)")
                    
                    var statement: OpaquePointer?
                    if sqlite3_prepare_v2(db, searchSQL, -1, &statement, nil) != SQLITE_OK {
                        let errorMsg = String(cString: sqlite3_errmsg(db))
                        throw SearchError.predicateCreationFailed("SQL prepare failed: \(errorMsg)")
                    }
                    
                    defer {
                        sqlite3_finalize(statement)
                    }
                    
                    var uuids: [UUID] = []
                    
                    // Execute query and collect UUIDs
                    while sqlite3_step(statement) == SQLITE_ROW {
                        if let uuidCString = sqlite3_column_text(statement, 0) {
                            let uuidString = String(cString: uuidCString)
                            if let uuid = UUID(uuidString: uuidString) {
                                uuids.append(uuid)
                            }
                        }
                    }
                    
                    print("🗄️ SQLite query returned \(uuids.count) UUIDs")
                    continuation.resume(returning: uuids)
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func buildDefaultQuery() -> String {
        return """
        SELECT ZUUID FROM ZASSET 
        WHERE ZTRASHEDSTATE = 0 
        AND ZKIND = 0
        ORDER BY ZDATECREATED DESC 
        LIMIT 50
        """
    }
    
    // MARK: - Database Validation (for testing)
    
    private func validatePhotosDatabase() {
        Task {
            do {
                print("🗄️ Checking Photos database at: \(photosDBPath)")
                guard FileManager.default.fileExists(atPath: photosDBPath) else {
                    print("❌ Photos database not found")
                    return
                }
                
                var db: OpaquePointer?
                guard sqlite3_open_v2(photosDBPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                    print("❌ Cannot open Photos database")
                    return
                }
                
                defer { sqlite3_close(db) }
                
                // Check if ZASSET table exists and count records
                let countQuery = "SELECT COUNT(*) FROM ZASSET WHERE ZTRASHEDSTATE = 0 AND ZKIND = 0"
                var statement: OpaquePointer?
                
                if sqlite3_prepare_v2(db, countQuery, -1, &statement, nil) == SQLITE_OK {
                    if sqlite3_step(statement) == SQLITE_ROW {
                        let count = sqlite3_column_int(statement, 0)
                        print("✅ Found \(count) photos in database")
                    }
                    sqlite3_finalize(statement)
                } else {
                    let error = String(cString: sqlite3_errmsg(db))
                    print("❌ Database query failed: \(error)")
                }
            }
        }
    }
    
}

#Preview {
    ContentView()
}

