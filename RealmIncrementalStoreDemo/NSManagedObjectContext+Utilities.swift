//
//  NSManagedObjectContext.swift
//  RealmIncrementalStoreDemo
//
//  Created by John Estropia on 2016/02/22.
//  Copyright © 2016年 John Estropia. All rights reserved.
//

import CoreData
import Foundation
import RealmIncrementalStore

extension NSManagedObjectContext {
    
    @nonobjc static func beginTransaction(transaction: (context: NSManagedObjectContext, entities: [String: NSEntityDescription]) -> Void, completion: () -> Void = {}) {
        
        let app = UIApplication.sharedApplication().delegate as! AppDelegate
        let mainContext = NSManagedObjectContext.mainContext
        
        mainContext.performBlock { () -> Void in
            
            let temporaryContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
            temporaryContext.parentContext = mainContext
            temporaryContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            
            temporaryContext.performBlock {
                
                transaction(
                    context: temporaryContext,
                    entities: NSManagedObjectContext.managedObjectModel.entitiesByName
                )
                
                guard temporaryContext.hasChanges else {
                    
                    dispatch_async(dispatch_get_main_queue(), completion)
                    return
                }
                
                do {
                    
                    try temporaryContext.save()
                    mainContext.performBlock {
                        
                        defer {
                            
                            dispatch_async(dispatch_get_main_queue(), completion)
                        }
                        
                        guard mainContext.hasChanges else {
                            
                            return
                        }
                        
                        do {
                            
                            try mainContext.save()
                        }
                        catch let error as NSError {
                            
                            print("Unresolved error \(error), \(error.userInfo)")
                        }
                    }
                }
                catch let error as NSError {
                    
                    print("Unresolved error \(error), \(error.userInfo)")
                    dispatch_async(dispatch_get_main_queue(), completion)
                }
            }
        }
    }
    
    @nonobjc static var mainContext: NSManagedObjectContext = {
        
        let coordinator = NSManagedObjectContext.persistentStoreCoordinator
        let managedObjectContext = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = coordinator
        return managedObjectContext
    }()
    
    @nonobjc private static var persistentStoreCoordinator: NSPersistentStoreCoordinator = {
        
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectContext.managedObjectModel)
        let documentsDirectory = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).last!
        let url = documentsDirectory.URLByAppendingPathComponent("SingleViewCoreData.realm")
        
        do {
            
            try coordinator.addPersistentStoreWithType(
                RealmIncrementalStore.storeType,
                configuration: nil,
                URL: url,
                options: nil
            )
            print("Persistent Store loaded from: \(url)")
        }
        catch let error as NSError {
            
            print(error)
        }
        
        return coordinator
    }()
    
    @nonobjc private static var managedObjectModel: NSManagedObjectModel = {
        
        let modelURL = NSBundle.mainBundle().URLForResource(
            "RealmIncrementalStoreDemo",
            withExtension: "momd"
        )
        return NSManagedObjectModel(contentsOfURL: modelURL!)!
    }()
}
