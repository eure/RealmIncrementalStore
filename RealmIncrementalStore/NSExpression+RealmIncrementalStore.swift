//
//  NSExpression+RealmIncrementalStore.swift
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

import CoreData
import Foundation
import Realm


// MARK: - NSExpression

internal extension NSExpression {
    
    internal func realmExpression() -> NSExpression {
        
        switch self.expressionType {
            
        case .ConstantValueExpressionType:
            switch self.constantValue {
                
            case let objectID as NSManagedObjectID:
                guard let realmObject = objectID.realmObject() else {
                    
                    return self
                }
                return NSExpression(forConstantValue: realmObject)
                
            case let set as Set<NSManagedObjectID>:
                return NSExpression(
                    forConstantValue: set.map { $0.realmObject() ?? $0 }
                )
                
            case let array as [NSManagedObjectID]:
                return NSExpression(
                    forConstantValue: array.map { $0.realmObject() ?? $0 }
                )
                
            case let object as NSManagedObject:
                guard let realmObject = object.objectID.realmObject() else {
                    
                    return self
                }
                return NSExpression(forConstantValue: realmObject)
                
            case let set as Set<NSManagedObject>:
                return NSExpression(
                    forConstantValue: set.map { $0.objectID.realmObject() ?? $0 }
                )
                
            case let array as [NSManagedObject]:
                return NSExpression(
                    forConstantValue: array.map { $0.objectID.realmObject() ?? $0 }
                )
                
            default:
                return self
            }
            
        default:
            return self
        }
    }
}
