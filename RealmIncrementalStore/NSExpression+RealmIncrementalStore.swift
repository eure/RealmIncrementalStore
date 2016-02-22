//
//  NSExpression+RealmIncrementalStore.swift
//  RealmIncrementalStore
//
//  Created by John Estropia on 2016/02/22.
//  Copyright © 2016年 John Estropia. All rights reserved.
//

import CoreData
import Foundation
import Realm

internal extension NSExpression {
    
    internal func realmExpression() -> NSExpression {
        
        switch self.expressionType {
            
        case .ConstantValueExpressionType:
            switch self.constantValue {
                
            case let object as NSManagedObject:
                guard let realmObject = object.realmObject() else {
                    
                    return self
                }
                return NSExpression(forConstantValue: realmObject)
                
            case let set as NSSet:
                return NSExpression(
                    forConstantValue: set.map { $0.realmObject() ?? $0 }
                )
                
            case let array as NSArray:
                return NSExpression(
                    forConstantValue: array.map { $0.realmObject() ?? $0 }
                )
                
            default:
                return self
            }
            
        default:
            return self
        }
    }
}
