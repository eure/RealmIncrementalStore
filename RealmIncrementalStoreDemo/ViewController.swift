//
//  ViewController.swift
//  RealmIncrementalStoreDemo
//
//  Created by John Estropia on 2016/02/18.
//  Copyright © 2016年 John Estropia. All rights reserved.
//

import CoreData
import UIKit

class ViewController: UITableViewController, NSFetchedResultsControllerDelegate {
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        self.fetchedResultsController.delegate = self
        try! self.fetchedResultsController.performFetch()
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return self.fetchedResultsController.sections?.first?.numberOfObjects ?? 0
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)
        let testEntity = self.fetchedResultsController.objectAtIndexPath(indexPath) as! TestEntity
        cell.textLabel?.text = testEntity.stringField
        cell.detailTextLabel?.text = testEntity.intField.flatMap { "\($0)" }
        
        return cell
    }
    
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        
        tableView.deselectRowAtIndexPath(indexPath, animated: true)
        
        let object = self.fetchedResultsController.objectAtIndexPath(indexPath)
        
        NSManagedObjectContext.beginTransaction(
            { (context, entities) -> Void in
                
                guard let objectID = object.objectID,
                    let object = (try? context.existingObjectWithID(objectID)) as? TestEntity else {
                        
                        return
                }
                object.stringField = "random_\(arc4random_uniform(100))"
                object.intField = NSNumber(unsignedInt: arc4random_uniform(10000))
            }
        )
    }
    
    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        
        guard case .Delete = editingStyle else {
            
            return
        }
        
        let object = self.fetchedResultsController.objectAtIndexPath(indexPath)
        
        NSManagedObjectContext.beginTransaction(
            { (context, entities) -> Void in
                
                guard let objectID = object.objectID,
                    let object = (try? context.existingObjectWithID(objectID)) as? TestEntity else {
                        
                        return
                }
                context.deleteObject(object)
            }
        )
    }
    
    func controllerWillChangeContent(controller: NSFetchedResultsController) {
        
        self.tableView?.beginUpdates()
    }

    func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {
        
        guard let tableView = self.tableView else {
            
            return
        }
        switch type {
            
        case .Insert:
            tableView.insertRowsAtIndexPaths([newIndexPath!], withRowAnimation: .Automatic)
            
        case .Delete:
            tableView.deleteRowsAtIndexPaths([indexPath!], withRowAnimation: .Automatic)
            
        case .Update:
            tableView.deleteRowsAtIndexPaths([indexPath!], withRowAnimation: .Automatic)
            tableView.insertRowsAtIndexPaths([indexPath!], withRowAnimation: .Automatic)
            
        case .Move:
            tableView.moveRowAtIndexPath(indexPath!, toIndexPath: newIndexPath!)
        }
    }
    
    func controller(controller: NSFetchedResultsController, didChangeSection sectionInfo: NSFetchedResultsSectionInfo, atIndex sectionIndex: Int, forChangeType type: NSFetchedResultsChangeType) {
        
        switch type {
            
        case .Insert:
            self.tableView?.insertSections(NSIndexSet(index: sectionIndex), withRowAnimation: .Automatic)
            
        case .Delete:
            self.tableView?.deleteSections(NSIndexSet(index: sectionIndex), withRowAnimation: .Automatic)
            
        default:
            return
        }
    }
    
    func controllerDidChangeContent(controller: NSFetchedResultsController) {
        
        self.tableView?.endUpdates()
    }
    
    @IBAction func addBarButtonTapped(sender: UIBarButtonItem) {
        
        NSManagedObjectContext.beginTransaction(
            { (context, entities) -> Void in
            
                let object = TestEntity(
                    entity: entities["TestEntity"]!,
                    insertIntoManagedObjectContext: context
                )
                object.stringField = "random_\(arc4random_uniform(100))"
                object.intField = NSNumber(unsignedInt: arc4random_uniform(10000))
            }
        )
    }
    
    private(set) lazy var fetchedResultsController: NSFetchedResultsController = {
        
        let context = NSManagedObjectContext.mainContext
        
        let request = NSFetchRequest(entityName: "TestEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "stringField", ascending: true)]
        
        return NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
    }()
}

