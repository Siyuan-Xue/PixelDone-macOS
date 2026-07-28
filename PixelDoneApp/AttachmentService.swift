import CryptoKit
import Foundation
import ImageIO
import PixelDoneSyncContract
import UniformTypeIdentifiers

nonisolated struct NormalizedAttachment: Equatable, Sendable {
    var data: Data
    var contentType: String
    var contentSHA256: String
    var byteSize: Int64
}

enum AttachmentError: LocalizedError {
    case invalidImage
    case normalizationFailed
    case tooLarge
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .invalidImage: "The selected file is not a supported image."
        case .normalizationFailed: "PixelDone could not normalize the image."
        case .tooLarge: "The normalized image exceeds the 10 MiB limit."
        case .checksumMismatch:
            "The downloaded image did not match its content hash."
        }
    }
}

actor PixelDoneAttachmentService {
    func normalize(_ input: Data) throws -> NormalizedAttachment {
        guard let source = CGImageSourceCreateWithData(input as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 4_096,
                ] as CFDictionary
              ) else {
            throw AttachmentError.invalidImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw AttachmentError.normalizationFailed
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw AttachmentError.normalizationFailed
        }
        let data = output as Data
        guard data.count
                <= PixelDoneSyncContractVersion.attachmentMaximumBytes else {
            throw AttachmentError.tooLarge
        }
        return NormalizedAttachment(
            data: data,
            contentType: UTType.jpeg.preferredMIMEType ?? "image/jpeg",
            contentSHA256: SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined(),
            byteSize: Int64(data.count)
        )
    }

    func storeLocally(
        _ attachment: NormalizedAttachment,
        attachmentID: String
    ) throws -> URL {
        let url = try localURL(attachmentID: attachmentID)
        try attachment.data.write(to: url, options: .atomic)
        return url
    }

    func loadLocalData(attachmentID: String) throws -> Data {
        try Data(contentsOf: localURL(attachmentID: attachmentID))
    }

    func storeDownloaded(
        _ data: Data,
        attachmentID: String,
        expectedSHA256: String
    ) throws {
        guard data.count
                <= PixelDoneSyncContractVersion.attachmentMaximumBytes else {
            throw AttachmentError.tooLarge
        }
        let actualHash = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualHash == expectedSHA256 else {
            throw AttachmentError.checksumMismatch
        }
        try data.write(
            to: localURL(attachmentID: attachmentID),
            options: .atomic
        )
    }

    private func localURL(attachmentID: String) throws -> URL {
        let fileManager = FileManager.default
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appending(path: "PixelDone", directoryHint: .isDirectory)
            .appending(path: "Attachments", directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appending(path: "\(attachmentID).jpg")
    }
}
