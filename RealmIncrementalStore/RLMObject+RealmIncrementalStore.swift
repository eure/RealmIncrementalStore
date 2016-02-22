//
//  RLMObject+RealmIncrementalStore.swift
//  RealmIncrementalStore
//
//  Copyright © 2016 eureka, Inc., John Rommel Estropia
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
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
