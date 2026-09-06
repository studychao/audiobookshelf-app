//
//  AbsDownloader.swift
//  App
//
//  Created by advplyr on 5/13/22.
//

import Foundation
import Capacitor
import RealmSwift

@objc(AbsDownloader)
public class AbsDownloader: CAPPlugin, CAPBridgedPlugin, URLSessionDownloadDelegate {
    public var identifier = "AbsDownloaderPlugin"
    public var jsName = "AbsDownloader"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "downloadLibraryItem", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "retryDownloads", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getDownloads", returnType: CAPPluginReturnPromise)
    ]
    
    static private let downloadsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "AbsDownloader")
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 3
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 7 * 24 * 60 * 60
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 5
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()
    private let progressStatusQueue = DispatchQueue(label: "progress-status-queue", attributes: .concurrent)
    private var downloadItemProgress = [String: DownloadItem]()
    private var monitoringProgressTimer: Timer?

    // Download queue management
    private let downloadQueueLock = NSLock()
    private var pendingDownloadTasks: [DownloadItemPartTask] = []
    private var activeDownloadTasks: Set<String> = [] // Track active task IDs
    private let maxConcurrentDownloads = 3
    private var restoring = false
    private var finalizing = Set<String>()

    override public func load() {
        NotificationCenter.default.addObserver(self, selector: #selector(restoreAfterForeground), name: UIApplication.didBecomeActiveNotification, object: nil)
        restoreDownloads(resetRetries: false)
    }

    @objc private func restoreAfterForeground() { restoreDownloads(resetRetries: false) }

    @objc func retryDownloads(_ call: CAPPluginCall) {
        restoreDownloads(resetRetries: true)
        call.resolve()
    }

    @objc func getDownloads(_ call: CAPPluginCall) {
        do {
            let items = try Realm().objects(DownloadItem.self).filter("serverConnectionConfigId == %@", Store.serverConfig?.id ?? "")
            call.resolve(["items": try items.map { try $0.asDictionary() }])
        } catch { call.reject("无法读取下载队列", nil, error) }
    }

    private func restoreDownloads(resetRetries: Bool) {
        downloadQueueLock.lock()
        if restoring { downloadQueueLock.unlock(); return }
        restoring = true
        downloadQueueLock.unlock()
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            defer { self.downloadQueueLock.lock(); self.restoring = false; self.downloadQueueLock.unlock() }
            do {
                let realm = try Realm()
                var known = Set(tasks.compactMap { $0.taskDescription })
                self.downloadQueueLock.lock()
                known.formUnion(self.pendingDownloadTasks.map { $0.partId })
                self.activeDownloadTasks.formUnion(tasks.filter { $0.state == .running }.compactMap { $0.taskDescription })
                self.downloadQueueLock.unlock()
                for item in realm.objects(DownloadItem.self) {
                    for part in item.downloadItemParts where !part.moved && !known.contains(part.id) {
                        if part.failed && !resetRetries { continue }
                        if let configId = item.serverConnectionConfigId, let config = realm.object(ofType: ServerConnectionConfig.self, forPrimaryKey: configId), var url = part.downloadURL.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) {
                            var query = (url.queryItems ?? []).filter { $0.name != "token" }
                            query.append(URLQueryItem(name: "token", value: config.token)); url.queryItems = query
                            if let updated = url.url { try realm.write {
                                if part.uri != updated.absoluteString { part.resumeData = nil }
                                part.uri = updated.absoluteString
                            } }
                        }
                        guard let url = part.downloadURL else { continue }
                        let task = part.resumeData.map { self.session.downloadTask(withResumeData: $0) } ?? self.session.downloadTask(with: url)
                        task.taskDescription = part.id
                        try realm.write { part.completed = false; part.failed = false; part.lastError = ""; if resetRetries { part.retryCount = 0 } }
                        self.downloadQueueLock.lock()
                        self.pendingDownloadTasks.append(DownloadItemPartTask(part: part.freeze(), task: task, partId: part.id, filename: part.filename ?? "音频"))
                        self.downloadQueueLock.unlock()
                    }
                    if item.didDownloadSuccessfully() { self.handleDownloadTaskCompleteFromDownloadItem(item.freeze()) }
                }
                for task in tasks where task.state == .suspended { task.resume() }
                self.startNextDownloadInQueue()
            } catch { AbsLogger.error(message: "恢复下载失败", error: error) }
        }
    }
    
    
    // MARK: - Download Queue Management

    private func startNextDownloadInQueue() {
        downloadQueueLock.lock()
        defer { downloadQueueLock.unlock() }

        // Start downloads up to the max concurrent limit
        while activeDownloadTasks.count < maxConcurrentDownloads && !pendingDownloadTasks.isEmpty {
            let nextTask = pendingDownloadTasks.removeFirst()
            activeDownloadTasks.insert(nextTask.partId)
            AbsLogger.info(message: "Starting download for \(nextTask.filename) (\(activeDownloadTasks.count)/\(maxConcurrentDownloads) active, \(pendingDownloadTasks.count) pending)")
            nextTask.task.resume()
        }
    }

    private func markDownloadTaskCompleted(_ taskId: String) {
        downloadQueueLock.lock()
        activeDownloadTasks.remove(taskId)
        downloadQueueLock.unlock()

        // Try to start the next download
        startNextDownloadInQueue()
    }


    // MARK: - Progress handling

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        handleDownloadTaskUpdate(downloadTask: downloadTask) { downloadItem, downloadItemPart in
            let realm = try Realm()
            let partId = downloadItemPart.id

            // Get fresh reference to the object in this realm
            guard let liveDownloadItemPart = realm.object(ofType: DownloadItemPart.self, forPrimaryKey: partId) else {
                throw LibraryItemDownloadError.downloadItemPartNotFound
            }

            let actualSize = (try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.int64Value ?? 0
            if let failure = DownloadValidation.failure(statusCode: (downloadTask.response as? HTTPURLResponse)?.statusCode, actualSize: actualSize, expectedSize: Int64(liveDownloadItemPart.fileSize), isCover: liveDownloadItemPart.filename == "cover.jpg") {
                try realm.write { liveDownloadItemPart.failed = true; liveDownloadItemPart.lastError = failure }
                return
            }
            
            do {
                // Move the downloaded file into place
                guard let destinationUrl = liveDownloadItemPart.destinationURL else {
                    throw LibraryItemDownloadError.downloadItemPartDestinationUrlNotDefined
                }
                try? FileManager.default.removeItem(at: destinationUrl)
                try FileManager.default.moveItem(at: location, to: destinationUrl)
                try realm.write {
                    liveDownloadItemPart.moved = true
                    liveDownloadItemPart.completed = true
                    liveDownloadItemPart.failed = false
                    liveDownloadItemPart.resumeData = nil
                    liveDownloadItemPart.bytesDownloaded = Double(actualSize)
                    liveDownloadItemPart.progress = 100
                }
            } catch {
                try realm.write {
                    liveDownloadItemPart.failed = true
                }
                throw error
            }
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        handleDownloadTaskUpdate(downloadTask: task) { downloadItem, downloadItemPart in
            if error != nil || downloadItemPart.failed {
                let realm = try Realm()
                let partId = downloadItemPart.id

                // Get fresh reference to the object in this realm
                guard let liveDownloadItemPart = realm.object(ofType: DownloadItemPart.self, forPrimaryKey: partId) else {
                    throw LibraryItemDownloadError.downloadItemPartNotFound
                }

                try realm.write {
                    liveDownloadItemPart.completed = true
                    liveDownloadItemPart.failed = true
                    liveDownloadItemPart.resumeData = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                    if let error { liveDownloadItemPart.lastError = error.localizedDescription }
                }
                let retry = DownloadValidation.shouldRetry(errorCode: (error as NSError?)?.code, statusCode: (task.response as? HTTPURLResponse)?.statusCode, attempt: liveDownloadItemPart.retryCount)
                if retry {
                    try realm.write { liveDownloadItemPart.retryCount += 1; liveDownloadItemPart.completed = false; liveDownloadItemPart.failed = false }
                    let delay = pow(2.0, Double(liveDownloadItemPart.retryCount))
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in self?.restoreDownloads(resetRetries: false) }
                }
            }
        }

        // Mark this task as completed and start the next download in queue
        if let taskId = task.taskDescription {
            markDownloadTaskCompleted(taskId)
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        handleDownloadTaskUpdate(downloadTask: downloadTask) { downloadItem, downloadItemPart in
            // Calculate the download percentage
            let percentDownloaded = (Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) * 100

            // Only update the progress if we received accurate progress data
            if percentDownloaded >= 0.0 && percentDownloaded <= 100.0 {
                let realm = try Realm()
                let partId = downloadItemPart.id

                // Get fresh reference to the object in this realm
                guard let liveDownloadItemPart = realm.object(ofType: DownloadItemPart.self, forPrimaryKey: partId) else {
                    throw LibraryItemDownloadError.downloadItemPartNotFound
                }

                try realm.write {
                    liveDownloadItemPart.bytesDownloaded = Double(totalBytesWritten)
                    liveDownloadItemPart.progress = percentDownloaded
                }
            }
        }
    }
    
    // Called when downloads are complete on the background thread
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
                let backgroundCompletionHandler =
                appDelegate.backgroundCompletionHandler else {
                    return
            }
            backgroundCompletionHandler()
        }
    }
    
    private func handleDownloadTaskUpdate(downloadTask: URLSessionTask, progressHandler: DownloadProgressHandler) {
        do {
            guard let downloadItemPartId = downloadTask.taskDescription else { throw LibraryItemDownloadError.noTaskDescription }
            AbsLogger.info(message: "Received download update for \(downloadItemPartId)")
            
            // Find the download item
            let downloadItem = Database.shared.getDownloadItem(downloadItemPartId: downloadItemPartId)
            guard var downloadItem = downloadItem else { throw LibraryItemDownloadError.downloadItemNotFound }
        
            // Find the download item part
            let part = downloadItem.downloadItemParts.first(where: { $0.id == downloadItemPartId })
            guard let part = part else { throw LibraryItemDownloadError.downloadItemPartNotFound }
            
            // Call the progress handler
            do {
                try progressHandler(downloadItem, part)
                try? self.notifyListeners("onDownloadItemPartUpdate", data: part.asDictionary())
            } catch {
                AbsLogger.error(message: "Error while processing progress")
                debugPrint(error)
            }
            
            // Update the progress
            downloadItem = downloadItem.freeze()
            self.progressStatusQueue.async(flags: .barrier) {
                self.downloadItemProgress.updateValue(downloadItem, forKey: downloadItem.id!)
            }
            self.notifyDownloadProgress()
        } catch {
            AbsLogger.error(message: "DownloadItemError")
            debugPrint(error)
        }
    }
    
    // We want to handle updating the UI in the background and throttled so we don't overload the UI with progress updates
    private func notifyDownloadProgress() {
        if self.monitoringProgressTimer?.isValid ?? false {
            AbsLogger.info(message: "Already monitoring progress, no need to start timer again")
        } else {
            DispatchQueue.runOnMainQueue {
                self.monitoringProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true, block: { [unowned self] t in
                    AbsLogger.info(message: "Starting monitoring download progress...")
                    
                    // Fetch active downloads in a thread-safe way
                    func fetchActiveDownloads() -> [String: DownloadItem]? {
                        self.progressStatusQueue.sync {
                            let activeDownloads = self.downloadItemProgress
                            if activeDownloads.isEmpty {
                                AbsLogger.info(message: "Finishing monitoring download progress...")
                                t.invalidate()
                            }
                            return activeDownloads
                        }
                    }
                    
                    // Remove a completed download item in a thread-safe way
                    func handleDoneDownloadItem(_ item: DownloadItem) {
                        self.progressStatusQueue.async(flags: .barrier) {
                            self.downloadItemProgress.removeValue(forKey: item.id!)
                        }
                        self.handleDownloadTaskCompleteFromDownloadItem(item)
                    }
                    
                    // Check for items done downloading
                    if let activeDownloads = fetchActiveDownloads() {
                        for item in activeDownloads.values {
                            if item.isDoneDownloading() { handleDoneDownloadItem(item) }
                        }
                    }
                })
            }
        }
    }
    
    private func handleDownloadTaskCompleteFromDownloadItem(_ downloadItem: DownloadItem) {
        guard downloadItem.didDownloadSuccessfully(), let downloadId = downloadItem.id else { return }
        downloadQueueLock.lock()
        let started = finalizing.insert(downloadId).inserted
        downloadQueueLock.unlock()
        guard started else { return }
        let finish: (LibraryItem?) -> Void = { [weak self] libraryItem in
            guard let self else { return }
            defer { self.downloadQueueLock.lock(); self.finalizing.remove(downloadId); self.downloadQueueLock.unlock() }
            do {
                guard let libraryItem else { throw LibraryItemDownloadError.downloadItemNotFound }
                let realm = try Realm()
                guard let savedDownload = realm.object(ofType: DownloadItem.self, forPrimaryKey: downloadId),
                      let configId = downloadItem.serverConnectionConfigId,
                      let server = realm.object(ofType: ServerConnectionConfig.self, forPrimaryKey: configId) else { return }
                var coverFile: String?
                let files: [LocalFile] = try downloadItem.downloadItemParts.map { part in
                    guard let filename = part.filename, let uri = part.destinationUri, let url = part.destinationURL,
                          FileManager.default.fileExists(atPath: url.path) else { throw LibraryItemDownloadError.downloadItemPartNotFound }
                    let mime = filename == "cover.jpg" ? "image/jpeg" : (part.mimeType() ?? "application/octet-stream")
                    if filename == "cover.jpg" { coverFile = uri }
                    return LocalFile(libraryItem.id, filename, mime, uri, fileSize: Int(url.fileSize))
                }
                var localItem = realm.objects(LocalLibraryItem.self).filter("libraryItemId == %@ AND serverConnectionConfigId == %@", libraryItem.id, configId).first
                var progress: LocalMediaProgress?
                // The local book, progress and queue removal commit together. A disk/Realm failure retains the queue.
                try realm.write {
                    if let existing = localItem, existing.isPodcast {
                        let names = Set(existing.localFiles.compactMap { $0.filename })
                        try existing.addFiles(files.filter { !names.contains($0.filename ?? "") }, item: libraryItem)
                    } else {
                        localItem = LocalLibraryItem(libraryItem, localUrl: libraryItem.id, server: server, files: files, coverPath: coverFile)
                        realm.add(localItem!, update: .modified)
                    }
                    if let remote = libraryItem.userMediaProgress, let localItem {
                        let episode = downloadItem.media?.episodes.first(where: { $0.id == downloadItem.episodeId })
                        let candidate = LocalMediaProgress(localLibraryItem: localItem, episode: episode, progress: remote)
                        let current = realm.object(ofType: LocalMediaProgress.self, forPrimaryKey: candidate.id)
                        if current == nil || current!.lastUpdate < candidate.lastUpdate {
                            realm.add(candidate, update: .modified)
                            progress = candidate
                        } else { progress = current }
                    }
                    realm.delete(savedDownload.downloadItemParts)
                    realm.delete(savedDownload)
                }
                var notification: [String: Any] = ["libraryItemId": downloadId]
                if let localItem { notification["localLibraryItem"] = try localItem.asDictionary() }
                if let progress { notification["localMediaProgress"] = try progress.asDictionary() }
                self.notifyListeners("onItemDownloadComplete", data: notification)
            } catch {
                AbsLogger.error(message: "文件已下载，本地书目保存失败；下载队列已保留", error: error)
                if let saved = Database.shared.getDownloadItem(downloadItemId: downloadId) {
                    try? saved.update { saved.downloadItemParts.forEach { $0.lastError = "保存到本机失败，请释放空间后重试" } }
                }
            }
        }
        if let snapshot = downloadItem.libraryItemSnapshot, let item = try? JSONDecoder().decode(LibraryItem.self, from: snapshot) { finish(item) }
        else { ApiClient.getLibraryItemWithProgress(libraryItemId: downloadItem.libraryItemId!, episodeId: downloadItem.episodeId, callback: finish) }
    }


    // MARK: - Capacitor functions
    
    @objc func downloadLibraryItem(_ call: CAPPluginCall) {
        let libraryItemId = call.getString("libraryItemId")
        var episodeId = call.getString("episodeId")
        if ( episodeId == "null" ) { episodeId = nil }
        
        AbsLogger.info(message: "Download library item \(libraryItemId ?? "N/A") / episode \(episodeId ?? "N/A")")
        guard let libraryItemId = libraryItemId else { return call.resolve(["error": "libraryItemId not specified"]) }
        
        ApiClient.getLibraryItemWithProgress(libraryItemId: libraryItemId, episodeId: episodeId) { [weak self] libraryItem in
            if let libraryItem = libraryItem {
                AbsLogger.info(message: "Got library item from server \(libraryItem.id)")
                do {
                    if let episodeId = episodeId {
                        // Download a podcast episode
                        guard libraryItem.mediaType == "podcast" else { throw LibraryItemDownloadError.libraryItemNotPodcast }
                        let episode = libraryItem.media?.episodes.enumerated().first(where: { $1.id == episodeId })?.element
                        guard let episode = episode else { throw LibraryItemDownloadError.podcastEpisodeNotFound }
                        try self?.startLibraryItemDownload(libraryItem, episode: episode)
                    } else {
                        // Download a book
                        try self?.startLibraryItemDownload(libraryItem)
                    }
                    call.resolve()
                } catch {
                    debugPrint(error)
                    call.resolve(["error": "Failed to download"])
                }
            } else {
                call.resolve(["error": "Server request failed"])
            }
        }
    }
    
    private func startLibraryItemDownload(_ item: LibraryItem) throws {
        try startLibraryItemDownload(item, episode: nil)
    }
    
    private func startLibraryItemDownload(_ item: LibraryItem, episode: PodcastEpisode?) throws {
        let tracks = List<AudioTrack>()
        var episodeId: String?
        
        // Handle the different media type downloads
        switch item.mediaType {
        case "book":
            guard item.media?.tracks.count ?? 0 > 0 || item.media?.ebookFile != nil else { throw LibraryItemDownloadError.noTracks }
            item.media?.tracks.forEach { t in tracks.append(AudioTrack.detachCopy(of: t)!) }
        case "podcast":
            guard let episode = episode else { throw LibraryItemDownloadError.podcastEpisodeNotFound }
            guard let podcastTrack = episode.audioTrack else { throw LibraryItemDownloadError.noTracks }
            episodeId = episode.id
            tracks.append(AudioTrack.detachCopy(of: podcastTrack)!)
        default:
            throw LibraryItemDownloadError.unknownMediaType
        }
        
        // Queue up everything for downloading
        let downloadItem = DownloadItem(libraryItem: item, episodeId: episodeId, server: Store.serverConfig!)
        var tasks = [DownloadItemPartTask]()
        for (i, track) in tracks.enumerated() {
            let task = try startLibraryItemTrackDownload(downloadItemId: downloadItem.id!, item: item, position: i, track: track, episode: episode)
            downloadItem.downloadItemParts.append(task.part)
            tasks.append(task)
        }
        
        if (item.media?.ebookFile != nil) {
            let task = try startLibraryItemEbookDownload(downloadItemId: downloadItem.id!, item: item, ebookFile: item.media!.ebookFile!)
            downloadItem.downloadItemParts.append(task.part)
            tasks.append(task)
        }
        
        // Also download the cover
        if item.media?.coverPath != nil && !(item.media?.coverPath!.isEmpty ?? true) {
            if let task = try? startLibraryItemCoverDownload(downloadItemId: downloadItem.id!, item: item) {
                downloadItem.downloadItemParts.append(task.part)
                tasks.append(task)
            }
        }
        
        // Notify client of download item
        try? self.notifyListeners("onDownloadItem", data: downloadItem.asDictionary())
        
        // Persist in the database before status start coming in
        try Database.shared.saveDownloadItem(downloadItem)

        // Add all tasks to the download queue
        downloadQueueLock.lock()
        pendingDownloadTasks.append(contentsOf: tasks)
        downloadQueueLock.unlock()

        AbsLogger.info(message: "Added \(tasks.count) tasks to download queue. Starting downloads...")

        // Start downloading (up to maxConcurrentDownloads at a time)
        startNextDownloadInQueue()
    }
    
    private func startLibraryItemTrackDownload(downloadItemId: String, item: LibraryItem, position: Int, track: AudioTrack, episode: PodcastEpisode?) throws -> DownloadItemPartTask {
        AbsLogger.info(message: "TRACK \(track.contentUrl!)")

        // If we don't name metadata, then we can't proceed
        guard let filename = track.metadata?.filename else {
            throw LibraryItemDownloadError.noMetadata
        }

        let serverUrl = urlForTrack(item: item, track: track)
        let itemDirectory = try createLibraryItemFileDirectory(item: item)
        let localUrl = "\(itemDirectory)/\(filename)"

        let task = session.downloadTask(with: serverUrl)
        let part = DownloadItemPart(downloadItemId: downloadItemId, filename: filename, destination: localUrl, itemTitle: track.title ?? "Unknown", serverPath: Store.serverConfig!.address, audioTrack: track, episode: episode, ebookFile: nil, size: track.metadata?.size ?? 0)
        part.uri = serverUrl.absoluteString

        // Store the id on the task so the download item can be pulled from the database later
        task.taskDescription = part.id

        return DownloadItemPartTask(part: part, task: task, partId: part.id, filename: filename)
    }
    
    private func startLibraryItemEbookDownload(downloadItemId: String, item: LibraryItem, ebookFile: EBookFile) throws -> DownloadItemPartTask {
        let filename = ebookFile.metadata?.filename ?? "ebook.\(ebookFile.ebookFormat)"
        let serverPath = "/api/items/\(item.id)/file/\(ebookFile.ino)/download"
        let itemDirectory = try createLibraryItemFileDirectory(item: item)
        let localUrl = "\(itemDirectory)/\(filename)"

        let part = DownloadItemPart(downloadItemId: downloadItemId, filename: filename, destination: localUrl, itemTitle: filename, serverPath: serverPath, audioTrack: nil, episode: nil, ebookFile: ebookFile, size: ebookFile.metadata?.size ?? 0)
        let task = session.downloadTask(with: part.downloadURL!)

        // Store the id on the task so the download item can be pulled from the database later
        task.taskDescription = part.id

        return DownloadItemPartTask(part: part, task: task, partId: part.id, filename: filename)
    }
    
    private func startLibraryItemCoverDownload(downloadItemId: String, item: LibraryItem) throws -> DownloadItemPartTask {
        let filename = "cover.jpg"
        let serverPath = "/api/items/\(item.id)/cover"
        let itemDirectory = try createLibraryItemFileDirectory(item: item)
        let localUrl = "\(itemDirectory)/\(filename)"

        // Find library file to get cover size
        let coverLibraryFile = item.libraryFiles.first(where: {
            $0.metadata?.path == item.media?.coverPath
        })

        let part = DownloadItemPart(downloadItemId: downloadItemId, filename: filename, destination: localUrl, itemTitle: "cover", serverPath: serverPath, audioTrack: nil, episode: nil, ebookFile: nil, size: coverLibraryFile?.metadata?.size ?? 0)
        let task = session.downloadTask(with: part.downloadURL!)

        // Store the id on the task so the download item can be pulled from the database later
        task.taskDescription = part.id

        return DownloadItemPartTask(part: part, task: task, partId: part.id, filename: filename)
    }
    
    private func urlForTrack(item: LibraryItem, track: AudioTrack) -> URL {
        // TODO: Future server release should include ino with AudioFile or FileMetadata
        let trackPath = track.metadata?.path ?? ""
        
        var audioFileIno = ""
        if (item.mediaType == "podcast") {
            let podcastEpisodes = item.media?.episodes ?? List<PodcastEpisode>()
            let matchingEpisode = podcastEpisodes.first(where: { $0.audioFile?.metadata?.path == trackPath })
            audioFileIno = matchingEpisode?.audioFile?.ino ?? ""
        } else {
            let audioFiles = item.media?.audioFiles ?? List<AudioFile>()
            let matchingAudioFile = audioFiles.first(where: { $0.metadata?.path == trackPath })
            audioFileIno = matchingAudioFile?.ino ?? ""
        }

        let urlstr = "\(Store.serverConfig!.address)/api/items/\(item.id)/file/\(audioFileIno)/download?token=\(Store.serverConfig!.token)"
        return URL(string: urlstr)!
    }
    
    private func createLibraryItemFileDirectory(item: LibraryItem) throws -> String {
        let itemDirectory = item.id
        AbsLogger.info(message: "ITEM DIR \(itemDirectory)")
        
        guard AbsDownloader.itemDownloadFolder(path: itemDirectory) != nil else {
            AbsLogger.error(message: "Failed to CREATE LI DIRECTORY \(itemDirectory)")
            throw LibraryItemDownloadError.failedDirectory
        }
        
        return itemDirectory
    }
    
    static func itemDownloadFolder(path: String) -> URL? {
        do {
            var itemFolder = AbsDownloader.downloadsDirectory.appendingPathComponent(path)
            
            if !FileManager.default.fileExists(atPath: itemFolder.path) {
                try FileManager.default.createDirectory(at: itemFolder, withIntermediateDirectories: true)
            }
            
            // Make sure we don't backup download files to iCloud
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try itemFolder.setResourceValues(resourceValues)
            
            return itemFolder
        } catch {
            AbsLogger.error(message: "Failed to CREATE LI DIRECTORY \(error)", error: error)
            return nil
        }
    }
    
}


// MARK: - Class structs

typealias DownloadProgressHandler = (_ downloadItem: DownloadItem, _ downloadItemPart: DownloadItemPart) throws -> Void

struct DownloadItemPartTask {
    let part: DownloadItemPart
    let task: URLSessionDownloadTask
    let partId: String // Cache the ID to avoid cross-thread Realm access
    let filename: String // Cache the filename to avoid cross-thread Realm access
}

enum LibraryItemDownloadError: String, Error {
    case noTracks = "No tracks on library item"
    case noMetadata = "No metadata for track, unable to download"
    case libraryItemNotPodcast = "Library item is not a podcast but episode was requested"
    case podcastEpisodeNotFound = "Invalid podcast episode not found"
    case podcastOnlySupported = "Only podcasts are supported for this function"
    case unknownMediaType = "Unknown media type"
    case failedDirectory = "Failed to create directory"
    case failedDownload = "Failed to download item"
    case noTaskDescription = "No task description"
    case downloadItemNotFound = "DownloadItem not found"
    case downloadItemPartNotFound = "DownloadItemPart not found"
    case downloadItemPartDestinationUrlNotDefined = "DownloadItemPart destination URL not defined"
    case libraryItemNotFound = "LibraryItem not found for id"
}
