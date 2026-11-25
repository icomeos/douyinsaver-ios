import Foundation

enum DownloadError: LocalizedError {
    case noUrl
    case http(Int)
    case incomplete
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noUrl: return "没有可下载的视频地址"
        case .http(let c): return "下载请求失败 HTTP \(c)"
        case .incomplete: return "下载未完成"
        case .cancelled: return "已取消"
        }
    }
}

/// 断点续传下载器：多候选轮换 + Range 续传 + 连续断流强制新连接
final class Downloader {

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 3600
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        return URLSession(configuration: cfg)
    }()

    /// 下载到临时文件，返回本地文件 URL（调用方负责存相册并在之后删除）
    func download(
        urls: [String],
        referer: String,
        progress: @escaping (Int) -> Void,
        checkCancelled: @escaping () -> Bool
    ) async throws -> URL {
        guard !urls.isEmpty else { throw DownloadError.noUrl }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl_\(Int(Date().timeIntervalSince1970)).part")
        let maxRounds = urls.count * 4 + 6
        var totalBytes: Int64 = -1
        var consecutiveClosed = 0
        var lastError: Error = DownloadError.incomplete

        defer { try? FileManager.default.removeItem(at: tmp) }

        var round = 0
        while round < maxRounds {
            if checkCancelled() { throw DownloadError.cancelled }
            let url = urls[round % urls.count]
            guard let u = URL(string: url) else { round += 1; continue }

            let already = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? NSNumber)?.int64Value ?? 0
            let wantResume = already > 0
            var req = URLRequest(url: u)
            req.setValue(VideoParser.uaMobile, forHTTPHeaderField: "User-Agent")
            req.setValue(referer, forHTTPHeaderField: "Referer")
            req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            if wantResume { req.setValue("bytes=\(already)-", forHTTPHeaderField: "Range") }
            if consecutiveClosed >= 2 { req.setValue("close", forHTTPHeaderField: "Connection") }

            do {
                // 用 dataTask(for:)（iOS 15+）接收本轮响应体，兼容性最好
                let (data, resp) = try await session.dataTask(for: req)
                let http = resp as? HTTPURLResponse
                let code = http?.statusCode ?? 0
                guard code == 200 || code == 206 else {
                    throw DownloadError.http(code)
                }
                if checkCancelled() { throw DownloadError.cancelled }
                // 只有请求了 Range 且服务端回 206 才算真续传，否则从头覆盖
                let actuallyResumed = wantResume && code == 206
                if wantResume && !actuallyResumed { progress(0) }

                let contentRange = http?.value(forHTTPHeaderField: "Content-Range")
                var roundTotal: Int64 = -1
                if code == 206, let cr = contentRange, let slash = cr.lastIndex(of: "/") {
                    let t = String(cr[cr.index(after: slash)...])
                    roundTotal = Int64(t) ?? -1
                } else if let len = http?.value(forHTTPHeaderField: "Content-Length"), let n = Int64(len) {
                    roundTotal = n
                }
                if roundTotal > 0 { totalBytes = roundTotal }

                // 写入临时文件：续传则追加，否则覆盖
                if actuallyResumed, FileManager.default.fileExists(atPath: tmp.path),
                   let handle = try? FileHandle(forWritingTo: tmp) {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try? handle.close()
                } else {
                    try data.write(to: tmp)
                }

                let size = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? NSNumber)?.int64Value ?? 0
                if totalBytes > 0 {
                    let pct = Int(size * 100 / totalBytes)
                    progress(min(100, max(0, pct)))
                }
                consecutiveClosed = 0

                if totalBytes > 0 && size >= totalBytes { return tmp }
                if totalBytes < 0 { return tmp }
                lastError = DownloadError.incomplete
            } catch {
                lastError = error
                let msg = "\(error)".lowercased()
                let isCut = msg.contains("closed") || msg.contains("eof") ||
                    msg.contains("unexpected") || msg.contains("connection")
                consecutiveClosed = isCut ? consecutiveClosed + 1 : 0
                if error is CancellationError || (error as? DownloadError) == .cancelled {
                    throw DownloadError.cancelled
                }
            }
            round += 1
        }
        throw lastError
    }
}
