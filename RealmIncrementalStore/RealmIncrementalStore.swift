//
//  RealmIncrementalStore.swift
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
    
    internal private(set) var rootRealm: RLMRealm!
    
    
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
        let storeIdentifier: String
        
        let sdkVersion = RealmIncrementalStoreMetadata.currentSDKVersion
        if let metadataObject = RealmIncrementalStoreMetadata(inRealm: rootRealm, forPrimaryKey: sdkVersion) {
            
            guard let plist = try NSPropertyListSerialization.propertyListWithData(metadataObject.versionHashes, options: .Immutable, format: nil) as? [String: NSData] else {
                
                throw RealmIncrementalStoreError.PersistentStoreCorrupted
            }
            versionHashes = plist
            storeIdentifier = metadataObject.storeIdentifier
        }
        else {
            
            versionHashes = model.entityVersionHashesByName
            storeIdentifier = RealmIncrementalStore.identifierForNewStoreAtURL(fileURL) as! String
            
            let plistData = try! NSPropertyListSerialization.dataWithPropertyList(
                versionHashes,
                format: .BinaryFormat_v1_0,
                options: 0
            )
            
            rootRealm.beginWriteTransaction()
            let metadataObject = RealmIncrementalStoreMetadata.createInRealm(
                rootRealm,
                withValue: [
                    RealmIncrementalStoreMetadata.primaryKey()!: sdkVersion
                ]
            )
            metadataObject.storeIdentifier = storeIdentifier
            metadataObject.versionHashes = plistData
            rootRealm.addOrUpdateObject(metadataObject)
            try rootRealm.commitWriteTransaction()
        }
        
        let metadata: [String: AnyObject] = [
            NSStoreUUIDKey: storeIdentifier,
            NSStoreTypeKey: RealmIncrementalStore.storeType,
            NSStoreModelVersionHashesKey: versionHashes
        ]
        
        self.rootRealm = rootRealm
        self.metadata = metadata
    }
    
    public override func executeRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext?) throws -> AnyObject {
        
        switch (request.requestType, request) {
            
        case (.FetchRequestType, let request as NSFetchRequest):
            return try self.executeFetchRequest(request, inContext: context)
            
        case (.SaveRequestType, let request as NSSaveChangesRequest):
            return try self.executeSaveRequest(request, inContext: context)
            
            // TODO:
//        case (.BatchUpdateRequestType, _):
//            fatalError()
//        case (.BatchDeleteRequestType, _):
//            fatalError()
            
        default:
            throw RealmIncrementalStoreError.StoreRequestUnsupported
        }
    }
    
    public override func newValuesForObjectWithID(objectID: NSManagedObjectID, withContext context: NSManagedObjectContext) throws -> NSIncrementalStoreNode {
        
        let realm = self.rootRealm!
        
        let backingClass = objectID.entity.realmBackingClass
        let primaryKey = self.referenceObjectForObjectID(objectID) as! String
        
        guard let realmObject = backingClass.init(inRealm: realm, forPrimaryKey: primaryKey) else {
            
            throw RealmIncrementalStoreError.ObjectNotFound
        }
        
        let keyValues = realmObject.dictionaryWithValuesForKeys(
            objectID.entity.realmObjectSchema.properties
                .filter { $0.objectClassName == nil && realmObject[$0.name] != nil }
                .map { $0.getterName }
        )
        
        return NSIncrementalStoreNode(
            objectID: objectID,
            withValues: keyValues,
            version: realmObject.realmObjectVersion
        )
    }
    
    public override func newValueForRelationship(relationship: NSRelationshipDescription, forObjectWithID objectID: NSManagedObjectID, withContext context: NSManagedObjectContext?) throws -> AnyObject {
        
        guard let realmObject = objectID.realmObject(),
            let destinationEntity = relationship.destinationEntity else {
            
                return NSNull()
        }
        
        if relationship.toMany {
            
            if let relatedObjects = realmObject[relationship.name] as? RLMArray {
                
                return relatedObjects.flatMap {
                    
                    return self.newObjectIDForEntity(
                        destinationEntity,
                        referenceObject: $0.realmResourceID
                    )
                }
            }
        }
        else {
            
            if let relatedObject = realmObject[relationship.name] as? RLMObject {
                
                return self.newObjectIDForEntity(
                    destinationEntity,
                    referenceObject: relatedObject.realmResourceID
                )
            }
        }
        return NSNull()
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
    
    private func createBackingClassesForModel(model: NSManagedObjectModel) -> RLMSchema {
        
        let metadataSchema = [RLMObjectSchema(forObjectClass: RealmIncrementalStoreMetadata.self)]
        let entitiesSchema = model.entities.loadObjectSchemas()
        
        let schema = RLMSchema()
        schema.objectSchema = metadataSchema + entitiesSchema
        return schema
    }
    
    private func executeFetchRequest(request: NSFetchRequest, inContext context: NSManagedObjectContext?) throws -> AnyObject {
        
        let entity = request.entity!
        let backingClass = entity.realmBackingClass
        let realm = self.rootRealm!
        var results = backingClass.objectsInRealm(
            realm,
            withPredicate: request.predicate?.realmPredicate()
        )
        if let sortDescriptors = request.sortDescriptors {
            
            results = results.sortedResultsUsingDescriptors(
                sortDescriptors.map {
                    RLMSortDescriptor(property: $0.key!, ascending: $0.ascending)
                }
            )
        }
        
        switch request.resultType {
            
        case NSFetchRequestResultType.ManagedObjectResultType:
            return results.flatMap { object -> AnyObject? in
                
                let resourceID = object.realmResourceID
                let objectID = self.newObjectIDForEntity(entity, referenceObject: resourceID)
                return context?.objectWithID(objectID)
            }
            
        case NSFetchRequestResultType.ManagedObjectIDResultType:
            return results.flatMap { object -> AnyObject? in
                
                let resourceID = object.realmResourceID
                return self.newObjectIDForEntity(entity, referenceObject: resourceID)
            }
            
        case NSFetchRequestResultType.DictionaryResultType:
            return results.flatMap { object -> AnyObject? in
                
                let propertiesToFetch = request.propertiesToFetch ?? []
                let keyValues = object.dictionaryWithValuesForKeys(
                    propertiesToFetch.flatMap {
                        
                        switch $0 {
                            
                        case let string as String:
                            return string
                        case let property as NSPropertyDescription:
                            return property.name
                        default:
                            return nil
                        }
                    }
                )
                return keyValues
            }
            
        case NSFetchRequestResultType.CountResultType:
            return results.count
            
        default:
            fatalError()
        }
    }
    
    private func executeSaveRequest(request: NSSaveChangesRequest, inContext context: NSManagedObjectContext?) throws -> AnyObject {
        
        let realm = self.rootRealm!
        realm.beginWriteTransaction()
        
        try request.insertedObjects?.forEach {
            
            let backingClass = $0.entity.realmBackingClass
            let realmObject = backingClass.createBackingObjectInRealm(
                realm,
                referenceObject: self.referenceObjectForObjectID($0.objectID)
            )
            try realmObject.setValuesFromManagedObject($0)
            realm.addOrUpdateObject(realmObject)
        }
        
        try request.updatedObjects?.forEach {
            
            let backingClass = $0.entity.realmBackingClass
            let realmObject = backingClass.init(
                inRealm: realm,
                forPrimaryKey: self.referenceObjectForObjectID($0.objectID)
            )
            try realmObject?.setValuesFromManagedObject($0)
        }
        
        request.deletedObjects?.forEach {
            
            let backingClass = $0.entity.realmBackingClass
            let realmObject = backingClass.init(
                inRealm: realm,
                forPrimaryKey: self.referenceObjectForObjectID($0.objectID)
            )
            _ = realmObject.flatMap(realm.deleteObject)
        }
        
        try realm.commitWriteTransaction()
        
        return []
    }
}
