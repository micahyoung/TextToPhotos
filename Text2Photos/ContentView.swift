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
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 50 // Increase limit for location filtering
        
        // Generate dynamic search filter (predicate + location) from search text using Foundation Models
        let searchFilter = try await generateDynamicSearchFilter(from: searchText)
        
        // Apply predicate if available
        if let predicate = searchFilter.predicate {
            fetchOptions.predicate = predicate
            print("🔍 Applied predicate to fetch: \(predicate)")
        } else {
            print("🔍 No predicate applied - fetching all photos")
        }
        
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        print("📊 PHAsset fetch returned \(assets.count) assets")
        
        var fetchedAssets: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            fetchedAssets.append(asset)
        }
        
        print("📊 Total assets after enumeration: \(fetchedAssets.count)")
        
        // Log some sample assets for debugging
        for (index, asset) in fetchedAssets.prefix(5).enumerated() {
            let hasLocation = asset.location != nil
            let locationString = if let loc = asset.location {
                "\(loc.coordinate.latitude), \(loc.coordinate.longitude)"
            } else {
                "No GPS"
            }
            print("📸 Asset \(index + 1): Date=\(asset.creationDate?.description ?? "nil"), Location=\(locationString), MediaSubtypes=\(asset.mediaSubtypes.rawValue)")
        }
        
        // Apply location filtering if specified
        if let locationFilter = searchFilter.locationFilter {
            print("🌍 Applying location filter for \(locationFilter.locationName)")
            print("🎯 Filter center: \(locationFilter.centerLatitude), \(locationFilter.centerLongitude) with \(locationFilter.radiusKm)km radius")
            
            var matchedCount = 0
            fetchedAssets = fetchedAssets.filter { asset in
                guard let location = asset.location else {
                    print("❌ Asset has no location data")
                    return false
                }
                
                let matches = locationFilter.matches(location)
                let distance = CLLocation(latitude: locationFilter.centerLatitude, longitude: locationFilter.centerLongitude)
                    .distance(from: location) / 1000.0
                
                if matches {
                    matchedCount += 1
                    print("✅ Asset matches location filter: \(location.coordinate.latitude), \(location.coordinate.longitude) (distance: \(String(format: "%.1f", distance))km)")
                } else {
                    print("❌ Asset outside radius: \(location.coordinate.latitude), \(location.coordinate.longitude) (distance: \(String(format: "%.1f", distance))km)")
                }
                return matches
            }
            print("🔍 Location filtering: \(matchedCount) matches out of original \(assets.count) photos")
        } else {
            print("📍 No location filter applied")
        }
        
        print("📊 Final asset count before limiting: \(fetchedAssets.count)")
        
        // Limit final results
        if fetchedAssets.count > 10 {
            fetchedAssets = Array(fetchedAssets.prefix(10))
            print("📊 Limited to 10 assets")
        }
        
        self.recentPhotos = fetchedAssets
        
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
                        // On macOS, PHImageManager returns NSImage directly
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
    
    // MARK: - Dynamic Predicate Generation with Foundation Models
    
    struct SearchFilter {
        let predicate: NSPredicate?
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
    
    private func generateDynamicSearchFilter(from searchText: String) async throws -> SearchFilter {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SearchFilter(predicate: nil, locationFilter: nil) }
        
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
        
        // Create system instructions with both predicate and location filter examples
        let systemInstructions = """
        You are an expert at analyzing natural language photo search queries and returning structured search filters.
        
        Your task is to analyze the user's search query and return a JSON response with both predicate and location filter information.
        
        RESPONSE FORMAT (JSON):
        {
          "predicate": "NSPredicate format string or null",
          "location": {
            "latitude": number,
            "longitude": number, 
            "radiusKm": number,
            "name": "string"
          } or null
        }
        
        RULES:
        1. Return valid JSON only, no explanations, no markdown formatting, no code blocks
        2. Use proper NSPredicate syntax for PHAsset properties
        3. If no predicate needed, set "predicate": null
        4. If no location filter needed, set "location": null
        5. For location queries, include both predicate "location != NULL" AND location filter details
        6. Do NOT wrap JSON in ```json or ``` blocks
        
        AVAILABLE PHRASSET PROPERTIES:
        - creationDate (Date) - when photo was taken
        - modificationDate (Date) - when photo was last modified
        - location (CLLocation?) - GPS location data (can only check for NULL/not NULL in predicate)
        - mediaType (PHAssetMediaType) - .image, .video, .audio
        - mediaSubtypes (PHAssetMediaSubtype) - .photoScreenshot, .photoPanorama, .photoHDR, .photoLive, .photoDepthEffect
        - pixelWidth, pixelHeight (Int) - image dimensions
        - favorite (Bool) - whether photo is marked as favorite
        - hidden (Bool) - whether photo is hidden
        - burstIdentifier (String?) - burst sequence identifier
        - representsBurst (Bool) - whether this is the key photo from a burst
        
        EXAMPLE RESPONSES:
        
        User: "favorite photos"
        Response: {"predicate": "favorite == YES", "location": null}
        
        User: "screenshots from today"
        Response: {"predicate": "mediaSubtypes & 4 != 0 AND creationDate >= %@ AND creationDate < %@", "location": null}
        
        User: "photos from San Francisco"
        Response: {"predicate": "location != NULL", "location": {"latitude": 37.7749, "longitude": -122.4194, "radiusKm": 25, "name": "San Francisco"}}
        
        User: "photos from Stockholm this month"
        Response: {"predicate": "location != NULL AND creationDate >= %@ AND creationDate < %@", "location": {"latitude": 59.3293, "longitude": 18.0686, "radiusKm": 30, "name": "Stockholm"}}
        
        User: "favorite photos from New York"
        Response: {"predicate": "favorite == YES AND location != NULL", "location": {"latitude": 40.7128, "longitude": -74.0060, "radiusKm": 30, "name": "New York"}}
        
        User: "photos with location"
        Response: {"predicate": "location != NULL", "location": null}
        
        User: "photos without location"
        Response: {"predicate": "location == NULL", "location": null}
        
        User: "large portrait photos"
        Response: {"predicate": "pixelHeight > pixelWidth AND (pixelWidth > 2000 OR pixelHeight > 2000)", "location": null}
        
        User: "HDR photos from London"
        Response: {"predicate": "mediaSubtypes & 8 != 0 AND location != NULL", "location": {"latitude": 51.5074, "longitude": -0.1278, "radiusKm": 20, "name": "London"}}
        
        MAJOR CITIES COORDINATES:
        - San Francisco: 37.7749, -122.4194 (radius: 25km)
        - New York: 40.7128, -74.0060 (radius: 30km)
        - Los Angeles: 34.0522, -118.2437 (radius: 35km)
        - Chicago: 41.8781, -87.6298 (radius: 25km)
        - London: 51.5074, -0.1278 (radius: 20km)
        - Paris: 48.8566, 2.3522 (radius: 15km)
        - Tokyo: 35.6762, 139.6503 (radius: 20km)
        - Sydney: -33.8688, 151.2093 (radius: 20km)
        - Berlin: 52.5200, 13.4050 (radius: 15km)
        - Rome: 41.9028, 12.4964 (radius: 15km)
        - Stockholm: 59.3293, 18.0686 (radius: 30km)
        - Amsterdam: 52.3676, 4.9041 (radius: 15km)
        - Barcelona: 41.3851, 2.1734 (radius: 20km)
        
        MEDIASUBTYPE VALUES:
        - photoScreenshot: 4
        - photoPanorama: 2  
        - photoHDR: 8
        - photoLive: 16
        - photoDepthEffect: 32
        
        IMPORTANT: Return raw JSON only - no markdown code blocks, no explanations, no ```json formatting.
        """
        
        do {
            // Create session with system instructions
            let session = LanguageModelSession(instructions: systemInstructions)
            
            // Generate structured response from user query
            let response = try await session.respond(to: query)
            let rawJsonString = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Clean the response - remove markdown code blocks if present
            let jsonString: String
            if rawJsonString.hasPrefix("```json") && rawJsonString.hasSuffix("```") {
                // Remove ```json at start and ``` at end
                let startIndex = rawJsonString.index(rawJsonString.startIndex, offsetBy: 7) // "```json".count
                let endIndex = rawJsonString.index(rawJsonString.endIndex, offsetBy: -3) // "```".count
                jsonString = String(rawJsonString[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if rawJsonString.hasPrefix("```") && rawJsonString.hasSuffix("```") {
                // Remove ``` at start and end
                let startIndex = rawJsonString.index(rawJsonString.startIndex, offsetBy: 3)
                let endIndex = rawJsonString.index(rawJsonString.endIndex, offsetBy: -3)
                jsonString = String(rawJsonString[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                jsonString = rawJsonString
            }
            
            print("🤖 AI Generated JSON response: '\(jsonString)' for query: '\(query)'")
            
            // Parse JSON response
            guard let jsonData = jsonString.data(using: .utf8) else {
                throw SearchError.predicateCreationFailed("Invalid JSON response")
            }
            
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            guard let json = jsonObject else {
                throw SearchError.predicateCreationFailed("Could not parse JSON response")
            }
            
            // Extract predicate
            var predicate: NSPredicate? = nil
            if let predicateString = json["predicate"] as? String {
                print("🔧 Creating predicate from: '\(predicateString)'")
                
                if predicateString.contains("%@") {
                    print("📅 Predicate contains date placeholders, handling date logic...")
                    predicate = try handleDatePredicate(predicateString, for: query)
                } else {
                    predicate = NSPredicate(format: predicateString)
                    print("✅ Successfully created predicate: \(predicate!)")
                }
            } else {
                print("🔍 No predicate specified")
            }
            
            // Extract location filter
            var locationFilter: LocationFilter? = nil
            if let locationData = json["location"] as? [String: Any],
               let lat = locationData["latitude"] as? Double,
               let lng = locationData["longitude"] as? Double,
               let radius = locationData["radiusKm"] as? Double,
               let name = locationData["name"] as? String {
                locationFilter = LocationFilter(
                    centerLatitude: lat,
                    centerLongitude: lng,
                    radiusKm: radius,
                    locationName: name
                )
                print("🌍 Location filter: \(name) at \(lat), \(lng) with \(radius)km radius")
            } else {
                print("📍 No location filter specified")
            }
            
            return SearchFilter(predicate: predicate, locationFilter: locationFilter)
            
        } catch let error as SearchError {
            throw error
        } catch {
            throw SearchError.foundationModelsError(error)
        }
    }
    
    private func generateDynamicPredicate(from searchText: String) async throws -> NSPredicate? {
        let searchFilter = try await generateDynamicSearchFilter(from: searchText)
        return searchFilter.predicate
    }
    
    private func handleDatePredicate(_ predicateFormat: String, for query: String) throws -> NSPredicate? {
        print("📅 Handling date predicate: '\(predicateFormat)' for query: '\(query)'")
        
        let calendar = Calendar.current
        let now = Date()
        let query = query.lowercased()
        
        // Determine the date range based on the query
        var startDate: Date?
        var endDate: Date?
        
        if query.contains("today") {
            startDate = calendar.startOfDay(for: now)
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate!)
            print("🗓️ Detected 'today' - start: \(startDate!), end: \(endDate!)")
        } else if query.contains("yesterday") {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
            startDate = calendar.startOfDay(for: yesterday)
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate!)
            print("🗓️ Detected 'yesterday' - start: \(startDate!), end: \(endDate!)")
        } else if query.contains("this week") || query.contains("week") {
            startDate = calendar.dateInterval(of: .weekOfYear, for: now)?.start
            endDate = now
            print("🗓️ Detected 'week' - start: \(startDate!), end: \(endDate!)")
        } else if query.contains("last week") {
            let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
            startDate = calendar.dateInterval(of: .weekOfYear, for: lastWeek)?.start
            endDate = calendar.date(byAdding: .weekOfYear, value: 1, to: startDate!)
            print("🗓️ Detected 'last week' - start: \(startDate!), end: \(endDate!)")
        } else if query.contains("this month") || query.contains("month") {
            startDate = calendar.dateInterval(of: .month, for: now)?.start
            endDate = now
            print("🗓️ Detected 'month' - start: \(startDate!), end: \(endDate!)")
        } else if query.contains("last month") {
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!
            startDate = calendar.dateInterval(of: .month, for: lastMonth)?.start
            endDate = calendar.date(byAdding: .month, value: 1, to: startDate!)
            print("🗓️ Detected 'last month' - start: \(startDate!), end: \(endDate!)")
        } else if query.contains("this year") || query.contains("year") {
            startDate = calendar.dateInterval(of: .year, for: now)?.start
            endDate = now
            print("🗓️ Detected 'year' - start: \(startDate!), end: \(endDate!)")
        } else {
            print("⚠️ No date pattern matched for query: '\(query)'")
        }
        
        // Create predicate with actual dates
        if let start = startDate, let end = endDate {
            let finalPredicate = NSPredicate(format: predicateFormat, start as NSDate, end as NSDate)
            print("✅ Created date range predicate: \(finalPredicate)")
            return finalPredicate
        } else if let start = startDate {
            let finalPredicate = NSPredicate(format: "creationDate >= %@", start as NSDate)
            print("✅ Created single date predicate: \(finalPredicate)")
            return finalPredicate
        }
        
        print("❌ Failed to create date predicate from: '\(predicateFormat)'")
        throw SearchError.predicateCreationFailed(predicateFormat)
    }
}

#Preview {
    ContentView()
}
