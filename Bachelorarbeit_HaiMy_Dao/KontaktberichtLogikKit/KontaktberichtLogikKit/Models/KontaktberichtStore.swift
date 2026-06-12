//
//  KontaktberichtStore.swift
//  KontaktberichtLogikKit
//
//  Created by Hai My Dao on 13.02.26.
//

import Foundation
import Combine

final class KontaktberichtStore {
    @Published private(set) var items: [Kontaktbericht] = []
    private let url: URL

    init(filename: String = "kontaktberichte.json") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.url = dir.appendingPathComponent(filename)
        load()
    }

    func add(_ item: Kontaktbericht) {
        items.insert(item, at: 0)
        save()
    }

    func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            items.remove(at: index)
        }
        save()
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("Save error:", error)
        }
    }

    func load() {
        do {
            let data = try Data(contentsOf: url)
            items = try JSONDecoder().decode([Kontaktbericht].self, from: data)
        } catch {
            items = []
        }
    }
}

