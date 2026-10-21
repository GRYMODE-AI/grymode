import Foundation
import UIKit

/// Prepares wardrobe photos as JPEGs within a practical upload size.
enum WardrobeImageEncoder {
    static let contentType = "image/jpeg"
    /// Soft client target; the API accepts up to 12 MB.
    static let targetMaxBytes = 2 * 1024 * 1024
    private static let minimumDimension: CGFloat = 720

    static func jpegData(from source: Data, maxBytes: Int = targetMaxBytes) throws(AppError) -> Data {
        guard let image = UIImage(data: source) else {
            throw .api(
                status: 422,
                code: "invalid_image",
                message: "That photo couldn't be read. Try another image.",
                requestID: nil,
                retryable: false
            )
        }
        return try jpegData(from: image, maxBytes: maxBytes)
    }

    static func jpegData(from image: UIImage, maxBytes: Int = targetMaxBytes) throws(AppError) -> Data {
        var working = image
        var quality: CGFloat = 0.88
        for _ in 0..<8 {
            if let data = working.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
            quality -= 0.1
            if quality < 0.35 {
                working = downscale(working)
                quality = 0.8
            }
        }
        if let data = working.jpegData(compressionQuality: 0.35), data.count <= maxBytes {
            return data
        }
        throw .api(
            status: 422,
            code: "image_too_large",
            message: "That photo is still too large after compression. Try a smaller image.",
            requestID: nil,
            retryable: false
        )
    }

    private static func downscale(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > minimumDimension else { return image }
        let scale = 0.7
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
