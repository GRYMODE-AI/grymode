import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Loads image bytes from `PhotosPickerItem` without depending on UIImage in the picker path.
struct PhotoDataTransfer: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PhotoDataTransfer(data: data)
        }
        DataRepresentation(importedContentType: .jpeg) { data in
            PhotoDataTransfer(data: data)
        }
        DataRepresentation(importedContentType: .png) { data in
            PhotoDataTransfer(data: data)
        }
        DataRepresentation(importedContentType: .webP) { data in
            PhotoDataTransfer(data: data)
        }
        DataRepresentation(importedContentType: .heic) { data in
            PhotoDataTransfer(data: data)
        }
        DataRepresentation(importedContentType: .heif) { data in
            PhotoDataTransfer(data: data)
        }
    }
}
