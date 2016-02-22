//
//  NSPredicate+RealmIncrementalStore.swift
//  RealmIncrementalStore
//
//  Created by John Estropia on 2016/02/22.
//  Copyright © 2016年 John Estropia. All rights reserved.
//

import CoreData
import Foundation
import Realm

internal extension NSPredicate {
    
    internal func realmPredicate() -> NSPredicate {
        
        switch self {
            
        case let `self` as NSCompoundPredicate:
            return NSCompoundPredicate(
                type: self.compoundPredicateType,
                subpredicates: self.subpredicates.map {
                    
                    ($0 as! NSPredicate).realmPredicate()
                }
            )
            
        case let `self` as NSComparisonPredicate where self.predicateOperatorType != .CustomSelectorPredicateOperatorType:
            return NSComparisonPredicate(
                leftExpression: self.leftExpression.realmExpression(),
                rightExpression: self.rightExpression.realmExpression(),
                modifier: self.comparisonPredicateModifier,
                type: self.predicateOperatorType,
                options: self.options
            )
            
        default:
            return self
        }
    }
}
