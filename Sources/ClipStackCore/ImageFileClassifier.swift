import Foundation
import UniformTypeIdentifiers

/// 根据文件扩展名判断该文件是否属于图片。
public enum ImageFileClassifier {
    public static func isImageFile(at url: URL) -> Bool {
        let fileExtension = url.pathExtension
        guard !fileExtension.isEmpty,
              let type = UTType(filenameExtension: fileExtension) else {
            return false
        }
        return type.conforms(to: .image)
    }
}
