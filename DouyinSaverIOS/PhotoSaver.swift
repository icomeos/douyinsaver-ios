import Foundation
import Photos

/// 保存视频到系统相册
final class PhotoSaver {

    enum SaveError: LocalizedError {
        case denied
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .denied: return "没有相册写入权限，请在 设置→隐私→照片 中开启"
            case .failed(let m): return "保存失败：\(m)"
            }
        }
    }

    /// 请求相册写入权限（在 Info.plist 中已声明 NSPhotoLibraryAddUsageDescription）
    static func requestPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .authorized || status == .limited { return true }
        if status == .notDetermined {
            let result = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return result == .authorized || result == .limited
        }
        return false
    }

    /// 把本地视频文件保存到相册
    func save(videoAt url: URL) async throws {
        guard await Self.requestPermission() else { throw SaveError.denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        } catch {
            throw SaveError.failed(error.localizedDescription)
        }
    }
}
