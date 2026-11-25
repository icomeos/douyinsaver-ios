import Foundation

/// 平台识别与解析结果
enum Platform {
    case douyin, tiktok, bilibili
}

struct ResolvedVideo {
    let playUrl: String
    let title: String?
    let videoId: String?
    let allUrls: [String]
}

enum ParseError: LocalizedError {
    case invalidLink
    case noVideoId
    case noBvid
    case api(String)
    case noUrl

    var errorDescription: String? {
        switch self {
        case .invalidLink: return "未识别到有效链接（支持抖音 / B站 / TikTok）"
        case .noVideoId: return "未能解析出视频 ID"
        case .noBvid: return "未能从链接中解析出 B站 BV 号"
        case .api(let m): return m
        case .noUrl: return "未获取到播放地址"
        }
    }
}

/// 视频解析器：B站走官方 API，抖音/TikTok 走云端 API（api.douyin.wtf）
final class VideoParser {

    static let uaMobile = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    private static let uaDesktop = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 120
        return URLSession(configuration: cfg)
    }()

    private var cloudCookie: String?

    // MARK: - 平台 / 链接工具

    static func platform(of url: String) -> Platform {
        if url.contains("bilibili.com") || url.contains("b23.tv") || url.contains("bili2233.cn") {
            return .bilibili
        }
        if url.contains("tiktok.com") || url.contains("tiktokv.com") {
            return .tiktok
        }
        return .douyin
    }

    /// 从分享文本中提取 http(s) 链接（排除 tiktokcdn 直链，避免把下载地址当分享链接）
    static func extractURL(from text: String) -> String? {
        let pattern = "https?://[A-Za-z0-9._%~:/?#@!$&'()*+,;=\\-]+"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let s = ns.substring(with: m.range)
            let lower = s.lowercased()
            guard !(lower.contains("douyin.com") || lower.contains("iesdouyin.com") ||
                    lower.contains("bilibili.com") || lower.contains("b23.tv") ||
                    lower.contains("bili2233.cn") || lower.contains("tiktok.com")) else { continue }
            return s
        }
        // 若上面严格过滤没命中（例如纯直链文本），退而取第一个链接
        return matches.first.map { ns.substring(with: $0.range) }
    }

    static func referer(for url: String) -> String {
        let lower = url.lowercased()
        if lower.contains("bilivideo") || lower.contains("bilibili") { return "https://www.bilibili.com/" }
        if lower.contains("tiktok") { return "https://www.tiktok.com/" }
        return "https://www.douyin.com/"
    }

    // MARK: - 统一入口

    func resolve(_ shareUrl: String) async throws -> ResolvedVideo {
        switch Self.platform(of: shareUrl) {
        case .bilibili: return try await resolveBilibili(shareUrl)
        case .tiktok: return try await resolveViaCloud(shareUrl, platform: "tiktok")
        case .douyin: return try await resolveViaCloud(shareUrl, platform: "douyin")
        }
    }

    // MARK: - B站

    private func resolveBilibili(_ shareUrl: String) async throws -> ResolvedVideo {
        var finalUrl = shareUrl
        if shareUrl.contains("b23.tv") || shareUrl.contains("bili2233.cn") {
            if let u = URL(string: shareUrl) {
                var req = URLRequest(url: u)
                req.setValue(Self.uaMobile, forHTTPHeaderField: "User-Agent")
                if let (_, resp) = try? await session.data(for: req),
                   let final = resp.url?.absoluteString { finalUrl = final }
            }
        }
        let bv = Self.firstMatch(#"BV[0-9A-Za-z]{10}"#, in: finalUrl)
            ?? Self.firstMatch(#"BV[0-9A-Za-z]{10}"#, in: shareUrl)
        let aid = bv == nil ? Self.firstMatch(#"(?:av|aid=)(\\d+)"#, in: "\(shareUrl) \(finalUrl)") : nil
        guard bv != nil || aid != nil else { throw ParseError.noBvid }
        let idQuery = bv != nil ? "bvid=\(bv!)" : "aid=\(aid!)"

        let viewText = try await getText(
            "https://api.bilibili.com/x/web-interface/view?\(idQuery)",
            headers: ["Referer": "https://www.bilibili.com/"]
        )
        guard let view = dict(viewText), view["code"] as? Int == 0,
              let data = view["data"] as? [String: Any] else {
            throw ParseError.api("B站视频信息获取失败")
        }
        let title = data["title"] as? String
        var cid = (data["cid"] as? NSNumber)?.int64Value ?? 0
        if let pages = data["pages"] as? [[String: Any]], pages.count > 0 {
            let p = Self.firstMatch(#"[?&]p=(\\d+)"#, in: shareUrl).flatMap { Int($0) } ?? 1
            if p >= 1 && p <= pages.count {
                cid = (pages[p - 1]["cid"] as? NSNumber)?.int64Value ?? cid
            }
        }
        guard cid > 0 else { throw ParseError.api("未获取到 B站 CID") }

        let playUrl = "https://api.bilibili.com/x/player/playurl?\(idQuery)&cid=\(cid)" +
            "&qn=80&fnval=1&platform=web&high_quality=1"
        let playText = try await getText(playUrl, headers: ["Referer": "https://www.bilibili.com/"])
        guard let proot = dict(playText), proot["code"] as? Int == 0,
              let pdata = proot["data"] as? [String: Any] else {
            throw ParseError.api("B站取流失败")
        }
        var candidates: [String] = []
        if let durl = pdata["durl"] as? [[String: Any]], let first = durl.first {
            if let u = first["url"] as? String, !u.isEmpty { candidates.append(u) }
            if let backups = first["backup_url"] as? [String] {
                candidates.append(contentsOf: backups.filter { !$0.isEmpty })
            }
        }
        if candidates.isEmpty,
           let dash = pdata["dash"] as? [String: Any],
           let videos = dash["video"] as? [[String: Any]],
           let base = videos.first?["baseUrl"] as? String, !base.isEmpty {
            candidates.append(base)
        }
        guard let main = candidates.first else {
            throw ParseError.api("未获取到 B站播放地址（可能需要登录或为付费内容）")
        }
        return ResolvedVideo(playUrl: main, title: title, videoId: bv ?? "av\(aid!)",
                             allUrls: dedup(candidates))
    }

    // MARK: - 云端 API（抖音 / TikTok）

    private func resolveViaCloud(_ shareUrl: String, platform: String) async throws -> ResolvedVideo {
        let base = "https://api.douyin.wtf"
        var cookie = cloudCookie
        if cookie == nil {
            cookie = try await cloudLogin(base)
            cloudCookie = cookie
        }
        let enc = shareUrl.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? shareUrl
        let apiPath = platform == "tiktok" ? "tiktok" : "douyin"
        let apiUrl = platform == "tiktok"
            ? "\(base)/api/v1/tiktok/video?url=\(enc)&wait=25"
            : "\(base)/api/v1/douyin/video?url=\(enc)&wait=25&refresh=true"

        var text = try await getText(apiUrl, headers: ["Cookie": cookie!, "User-Agent": Self.uaMobile])
        var root = dict(text)
        if root?["success"] as? Bool != true {
            // cookie 可能失效：重新登录再试一次
            cloudCookie = nil
            let fresh = try await cloudLogin(base)
            cloudCookie = fresh
            text = try await getText(apiUrl, headers: ["Cookie": fresh, "User-Agent": Self.uaMobile])
            root = dict(text)
        }
        let success = root?["success"] as? Bool == true
        guard success, let r = root else {
            let err = (root?["error"] as? [String: Any])?["message"] as? String ?? "服务暂不可用"
            throw ParseError.api("\(platform == "tiktok" ? "TikTok" : "抖音") 云端解析失败：\(err)")
        }
        guard let data = r["data"] as? [String: Any],
              let media = data["media"] as? [String: Any],
              let video = media["video"] as? [String: Any] else {
            throw ParseError.api("云端返回中无视频数据（可能为图文笔记）")
        }
        var candidates: [String] = []
        if let u = video["url"] as? String, !u.isEmpty { candidates.append(u) }
        if let urls = video["urls"] as? [String] {
            candidates.append(contentsOf: urls.filter { !$0.isEmpty })
        }
        guard !candidates.isEmpty else { throw ParseError.api("云端未返回播放地址") }

        let ordered = dedup(candidates).sorted { a, b in
            score(a) < score(b)
        }
        // 用 Range 小请求验证首个可用地址；失败就用排序第一个（下载器还会轮换）
        var playUrl = ordered[0]
        for u in ordered {
            if await verify(u) { playUrl = u; break }
        }
        let contentId = data["content_id"] as? String ?? ""
        let title = data["title"] as? String
        let vid = contentId.isEmpty ? nil : contentId
        return ResolvedVideo(playUrl: playUrl, title: title, videoId: vid, allUrls: ordered)
    }

    private func score(_ url: String) -> Int {
        let l = url.lowercased()
        if l.contains("www.douyin.com") || l.contains("aweme.snssdk.com") { return 0 }
        if l.contains("experiment") { return 2 }
        return 1
    }

    private func verify(_ url: String) async -> Bool {
        guard let u = URL(string: url) else { return false }
        var req = URLRequest(url: u)
        req.setValue(Self.uaMobile, forHTTPHeaderField: "User-Agent")
        req.setValue(Self.referer(for: url), forHTTPHeaderField: "Referer")
        req.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        do {
            let (_, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return code == 200 || code == 206
        } catch { return false }
    }

    private func cloudLogin(_ base: String) async throws -> String {
        let demoText = try await getText("\(base)/api/v1/auth/demo", method: "POST", body: "{}",
                                         headers: ["Content-Type": "application/json"])
        guard let demoRoot = dict(demoText), let demo = demoRoot["data"] as? [String: Any],
              let username = demo["username"] as? String, let password = demo["password"] as? String else {
            throw ParseError.api("获取云端演示账号失败")
        }
        guard let url = URL(string: "\(base)/api/v1/auth/login") else { throw ParseError.api("云端地址无效") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(Self.uaMobile, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = "{\"username\":\"\(username)\",\"password\":\"\(password)\"}"
            .data(using: .utf8)
        let (_, resp) = try await session.data(for: req)
        let http = resp as? HTTPURLResponse
        let setCookie = http?.value(forHTTPHeaderField: "Set-Cookie") ?? ""
        guard let range = setCookie.range(of: "dtk_session=[^;]+", options: String.CompareOptions.regularExpression) else {
            throw ParseError.api("云端登录未返回会话（HTTP \(http?.statusCode ?? 0)）")
        }
        return String(setCookie[range])
    }

    // MARK: - HTTP 工具

    private func getText(_ urlString: String, method: String = "GET", body: String? = nil,
                         headers: [String: String]? = nil) async throws -> String {
        guard let url = URL(string: urlString) else { throw ParseError.api("请求地址无效") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(Self.uaDesktop, forHTTPHeaderField: "User-Agent")
        headers?.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let body = body { req.httpBody = body.data(using: .utf8) }
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ParseError.api("请求失败 HTTP \(code)") }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func dict(_ text: String) -> [String: Any]? {
        guard let d = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    private func dedup(_ arr: [String]) -> [String] {
        var seen = Set<String>()
        return arr.filter { seen.insert($0).inserted }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range)
    }
}
