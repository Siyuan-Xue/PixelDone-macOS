import PixelDoneDesignFoundation
import PixelDoneDomain
import SwiftUI

extension Color {
    init(pixelDoneHex value: String) {
        let hex = value.trimmingCharacters(
            in: CharacterSet.alphanumerics.inverted
        )
        var number: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&number)
        self.init(
            .sRGB,
            red: Double((number >> 16) & 0xff) / 255,
            green: Double((number >> 8) & 0xff) / 255,
            blue: Double(number & 0xff) / 255,
            opacity: 1
        )
    }

    static let pixelDoneIvory = Color(
        pixelDoneHex: PixelDoneDesignFoundation.light.background
    )
    static let pixelDoneSlate = Color(
        pixelDoneHex: PixelDoneDesignFoundation.dark.background
    )
    static let pixelDoneClay = Color(
        pixelDoneHex: PixelDoneDesignFoundation.semantic.accent
    )
    static let pixelDoneSuccess = Color(
        pixelDoneHex: PixelDoneDesignFoundation.semantic.success
    )
    static let pixelDoneError = Color(
        pixelDoneHex: PixelDoneDesignFoundation.semantic.error
    )
}

extension TodoPriority {
    var color: Color {
        switch self {
        case .low:
            Color(
                pixelDoneHex:
                    PixelDoneDesignFoundation.semantic.priorityLow
            )
        case .medium:
            Color(
                pixelDoneHex:
                    PixelDoneDesignFoundation.semantic.priorityMedium
            )
        case .high:
            Color(
                pixelDoneHex:
                    PixelDoneDesignFoundation.semantic.priorityHigh
            )
        case .xHigh:
            Color(
                pixelDoneHex:
                    PixelDoneDesignFoundation.semantic.priorityXHigh
            )
        }
    }

    var displayName: String {
        switch self {
        case .xHigh: "XHIGH"
        case .high: "HIGH"
        case .medium: "MEDIUM"
        case .low: "LOW"
        }
    }
}
