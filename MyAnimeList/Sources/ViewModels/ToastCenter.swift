//
//  ToastCenter.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/4/26.
//

import AlertToast
import Foundation
import SwiftUI

/// A MainActor-bound singleton that stores properties used to display toasts globally on screen.
///
/// It is recommended to use this class when toasts need to be triggered from non-UI components or a non-main-thread environment.
@Observable @MainActor
class ToastCenter {
    static var global: ToastCenter = .init()

    var copied: Bool = false
    var pasted: Bool = false
    var favorited: Bool = false
    var unFavorited: Bool = false
    var regularCompleted: Bool = false
    var regularFailed: Bool = false

    var completionState: CompletedWithMessage? = nil
    var loadingMessage: LoadingMessage? = nil
    var progressState: ProgressWithMessage? = nil

    struct LoadingMessage: Identifiable, Equatable {
        var id = UUID()
        var messageResource: LocalizedStringResource

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.messageResource == rhs.messageResource
        }

        static func message(_ messageResource: LocalizedStringResource) -> Self {
            .init(messageResource: messageResource)
        }

        static func message(message: String) -> Self {
            .init(messageResource: LocalizedStringResource(stringLiteral: message))
        }
    }

    struct ProgressWithMessage: Identifiable, Equatable {
        var id = UUID()
        var current: Int
        var total: Int
        var messageResource: LocalizedStringResource

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.current == rhs.current && lhs.total == rhs.total && lhs.messageResource == rhs.messageResource
        }

        static func progress(
            current: Int, total: Int, messageResource: LocalizedStringResource
        ) -> Self {
            .init(current: current, total: total, messageResource: messageResource)
        }

        static func progress(current: Int, total: Int, message: String) -> Self {
            .init(
                current: current,
                total: total,
                messageResource: LocalizedStringResource(stringLiteral: message))
        }
    }

    struct CompletedWithMessage: Identifiable, Equatable {
        var id = UUID()
        var state: State
        var messageResource: LocalizedStringResource

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.state == rhs.state && lhs.messageResource == rhs.messageResource
        }

        enum State {
            case completed, failed, partialComplete
        }

        static func completed(_ messageResource: LocalizedStringResource) -> Self {
            .init(state: .completed, messageResource: messageResource)
        }

        static func failed(_ messageResource: LocalizedStringResource) -> Self {
            .init(state: .failed, messageResource: messageResource)
        }

        static func partialComplete(_ messageResource: LocalizedStringResource) -> Self {
            .init(state: .partialComplete, messageResource: messageResource)
        }

        static func completed(message: String) -> Self {
            .init(
                state: .completed, messageResource: LocalizedStringResource(stringLiteral: message))
        }

        static func failed(message: String) -> Self {
            .init(state: .failed, messageResource: LocalizedStringResource(stringLiteral: message))
        }

        static func partialComplete(message: String) -> Self {
            .init(
                state: .partialComplete,
                messageResource: LocalizedStringResource(stringLiteral: message))
        }
    }
}
