import Foundation
import SwiftUI
import UIKit

/// 取消标志（线程安全）
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set(_ v: Bool) { lock.lock(); value = v; lock.unlock() }
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
}

final class DownloadModel: ObservableObject {
    @Published var input: String = ""
    @Published var status: String = "复制视频分享链接，点「下载」即可"
    @Published var progress: Int = 0
    @Published var isBusy: Bool = false
    @Published var savedCount: Int = 0

    private let cancelFlag = CancelFlag()

    private func ui(_ block: @escaping () -> Void) {
        DispatchQueue.main.async { block() }
    }

    func startDownload() {
        guard !isBusy else { return }
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let shareUrl = VideoParser.extractURL(from: raw) else {
            status = ParseError.invalidLink.localizedDescription
            return
        }
        isBusy = true
        cancelFlag.set(false)
        progress = 0
        status = "正在解析视频地址…"

        let parser = VideoParser()
        let downloader = Downloader()
        let photoSaver = PhotoSaver()
        let flag = cancelFlag

        Task.detached(priority: .userInitiated) {
            do {
                let resolved = try await parser.resolve(shareUrl)
                self.ui { self.status = "解析成功，开始下载…" }

                var urls = [resolved.playUrl] + resolved.allUrls
                urls = Array(Set(urls.filter { !$0.isEmpty }))
                let ref = VideoParser.referer(for: resolved.playUrl)

                let file = try await downloader.download(
                    urls: urls,
                    referer: ref,
                    progress: { p in self.ui { self.progress = p } },
                    checkCancelled: { flag.get() }
                )
                if flag.get() { throw DownloadError.cancelled }
                try await photoSaver.save(videoAt: file)

                let name = resolved.title ?? "video"
                self.ui {
                    self.savedCount += 1
                    self.status = "✅ 已保存到相册：\(name)\n（第 \(self.savedCount) 个视频）"
                    self.progress = 100
                    self.isBusy = false
                }
            } catch {
                let cancelled = (error as? DownloadError) == .cancelled
                let msg = cancelled ? "已取消下载" : "失败：\(error.localizedDescription)\n可稍后重试"
                self.ui {
                    self.isBusy = false
                    self.status = msg
                }
            }
        }
    }

    func cancel() {
        cancelFlag.set(true)
        status = "正在取消…"
    }

    /// 从剪贴板读取链接（iOS 16+ 首次读会弹系统粘贴提示）
    func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            status = "剪贴板为空或不是文本"
            return
        }
        input = text
        if let url = VideoParser.extractURL(from: text) {
            status = "已识别剪贴板链接：\(url)\n点「下载」开始"
        } else {
            status = "剪贴板中没有识别到视频链接"
        }
    }
}
