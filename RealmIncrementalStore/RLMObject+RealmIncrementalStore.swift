//
//  RLMObject+RealmIncrementalStore.swift
//  RealmIncrementalStore
//
//  Created by John Estropia on 2016/02/19.
//  Copyright © 2016年 John Estropia. All rights reserved.
//

import CoreData
import Foundation
import Realm

internal extension RLMObject {
    
    @nonobjc internal static let IncrementalStoreResourceIDProperty = "_RIS_PK"
    @nonobjc internal static let IncrementalStoreResourceIDSetter = "set_RIS_PK:"
    @nonobjc internal static let IncrementalStoreResourceIDIVar = "__RIS_PK"
    
    @nonobjc internal static func IncrementalStoreBackingClassNameForEntity(entity: NSEntityDescription) -> NSString {
        
        return "_RIS_\(_RealmIncrementalStoreMetadata.currentPrimaryKeyValue)_\(entity.name!)"
    }
    
    @nonobjc internal func setValuesFromManagedObject(managedObject: NSManagedObject) throws {
        
        let entity = managedObject.entity
        entity.attributesByName.keys
            .filter { $0 != RLMObject.IncrementalStoreResourceIDProperty }
            .forEach { self[$0] = managedObject.valueForKey($0) }
        // TODO: external binary storage(?)
        
        entity.relationshipsByName.forEach { (relationshipName, relationshipDescription) in
            
            let value = managedObject.valueForKey(relationshipName) as? NSManagedObject
            if relationshipDescription.toMany {
                
                // TODO:
            }
            else {
                
                if let value = value {
                    
                    // TODO:
                }
                else {
                    
                    self[relationshipName] = nil
                }
            }
        }
    }
}
