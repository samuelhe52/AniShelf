//
//  UserEntryInfo+Pasteboard.swift
//  MyAnimeList
//
//  Created by Samuel He on 7/15/25.
//

import DataProvider
import Foundation
import UniformTypeIdentifiers

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

extension UserEntryInfo {
    static let pasteboardUTType = UTType("com.samuelhe.myanimelist.userentryinfo")!

    /// Copies the UserEntryInfo to the general pasteboard using both a custom UTI and plain text.
    func copyToPasteboard() {
        guard let data = try? JSONEncoder().encode(self),
            let jsonString = String(data: data, encoding: .utf8)
        else { return }
        #if os(macOS)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(jsonString, forType: .init(Self.pasteboardUTType.identifier))
            pasteboard.setString(description, forType: .string)
        #else
            UIPasteboard.general.items = [
                [
                    Self.pasteboardUTType.identifier: jsonString,
                    UTType.plainText.identifier: description
                ]
            ]
        #endif
    }

    /// Attempts to load UserEntryInfo from the general pasteboard.
    static func fromPasteboard() -> UserEntryInfo? {
        #if os(macOS)
            guard let jsonString = NSPasteboard.general.string(forType: .init(pasteboardUTType.identifier)),
                let data = jsonString.data(using: .utf8)
            else { return nil }
            return try? JSONDecoder().decode(UserEntryInfo.self, from: data)
        #else
            let pasteboard = UIPasteboard.general
            for item in pasteboard.items {
                if let jsonString = item[Self.pasteboardUTType.identifier] as? String,
                    let data = jsonString.data(using: .utf8),
                    let decoded = try? JSONDecoder().decode(UserEntryInfo.self, from: data)
                {
                    return decoded
                }
            }
            return nil
        #endif
    }
}
