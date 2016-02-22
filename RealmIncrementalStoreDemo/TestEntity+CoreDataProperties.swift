//
//  TestEntity+CoreDataProperties.swift
//  RealmIncrementalStoreDemo
//
//  Created by John Estropia on 2016/02/22.
//  Copyright © 2016年 John Estropia. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension TestEntity {

    @NSManaged var intField: NSNumber?
    @NSManaged var stringField: String?

}
