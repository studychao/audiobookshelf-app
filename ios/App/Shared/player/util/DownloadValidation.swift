import Foundation

enum DownloadValidation {
    static func failure(statusCode: Int?, actualSize: Int64, expectedSize: Int64, isCover: Bool) -> String? {
        guard let statusCode, statusCode == 200 || statusCode == 206 else {
            return "服务器没有返回音频文件（HTTP \(statusCode ?? 0)）"
        }
        guard actualSize > 0 else { return "下载文件为空" }
        if !isCover && expectedSize > 0 && actualSize != expectedSize { return "下载文件不完整，需要继续下载" }
        return nil
    }

    static func shouldRetry(errorCode: Int?, statusCode: Int?, attempt: Int) -> Bool {
        guard attempt < 3 else { return false }
        if let statusCode, [401, 403, 404].contains(statusCode) { return false }
        if let errorCode, [NSURLErrorBadURL, NSURLErrorUnsupportedURL, NSURLErrorUserAuthenticationRequired].contains(errorCode) { return false }
        return true
    }
}
