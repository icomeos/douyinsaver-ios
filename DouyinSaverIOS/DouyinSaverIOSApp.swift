import SwiftUI

@main
struct DouyinSaverIOSApp: App {
    @StateObject private var model = DownloadModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onOpenURL { url in
                    // 支持 douyinsaver://<链接> 与 Safari 分享
                    var s = url.absoluteString
                    if s.hasPrefix("douyinsaver://") {
                        s = String(s.dropFirst("douyinsaver://".count))
                        if let decoded = s.removingPercentEncoding { s = decoded }
                    }
                    model.input = s
                    model.startDownload()
                }
        }
    }
}
