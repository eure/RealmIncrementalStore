//
//  RealmIncrementalStore.swift
//  RealmIncrementalStore
//
//  Created by John Estropia on 2016/02/18.
//  Copyright © 2016年 John Estropia. All rights reserved.
//

import Foundation
import CoreData
import Realm
import Realm.Private


// MARK: - RealmIncrementalStore

@objc(RealmIncrementalStore)
public final class RealmIncrementalStore: NSIncrementalStore {
    
    public class var storeType: String {
        
        return NSStringFromClass(self)
    }
    
    
    // MARK: NSObject
    
    public override class func initialize() {
    
        NSPersistentStoreCoordinator.registerStoreClass(self, forStoreType:self.storeType)
    }
    
    
    // MARK: NSIncrementalStore
    
    public override func loadMetadata() throws {
        
        guard let coordinator = self.persistentStoreCoordinator else {
            
            throw RealmIncrementalStoreError.InvalidState
        }
        guard let fileURL = self.URL else {
            
            throw RealmIncrementalStoreError.PersistentStoreURLMissing
        }
        guard fileURL.fileURL else {
            
            throw RealmIncrementalStoreError.PersistentStoreURLInvalid
        }
        
        let model = coordinator.managedObjectModel
        let schema = self.createBackingClassesForModel(model)
        let rootRealm = try RLMRealm(
            path: fileURL.path!,
            key: nil,
            readOnly: false,
            inMemory: false,
            dynamic: false,
            schema: schema
        )
        
        let versionHashes: [String: NSData]
        let currentPrimaryKeyValue = _RealmIncrementalStoreMetadata.currentPrimaryKeyValue
        if let metadataObject = _RealmIncrementalStoreMetadata(inRealm: rootRealm, forPrimaryKey: currentPrimaryKeyValue) {
            
            guard let plist = try NSPropertyListSerialization.propertyListWithData(metadataObject._versionHashes, options: .Immutable, format: nil) as? [String: NSData] else {
                
                throw RealmIncrementalStoreError.PersistentStoreCorrupted
            }
            versionHashes = plist
        }
        else {
            
            versionHashes = model.entityVersionHashesByName
            let plistData = try! NSPropertyListSerialization.dataWithPropertyList(
                versionHashes,
                format: .BinaryFormat_v1_0,
                options: 0
            )
            
            rootRealm.beginWriteTransaction()
            let metadataObject = _RealmIncrementalStoreMetadata.createInRealm(
                rootRealm,
                withValue: [
                    _RealmIncrementalStoreMetadata.primaryKey()!: currentPrimaryKeyValue,
                    _RealmIncrementalStoreMetadata.versionHashesKey: plistData
                ]
            )
            rootRealm.addObject(metadataObject)
            try rootRealm.commitWriteTransaction()
        }
        
        
        let metadata: [String: AnyObject] = [
            NSStoreUUIDKey: NSUUID().UUIDString,
            NSStoreTypeKey: self.dynamicType.storeType,
            NSStoreModelVersionHashesKey: versionHashes
        ]
        
        self.rootRealm = rootRealm
        self.metadata = metadata
    }
    
    private func createBackingClassesForModel(model: NSManagedObjectModel) -> RLMSchema {
        
        let schema = RLMSchema()
        schema.objectSchema =
            [RLMObjectSchema(forObjectClass: _RealmIncrementalStoreMetadata.self)]
            + model.entities.map { $0.realmBackingType.objectSchema }
        return schema
    }
    
    private func executeFetchRequest(request: NSFetchRequest, inContext context: NSManagedObjectContext?) throws -> AnyObject {
        
        let entity = request.entity!
        
        let backingType = entity.realmBackingType
        let backingClass = backingType.backingClass
        let realm = self.rootRealm! // TODO: use per-context realm instance
        let results = backingClass.objectsInRealm(
            realm,
            withPredicate: request.predicate?.realmPredicate()
        )
        
        switch request.resultType {
            
        case NSFetchRequestResultType.ManagedObjectResultType:
            return results.flatMap { object -> AnyObject? in
                
                let resourceID = object[RLMObject.IncrementalStoreResourceIDProperty]!
                let objectID = self.newObjectIDForEntity(entity, referenceObject: resourceID)
                return context?.objectWithID(objectID)
            } // TODO: sort
            
        case NSFetchRequestResultType.ManagedObjectIDResultType:
            return results.flatMap { object -> AnyObject? in
                
                let resourceID = object[RLMObject.IncrementalStoreResourceIDProperty]!
                return self.newObjectIDForEntity(entity, referenceObject: resourceID)
            }
            
        case NSFetchRequestResultType.DictionaryResultType:
            // TODO:
            break
            
        case NSFetchRequestResultType.CountResultType:
            return results.count
            
        default:
            break
        }
        fatalError()
    }
    
    private func executeSaveRequest(request: NSSaveChangesRequest, inContext context: NSManagedObjectContext?) throws -> AnyObject {
        
        let realm = self.rootRealm! // TODO: use per-context realm instance
        realm.beginWriteTransaction()
        
        try request.insertedObjects?.forEach {
            
            let backingClass = $0.entity.realmBackingType.backingClass
            let realmObject = backingClass.createInRealm(
                realm,
                withValue: [
                    RLMObject.IncrementalStoreResourceIDProperty: self.referenceObjectForObjectID($0.objectID)
                ]
            )
            try realmObject.setValuesFromManagedObject($0)
            realm.addOrUpdateObject(realmObject)
        }
        
        try request.updatedObjects?.forEach {
            
            let backingClass = $0.entity.realmBackingType.backingClass
            let primaryKey = self.referenceObjectForObjectID($0.objectID)
            let realmObject = backingClass.init(
                inRealm: realm,
                forPrimaryKey: primaryKey
            )
            try realmObject?.setValuesFromManagedObject($0)
        }
        
        request.deletedObjects?.forEach {
            
            let backingClass = $0.entity.realmBackingType.backingClass
            let primaryKey = self.referenceObjectForObjectID($0.objectID)
            let realmObject = backingClass.init(
                inRealm: realm,
                forPrimaryKey: primaryKey
            )
            _ = realmObject.flatMap(realm.deleteObject)
        }
        
        try realm.commitWriteTransaction()
        
        return []
    }
    
    public override func executeRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext?) throws -> AnyObject {
        
        switch (request.requestType, request) {
            
        case (.FetchRequestType, let request as NSFetchRequest):
            return try self.executeFetchRequest(request, inContext: context)
            
        case (.SaveRequestType, let request as NSSaveChangesRequest):
            return try self.executeSaveRequest(request, inContext: context)
            
            // TODO:
        case (.BatchUpdateRequestType, _):
            fatalError()
        case (.BatchDeleteRequestType, _):
            fatalError()
            
        default:
            fatalError()
        }
    }
    
    public override func newValuesForObjectWithID(objectID: NSManagedObjectID, withContext context: NSManagedObjectContext) throws -> NSIncrementalStoreNode {
        
        let realm = self.rootRealm! // TODO: use per-context realm instance
        
        let backingType = objectID.entity.realmBackingType
        let backingClass = backingType.backingClass
        let primaryKey = self.referenceObjectForObjectID(objectID) as! String
        let realmObject = backingClass.init(
            inRealm: realm,
            forPrimaryKey: primaryKey
        )
        NSLog("%@", realmObject!)
        let keyValues = realmObject?.dictionaryWithValuesForKeys(backingType.objectSchema.properties.map { $0.getterName }) ?? [:]
        
        return NSIncrementalStoreNode(
            objectID: objectID,
            withValues: keyValues,
            version: UInt64(_RealmIncrementalStoreMetadata.currentPrimaryKeyValue)
        )
    }
    
    public override func newValueForRelationship(relationship: NSRelationshipDescription, forObjectWithID objectID: NSManagedObjectID, withContext context: NSManagedObjectContext?) throws -> AnyObject {
        
        // TODO:
        fatalError()
    }
    
    
    public override func obtainPermanentIDsForObjects(array: [NSManagedObject]) throws -> [NSManagedObjectID] {
        
        // TODO: cache?
        return array.map {
            
            guard $0.objectID.temporaryID else {
                
                return $0.objectID
            }
            
            return self.newObjectIDForEntity($0.entity, referenceObject: NSUUID().UUIDString)
        }
    }
    
//    public override func managedObjectContextDidRegisterObjectsWithIDs(objectIDs: [NSManagedObjectID]) {
//        
//        fatalError()
//    }
//    
//    public override func managedObjectContextDidUnregisterObjectsWithIDs(objectIDs: [NSManagedObjectID]) {
//        
//        fatalError()
//    }
    
    
    // MARK: Private
    
    private let objectIDCache = NSCache()
    private var rootRealm: RLMRealm?
}
