//
//  main.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import Foundation

// `ScreenSaverDemo --capture <folder>` writes still frames of every layout instead of opening the app.
let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--capture"), arguments.indices.contains(flag + 1) {
    try MainActor.assumeIsolated {
        try DemoCapture.run(output: URL(filePath: arguments[flag + 1], directoryHint: .isDirectory))
    }
} else {
    DemoApp.main()
}
