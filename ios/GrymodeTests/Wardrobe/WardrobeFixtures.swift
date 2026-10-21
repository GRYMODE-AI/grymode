import Foundation
import UIKit
import XCTest

@testable import Grymode

enum WardrobeFixtures {
    static let mediaID = UUID(uuidString: "11111111-1111-4111-8111-111111111111") ?? UUID()
    static let jobID = UUID(uuidString: "22222222-2222-4222-8222-222222222222") ?? UUID()
    static let garmentID = UUID(uuidString: "33333333-3333-4333-8333-333333333333") ?? UUID()
    static let uploadURL = URL(string: "https://storage.example.test/sign/upload") ?? URL(fileURLWithPath: "/")

    static func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    static func uploadSlot(
        mediaId: UUID = mediaID,
        jobId: UUID? = jobID,
        uploadUrl: URL = uploadURL
    ) -> Data {
        var payload: [String: Any] = [
            "media_id": mediaId.uuidString.lowercased(),
            "object_key": "wardrobe/\(mediaId.uuidString.lowercased())/original.jpg",
            "upload_url": uploadUrl.absoluteString,
            "expires_in_seconds": 600,
        ]
        if let jobId {
            payload["job_id"] = jobId.uuidString.lowercased()
        } else {
            payload["job_id"] = NSNull()
        }
        return json(payload)
    }

    static func completeUpload(
        mediaId: UUID = mediaID,
        jobId: UUID = jobID,
        status: String = "uploaded"
    ) -> Data {
        json([
            "media_id": mediaId.uuidString.lowercased(),
            "processing_status": status,
            "job_id": jobId.uuidString.lowercased(),
        ])
    }

    static func garment(
        id: UUID = garmentID,
        category: String = "uncategorised",
        confirmed: Bool = false,
        imageUrl: String = "https://storage.example.test/sign/read"
    ) -> [String: Any] {
        [
            "id": id.uuidString.lowercased(),
            "media_id": mediaID.uuidString.lowercased(),
            "category": category,
            "subcategory": NSNull(),
            "primary_color": NSNull(),
            "secondary_colors": [],
            "pattern": NSNull(),
            "material": NSNull(),
            "silhouette": NSNull(),
            "formality": NSNull(),
            "season_tags": [],
            "style_tags": [],
            "image_url": imageUrl,
            "confidence": NSNull(),
            "user_confirmed": confirmed,
            "created_at": "2026-10-11T10:00:00.000001Z",
            "updated_at": "2026-10-11T10:00:00Z",
        ]
    }

    static func job(
        id: UUID = jobID,
        mediaId: UUID = mediaID,
        status: String = "succeeded"
    ) -> [String: Any] {
        [
            "id": id.uuidString.lowercased(),
            "media_id": mediaId.uuidString.lowercased(),
            "job_type": "garment_extraction",
            "status": status,
            "progress_stage": NSNull(),
            "error_code": NSNull(),
            "created_at": "2026-10-11T10:00:00.000001Z",
            "completed_at": status == "succeeded" || status == "failed" ? "2026-10-11T10:00:01Z" : NSNull(),
        ]
    }

    static func summary(
        garments: [[String: Any]] = [],
        jobs: [[String: Any]] = [],
        unconfirmed: Int? = nil,
        confirmed: Int? = nil
    ) -> Data {
        let confirmedCount = confirmed ?? garments.filter { ($0["user_confirmed"] as? Bool) == true }.count
        let unconfirmedCount = unconfirmed ?? (garments.count - confirmedCount)
        return json([
            "media": [],
            "garments": garments,
            "jobs": jobs,
            "unconfirmed_count": unconfirmedCount,
            "confirmed_count": confirmedCount,
        ])
    }

    static func tinyJPEG(file: StaticString = #filePath, line: UInt = #line) throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12))
        let image = renderer.image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9), file: file, line: line)
    }
}
