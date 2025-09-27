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

enum SearchError: LocalizedError {
    case foundationModelsNotAvailable(reason: String)
    case foundationModelsError(Error)
    case predicateCreationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .foundationModelsNotAvailable(let reason):
            return "AI search is not available: \(reason). Please ensure Apple Intelligence is enabled in Settings."
        case .foundationModelsError(let error):
            return "AI search error: \(error.localizedDescription)"
        case .predicateCreationFailed(let predicateString):
            return "Failed to create search filter from: '\(predicateString)'. Please try rephrasing your search."
        }
    }
}

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
    
    // MARK: - Dynamic SQL Query Generation with Foundation Models
    
    struct SearchFilter {
        let sqlQuery: String?
        let locationFilter: LocationFilter?
    }
    
    struct LocationFilter {
        let centerLatitude: Double
        let centerLongitude: Double
        let radiusKm: Double
        let locationName: String
        
        func matches(_ location: CLLocation) -> Bool {
            let center = CLLocation(latitude: centerLatitude, longitude: centerLongitude)
            let distanceKm = location.distance(from: center) / 1000.0
            return distanceKm <= radiusKm
        }
    }
    
    private func generateDynamicSearchFilter(from searchText: String) async throws -> String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if Foundation Models is available
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            throw SearchError.foundationModelsNotAvailable(reason: "Device not eligible for Apple Intelligence")
        case .unavailable(.appleIntelligenceNotEnabled):
            throw SearchError.foundationModelsNotAvailable(reason: "Apple Intelligence not enabled")
        case .unavailable(.modelNotReady):
            throw SearchError.foundationModelsNotAvailable(reason: "AI model not ready (downloading or system busy)")
        case .unavailable(let other):
            throw SearchError.foundationModelsNotAvailable(reason: "Unknown reason: \(other)")
        }
        
        // Create system instructions with SQL query examples instead of predicate examples
        let systemInstructions = """
You are an expert at analyzing natural language photo search queries and returning SQL queries for the macOS Photos SQLite database.

Your task is to analyze the user's search query and return a SQL query reponse.

RESPONSE FORMAT (SQL):
```sql
SELECT ZUUID FROM ...
```

RULES:
1. Return valid SQL only without explanations
2. Use proper SQL syntax for Photos SQLite database
5. Always SELECT ZUUID as the first column
6. Base table is ZASSET for photos
7. Always wrap SQL response in ```sql blocks

PHOTOS DATABASE SCHEMA (DDL subset):
```sql
CREATE TABLE ZASSET (
  Z_PK INTEGER PRIMARY KEY,
  ZUUID TEXT, -- Unique identifier for photo
  ZDATECREATED REAL, -- Creation timestamp (Core Data absolute time)
  ZLATITUDE REAL, -- GPS latitude
  ZLONGITUDE REAL, -- GPS longitude
  ZKIND INTEGER, -- Media type (0=photo, 1=video)
  ZTRASHEDSTATE INTEGER, -- 0=not trashed, 1=trashed
  ZFAVORITE INTEGER, -- 0=not favorite, 1=favorite
  ZHIDDEN INTEGER, -- 0=not hidden, 1=hidden
  ZPIXELWIDTH INTEGER, -- Image width in pixels
  ZPIXELHEIGHT INTEGER, -- Image height in pixels
  ZADDEDDATE REAL, -- Date added (Core Data absolute time)
  ZMODIFICATIONDATE REAL -- Last modification date (Core Data absolute time)
);
```

```sql
CREATE TABLE ZADDITIONALASSETATTRIBUTES (
  Z_PK INTEGER PRIMARY KEY,
  ZASSET INTEGER, -- Foreign key to ZASSET.Z_PK
  ZSCENECLASSIFICATION TEXT, -- AI-generated scene labels
  ZKEYWORDS TEXT, -- Keywords and tags
  FOREIGN KEY(ZASSET) REFERENCES ZASSET(Z_PK)
);
```

```sql
CREATE TABLE ZGENERICALBUM (
  Z_PK INTEGER PRIMARY KEY,
  ZTITLE TEXT, -- Album name
  ZKIND INTEGER -- Album type
);
```

COMMON SQL PATTERNS:
- Always filter out trashed photos: `WHERE ZTRASHEDSTATE = 0`
- Photo only (not video): `AND ZKIND = 0`
- Sort by creation date: `ORDER BY ZDATECREATED DESC`
- Limit results: `LIMIT 50`
- Favorites: `AND ZFAVORITE = 1`
- Hidden photos: `AND ZHIDDEN = 1`
- Location: `AND ZLATITUDE BETWEEN`
- Date ranges in sqlite timestamp format: `AND ZDATECREATED > (strftime('%s','now','-1 days')`

EXAMPLE RESPONSES:

Q: favorite photos
A: ```sql
SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0 AND ZKIND = 0 AND ZFAVORITE = 1 ORDER BY ZDATECREATED DESC LIMIT 50
```

Q: photos from San Francisco
A: ```sql
SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0 AND ZKIND = 0 AND ZLATITUDE BETWEEN 37.60 AND 37.90 AND ZLONGITUDE BETWEEN -123.00 AND -122.20 ORDER BY ZDATECREATED DESC LIMIT 50
```

Q: photos from this month
A: ```sql
SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0 AND ZKIND = 0 AND ZDATECREATED > (strftime('%s','now','-30 days') - 978307200) ORDER BY ZDATECREATED DESC LIMIT 50
```

Q: large photos
A: ```sql
SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0 AND ZKIND = 0 AND (ZPIXELWIDTH > 2000 OR ZPIXELHEIGHT > 2000) ORDER BY ZDATECREATED DESC LIMIT 50
```

Q: hidden photos
A: ```sql
SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0 AND ZKIND = 0 AND ZHIDDEN = 1 ORDER BY ZDATECREATED DESC LIMIT 50
```

Q: recent photos
A: ```sql
SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0 AND ZKIND = 0 ORDER BY ZDATECREATED DESC LIMIT 50
```

Q: portrait photos
A: ```sql
SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0 AND ZKIND = 0 AND ZPIXELHEIGHT > ZPIXELWIDTH ORDER BY ZDATECREATED DESC LIMIT 50
```
"""
        
        do {
            // Create session with system instructions
            let session = LanguageModelSession(instructions: systemInstructions)
            
            // Generate structured response from user query
            let response = try await session.respond(to: query)
            let rawSQLString = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Clean the response - remove markdown code blocks if present
            let sqlString: String
            if rawSQLString.hasPrefix("```sql") && rawSQLString.hasSuffix("```") {
                // Remove ```json at start and ``` at end
                let startIndex = rawSQLString.index(rawSQLString.startIndex, offsetBy: 7) // "```json".count
                let endIndex = rawSQLString.index(rawSQLString.endIndex, offsetBy: -3) // "```".count
                sqlString = String(rawSQLString[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                sqlString = rawSQLString
            }
          
            return sqlString
            
        } catch let error as SearchError {
            throw error
        } catch {
            throw SearchError.foundationModelsError(error)
        }
    }
}

#Preview {
    ContentView()
}

