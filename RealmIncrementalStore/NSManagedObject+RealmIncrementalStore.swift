//
//  NSManagedObject+RealmIncrementalStore.swift
//  RealmIncrementalStore
//
//  Created by John Estropia on 2016/02/22.
//  Copyright © 2016年 John Estropia. All rights reserved.
//

import CoreData
import Foundation
import Realm

internal extension NSManagedObject {
    
    func realmObject() -> RLMObject? {
        
        let objectID = self.objectID
        guard case (let store as RealmIncrementalStore) = objectID.persistentStore else {
            
            return nil
        }
        
        let primaryKey = store.referenceObjectForObjectID(objectID)
        let backingClass = objectID.entity.realmBackingType.backingClass
        return backingClass.init(forPrimaryKey: primaryKey)
    }
}
