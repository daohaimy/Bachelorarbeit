//
//  KontaktberichtSpeicherService.swift
//  KontaktberichtLogikKit
//
//  Created by Hai My Dao on 13.02.26.
//

import Foundation
import FoundationModels

protocol KontaktberichtSpeicherServiceProtocol {
    func save(_ bericht: Kontaktbericht, store: KontaktberichtStore)
}

final class KontaktberichtSpeicherService: KontaktberichtSpeicherServiceProtocol {
    func save(_ bericht: Kontaktbericht, store: KontaktberichtStore) {
        store.add(bericht)
    }
}

