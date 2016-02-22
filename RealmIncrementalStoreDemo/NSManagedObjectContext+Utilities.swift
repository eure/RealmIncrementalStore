//
//  NSManagedObjectContext.swift
//  RealmIncrementalStoreDemo
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
