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


// MARK: - RLMObject

internal extension RLMObject {
    
    @nonobjc internal static let RISResourceIDProperty = "_RIS_PK"
    @nonobjc internal static let RISResourceIDSetter = "set_RIS_PK:"
    @nonobjc internal static let RISResourceIDIVar = "__RIS_PK"
    
    @nonobjc internal static let RISVersionProperty = "_RIS_VER"
    @nonobjc internal static let RISVersionSetter = "set_RIS_VER:"
    @nonobjc internal static let RISVersionIVar = "__RIS_VER"
    
    @nonobjc internal static func RISBackingClassNameForEntity(entity: NSEntityDescription) -> NSString {
        
        return "_RIS_\(RealmIncrementalStoreMetadata.currentSDKVersion)_\(entity.name!)"
    }
    
    internal static dynamic func createBackingObjectInRealm(realm: RLMRealm, referenceObject: AnyObject) -> RLMObject {
        
        return self.createInRealm(
            realm,
            withValue: [
                RLMObject.RISResourceIDProperty: referenceObject
            ]
        )
    }
    
    @nonobjc internal var realmResourceID: String {
        
        return self[RLMObject.RISResourceIDProperty] as! String
    }
    
    @nonobjc internal var realmObjectVersion: UInt64 {
        
        get {
            
            return (self[RLMObject.RISVersionProperty] as? NSNumber)?.unsignedLongLongValue ?? 0
        }
        set {
            
            self[RLMObject.RISVersionProperty] = NSNumber(unsignedLongLong: newValue)
        }
    }
    
    @nonobjc internal func setValuesFromManagedObject(managedObject: NSManagedObject) throws {
        
        let entity = managedObject.entity
        entity.attributesByName.keys
            .filter {
                
                return $0 != RLMObject.RISResourceIDProperty
                    && $0 != RLMObject.RISVersionProperty
            }
            .forEach { self[$0] = managedObject.valueForKey($0) }
        // TODO: external binary storage(?)
        
        entity.relationshipsByName.forEach { (relationshipName, relationshipDescription) in
            
            let value = managedObject.valueForKey(relationshipName) as? NSManagedObject
            if relationshipDescription.toMany {
                
                // TODO:
            }
            else {
                
                if let _ = value {
                    
                    // TODO:
                }
                else {
                    
                    self[relationshipName] = nil
                }
            }
        }
        
        self.realmObjectVersion += 1
    }
}
