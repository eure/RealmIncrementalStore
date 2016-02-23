//
//  ViewController.swift
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
import UIKit

class ViewController: UITableViewController, NSFetchedResultsControllerDelegate {
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        self.fetchedResultsController.delegate = self
        try! self.fetchedResultsController.performFetch()
    }
    
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        
        return self.fetchedResultsController.sections?.count ?? 0
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return self.fetchedResultsController.sections?[section].numberOfObjects ?? 0
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)
        let testEntity = self.fetchedResultsController.objectAtIndexPath(indexPath) as! TestEntity
        cell.textLabel?.text = testEntity.stringField
        cell.detailTextLabel?.text = testEntity.intField.flatMap { "\($0)" }
        
        return cell
    }
    
    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        
        return self.fetchedResultsController.sections?[section].name
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
                object.randomize()
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
            if let cell = tableView.cellForRowAtIndexPath(indexPath!) {
                
                let testEntity = self.fetchedResultsController.objectAtIndexPath(indexPath!) as! TestEntity
                cell.textLabel?.text = testEntity.stringField
                cell.detailTextLabel?.text = testEntity.intField.flatMap { "\($0)" }
            }
            
        case .Move:
            tableView.deleteRowsAtIndexPaths([indexPath!], withRowAnimation: .Automatic)
            tableView.insertRowsAtIndexPaths([newIndexPath!], withRowAnimation: .Automatic)
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
                object.randomize()
            }
        )
    }
    
    private(set) lazy var fetchedResultsController: NSFetchedResultsController = {
        
        let context = NSManagedObjectContext.mainContext
        
        let request = NSFetchRequest(entityName: "TestEntity")
        request.sortDescriptors = [
            NSSortDescriptor(key: "sectionField", ascending: true),
            NSSortDescriptor(key: "stringField", ascending: true)
        ]
        
        return NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: "sectionField",
            cacheName: nil
        )
    }()
}

