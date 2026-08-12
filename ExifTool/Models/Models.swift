//
//  Models.swift
//  ExifTool
//
//  Shared metadata models used by the Exif parser.
//

import CoreLocation
import Foundation

nonisolated struct PhotoMetadata: Equatable, Sendable {
    let sections: [MetadataSection]
    let coordinate: CLLocationCoordinate2D?

    static func == (lhs: PhotoMetadata, rhs: PhotoMetadata) -> Bool {
        lhs.sections == rhs.sections &&
        lhs.coordinate?.latitude == rhs.coordinate?.latitude &&
        lhs.coordinate?.longitude == rhs.coordinate?.longitude
    }
}

nonisolated struct MetadataSection: Equatable, Identifiable, Sendable {
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

nonisolated struct MetadataItemGroup: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let items: [MetadataItem]
}

nonisolated struct MetadataItem: Equatable, Identifiable, Sendable {
    let id: String
    let key: String
    let value: String
}
