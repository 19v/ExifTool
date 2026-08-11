//
//  Models.swift
//  ExifTool
//
//  Shared metadata models used by the Exif parser.
//

import CoreLocation
import Foundation

struct PhotoMetadata {
    let sections: [MetadataSection]
    let coordinate: CLLocationCoordinate2D?
}

struct MetadataSection: Identifiable {
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

struct MetadataItemGroup: Identifiable {
    let id: String
    let title: String
    let items: [MetadataItem]
}

struct MetadataItem: Identifiable {
    let id: String
    let key: String
    let value: String
}
