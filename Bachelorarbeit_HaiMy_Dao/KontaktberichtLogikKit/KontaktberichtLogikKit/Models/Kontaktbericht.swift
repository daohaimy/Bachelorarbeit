//
//  Kontaktbericht.swift
//  KontaktberichtLogikKit
//
//  Created by Hai My Dao on 13.02.26.
//

import Foundation
import Combine


public enum Gespraechstyp: String, Codable, CaseIterable, Sendable {
    case messegespraech, kundenbesuch, email, chance, telefon
    
    public var displayName: String {
        switch self {
        case .messegespraech: return "Messegespräch"
        case .kundenbesuch: return "Kundenbesuch"
        case .email: return "E-Mail"
        case .chance: return "Chance"
        case .telefon: return "Telefon"
        }
    }
}

public struct Kontaktbericht: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var ansprechpartner: String
    public var date: Date
    public var typ: Gespraechstyp
    public var inhalt: String

    public init(id: UUID = UUID(),
         ansprechpartner: String,
         date: Date = .now,
         typ: Gespraechstyp,
         inhalt: String) {
        self.id = id
        self.ansprechpartner = ansprechpartner
        self.date = date
        self.typ = typ
        self.inhalt = inhalt
    }
}
