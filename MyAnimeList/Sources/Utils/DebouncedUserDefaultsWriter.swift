//
//  DebouncedUserDefaultsWriter.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/3.
//

import Combine
import Foundation

class DebouncedIntUserDefaultsWriter {
    private var cancellable: AnyCancellable?
    let subject: PassthroughSubject<Int?, Never>

    init(forKey key: String, delay: TimeInterval = 0.5) {
        let queue = DispatchQueue(
            label: "com.samuelhe.MyAnimeList.userdefaults.intwriter", qos: .background)

        self.subject = PassthroughSubject<Int?, Never>()
        self.cancellable =
            subject
            .debounce(for: .seconds(delay), scheduler: queue)
            .sink { value in
                UserDefaults.standard.set(value, forKey: key)
            }
    }

    func updateValue(_ value: Int?) { subject.send(value) }
}

class DebouncedStringUserDefaultsWriter {
    private var cancellable: AnyCancellable?
    let subject: PassthroughSubject<String?, Never>

    init(forKey key: String, delay: TimeInterval = 0.5) {
        let queue = DispatchQueue(
            label: "com.samuelhe.MyAnimeList.userdefaults.stringwriter", qos: .background)

        self.subject = PassthroughSubject<String?, Never>()
        self.cancellable =
            subject
            .debounce(for: .seconds(delay), scheduler: queue)
            .sink { value in
                UserDefaults.standard.set(value, forKey: key)
            }
    }

    func updateValue(_ value: String?) { subject.send(value) }
}
