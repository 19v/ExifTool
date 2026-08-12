//
//  Models.swift
//  ExifTool
//
//  Shared metadata models used by the Exif parser.
//

import CoreLocation
import Foundation

nonisolated struct PhotoMetadata: Sendable {
    let sections: [MetadataSection]
    let coordinate: CLLocationCoordinate2D?
}

nonisolated struct MetadataSection: Identifiable, Sendable {
    let id: String
    let title: String
    let items: [MetadataItem]
    let itemGroups: [MetadataItemGroup]

    nonisolated init(id: String, title: String, items: [MetadataItem], itemGroups: [MetadataItemGroup] = []) {
        self.id = id
        self.title = title
        self.items = items
        self.itemGroups = itemGroups
    }
}

nonisolated struct MetadataItemGroup: Identifiable, Sendable {
    let id: String
    let title: String
    let items: [MetadataItem]
}

nonisolated struct MetadataItem: Identifiable, Sendable {
    let id: String
    let key: String
    let value: String
}
