//
//  IntelligenceModels.swift
//  StickiesPro
//

import FoundationModels

@Generable
struct ExtractedTerm {
    let term: String
    let weight: Double
    let positions: [Int]
    let localUsageHint: String
}

@Generable
struct NoteTerms {
    let terms: [ExtractedTerm]
}

@Generable
struct NoteCatalogAddress {
    let primary: Int
    let secondary: Int
    let tertiary: Int
    let label: String
    let rationale: String
}

@Generable
struct TermEtymology {
    let rootForms: [String]
    let summary: String
}
