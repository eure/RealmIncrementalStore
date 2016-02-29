//
//  TestAnotherEntity+CoreDataProperties.swift
//  RealmIncrementalStoreDemo
//
//  Created by John Estropia on 2016/02/26.
//  Copyright © 2016年 John Estropia. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension TestAnotherEntity {

    @NSManaged var dateField: NSDate?
    @NSManaged var intField: NSNumber?
    @NSManaged var sectionField: String?
    @NSManaged var stringField: String?
    @NSManaged var testEntities: NSSet?

}
