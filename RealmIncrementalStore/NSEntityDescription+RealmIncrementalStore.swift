//
//  NSEntityDescription+RealmIncrementalStore.swift
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


// MARK: - NSEntityDescription

internal extension NSEntityDescription {
    
    internal typealias RealmBackingType = (backingClass: RLMObject.Type, objectSchema: RLMObjectSchema)
    
    @nonobjc internal static let RISUserInfoKey = "_RISUserInfoKey"
    @nonobjc internal static let RISBackingClassKey = "_RISBackingClassKey"
    @nonobjc internal static let RISObjectSchemaKey = "_RISObjectSchemaKey"
    
    @nonobjc internal var realmBackingClass: RLMObject.Type {
        
        if let backingClass = self.realmUserInfo[NSEntityDescription.RISBackingClassKey] as? RLMObject.Type {
            
            return backingClass
        }
        return self.loadRealmBackingTypeIfNeeded().backingClass
    }
    
    @nonobjc internal var realmObjectSchema: RLMObjectSchema {
        
        if let objectSchema = self.realmUserInfo[NSEntityDescription.RISObjectSchemaKey] as? RLMObjectSchema {
            
            return objectSchema
        }
        return self.loadRealmBackingTypeIfNeeded().objectSchema
    }
    
    @nonobjc private var realmUserInfo: [String: AnyObject] {
        
        get {
            
            return (self.userInfo?[NSEntityDescription.RISUserInfoKey] as? [String: AnyObject]) ?? [:]
        }
        set {
            
            if self.userInfo == nil {
                
                self.userInfo = [:]
            }
            self.userInfo?[NSEntityDescription.RISUserInfoKey] = newValue
        }
    }
    
    @nonobjc internal func loadRealmBackingTypeIfNeeded() -> RealmBackingType {
        
        enum Static {
            
            static let safeQueue = dispatch_queue_create("RealmIncrementalStore.backingType.queue", DISPATCH_QUEUE_CONCURRENT)
            static let posixLocale = NSLocale(localeIdentifier: "en_US_POSIX")
            static var classes = [NSData: RealmBackingType]()
        }
        
        var backingType: RealmBackingType?
        dispatch_barrier_sync(Static.safeQueue) {
            
            let versionHash = self.versionHash
            if let existingClass = Static.classes[versionHash] {
                
                backingType = existingClass
                return
            }
            
            let backingClass: AnyClass = objc_allocateClassPair(
                RLMObject.self,
                RLMObject.RISBackingClassNameForEntity(self).UTF8String,
                0
            )
            
            var defaultValues: [String: AnyObject] = [RLMObject.RISVersionProperty: 0]
            let attributes: [() -> RLMProperty]
//            let relationships: [() -> RLMProperty]
            do {
                
                attributes = self.attributesByName.flatMap { (attributeName, attributeDescription) -> (() -> RLMProperty)? in
                    
                    guard !attributeDescription.transient else {
                        
                        return nil
                    }
                    
                    let rawAttribute: NSString
                    let realmPropertyType: RLMPropertyType
                    switch attributeDescription.attributeType {
                        
                    case .BooleanAttributeType:
                        rawAttribute = "\"NSNumber<RLMBool>\""
                        realmPropertyType = .Bool
                        
                    case .Integer16AttributeType: fallthrough
                    case .Integer32AttributeType: fallthrough
                    case .Integer64AttributeType:
                        rawAttribute = "\"NSNumber<RLMInt>\""
                        realmPropertyType = .Int
                        
                    case .DateAttributeType:
                        rawAttribute = "\"NSDate\""
                        realmPropertyType = .Date
                        
                    case .DoubleAttributeType:
                        rawAttribute = "\"NSNumber<RLMDouble>\""
                        realmPropertyType = .Double
                        
                    case .FloatAttributeType:
                        rawAttribute = "\"NSNumber<RLMFloat>\""
                        realmPropertyType = .Float
                        
                    case .StringAttributeType:
                        rawAttribute = "\"NSString\""
                        realmPropertyType = .String
                        
                    case .BinaryDataAttributeType:
                        rawAttribute = "\"NSData\""
                        realmPropertyType = .Data
                        
                    case .DecimalAttributeType:
//                        rawAttribute = "\"NSString\""
//                        realmPropertyType = .String
//                        getterConverter = { ($0 as? String).flatMap { NSDecimalNumber(string: $0, locale: Static.posixLocale) } }
//                        setterConverter = { ($0 as? NSDecimalNumber).flatMap { $0.descriptionWithLocale(Static.posixLocale) } }
                        fatalError("Attribute data type unsupported")
                        
                    case .TransformableAttributeType:
//                        // Transformable only supports NSCopying instances
//                        rawAttribute = "\"NSData\""
//                        realmPropertyType = .Data
//                        getterConverter = { ($0 as? NSData).flatMap { NSKeyedUnarchiver.unarchiveObjectWithData($0) } }
//                        setterConverter = { $0.flatMap { NSKeyedArchiver.archivedDataWithRootObject($0) } }
                        fatalError("Attribute data type unsupported")
                        
                    case .ObjectIDAttributeType: fallthrough
                    case .UndefinedAttributeType:
                        fatalError()
                    }
                    
                    let selectorNames = NSEntityDescription.synthesizePropertyWithName(
                        attributeName,
                        toBackingClass: backingClass
                    )
                    let rawAttributes = [
                        objc_property_attribute_t(name: ("T" as NSString).UTF8String, value: rawAttribute.UTF8String),
                        objc_property_attribute_t(name: ("&" as NSString).UTF8String, value: ("" as NSString).UTF8String),
                        objc_property_attribute_t(name: ("V" as NSString).UTF8String, value: (selectorNames.iVar as NSString).UTF8String)
                    ]
                    rawAttributes.withUnsafeBufferPointer { buffer in
                        
                        guard class_addProperty(backingClass, attributeName, buffer.baseAddress, UInt32(buffer.count)) else {
                            
                            fatalError("Could not dynamically add property \"\(attributeName)\" to class \"\(backingClass)\"")
                        }
                    }
                    
                    if let defaultValue = attributeDescription.defaultValue as? NSObject {
                        
                        defaultValues[attributeName] = defaultValue
                    }
                    
                    return {
                        
                        let property = RLMProperty(
                            name: attributeName,
                            type: realmPropertyType,
                            objectClassName: nil,
                            indexed: attributeDescription.indexed,
                            optional: true
                        )
                        property.getterName = selectorNames.getter
                        property.getterSel = NSSelectorFromString(selectorNames.getter)
                        property.setterName = selectorNames.setter
                        property.setterSel = NSSelectorFromString(selectorNames.setter)
                        return property
                    }
                }
                
//                relationships = try self.relationshipsByName.flatMap { (relationshipName, relationshipDescription) -> (() -> RLMProperty)? in
//                    
//                    guard let destinationEntity = relationshipDescription.destinationEntity else {
//                        
//                        throw RealmIncrementalStoreError.RelationshipDestinationEntityUnknown
//                    }
//                    
//                    let realmPropertyType: RLMPropertyType
//                    if relationshipDescription.toMany {
//                        
//                        realmPropertyType = .Array
//                    }
//                    else {
//                        
//                        realmPropertyType = .Object
//                    }
//                    
//                    return {
//                        
//                        let property = RLMProperty(
//                            name: relationshipName,
//                            type: realmPropertyType,
//                            objectClassName: nil,
//                            indexed: false,
//                            optional: true
//                        )
//                        property.getterName = selectorNames.getter
//                        property.getterSel = NSSelectorFromString(selectorNames.getter)
//                        property.setterName = selectorNames.setter
//                        property.setterSel = NSSelectorFromString(selectorNames.setter)
//                        return property
//                    }
//                }
                
                
                
                NSEntityDescription.synthesizeResourceIDToBackingClass(backingClass)
                NSEntityDescription.synthesizeVersionToBackingClass(backingClass)
                
                let metaClass: AnyClass = object_getClass(backingClass)
                NSEntityDescription.addGetterBlock(
                    { _, _ in RLMObject.RISResourceIDProperty },
                    methodName: "primaryKey",
                    toBackingClass: metaClass
                )
                
                if !defaultValues.isEmpty {
                    
                    NSEntityDescription.addGetterBlock(
                        { _, _ in defaultValues },
                        methodName: "defaultPropertyValues",
                        toBackingClass: metaClass
                    )
                }
                
                objc_registerClassPair(backingClass)
            }
            
            
            let resourceIDProperty: RLMProperty
            let versionProperty: RLMProperty
            do {
                
                resourceIDProperty = RLMProperty(
                    name: RLMObject.RISResourceIDProperty,
                    type: .String,
                    objectClassName: nil,
                    indexed: true,
                    optional: false
                )
                resourceIDProperty.isPrimary = true
                resourceIDProperty.getterName = RLMObject.RISResourceIDProperty
                resourceIDProperty.getterSel = NSSelectorFromString(RLMObject.RISResourceIDProperty)
                resourceIDProperty.setterName = RLMObject.RISResourceIDSetter
                resourceIDProperty.setterSel = NSSelectorFromString(RLMObject.RISResourceIDSetter)
            }
            do {
                
                versionProperty = RLMProperty(
                    name: RLMObject.RISVersionProperty,
                    type: .Int,
                    objectClassName: nil,
                    indexed: false,
                    optional: false
                )
                versionProperty.getterName = RLMObject.RISVersionProperty
                versionProperty.getterSel = NSSelectorFromString(RLMObject.RISVersionProperty)
                versionProperty.setterName = RLMObject.RISVersionSetter
                versionProperty.setterSel = NSSelectorFromString(RLMObject.RISVersionSetter)
            }
            
            let objectSchema = RLMObjectSchema(
                className: NSStringFromClass(backingClass),
                objectClass: backingClass,
                properties: [resourceIDProperty, versionProperty]
                    + attributes.map({ $0() })
            )
            
            backingType = (backingClass as! RLMObject.Type, objectSchema)
            Static.classes[versionHash] = backingType
        }
        
        self.realmUserInfo[NSEntityDescription.RISBackingClassKey] = backingType!.backingClass
        self.realmUserInfo[NSEntityDescription.RISObjectSchemaKey] = backingType!.objectSchema
        
        return backingType!
    }
    
    private typealias IMPGetterFunction = @convention(block) (AnyObject, Selector) -> AnyObject?
    private typealias IMPSetterFunction = @convention(block) (AnyObject, Selector, AnyObject?) -> Void
    private typealias IMPValueConverterFunction = @convention(block) (AnyObject?) -> AnyObject?
    
    private static func addGetterBlock(getter: IMPGetterFunction = { _ in nil }, methodName: String, toBackingClass backingClass: AnyClass) {
        
        let succeeded = class_addMethod(
            backingClass,
            NSSelectorFromString(methodName),
            imp_implementationWithBlock(unsafeBitCast(getter, AnyObject.self)),
            "@:"
        )
        guard succeeded else {
            
            fatalError("Could not dynamically add getter method \"\(methodName)\" to class \"\(backingClass)\"")
        }
    }
    
    private static func addSetterBlock(setter: IMPSetterFunction = { _ in }, methodName: String, toBackingClass backingClass: AnyClass) {
        
        let succeeded = class_addMethod(
            backingClass,
            NSSelectorFromString(methodName),
            imp_implementationWithBlock(unsafeBitCast(setter, AnyObject.self)),
            "v@:@"
        )
        guard succeeded else {
            
            fatalError("Could not dynamically add setter method \"\(methodName)\" to class \"\(backingClass)\"")
        }
    }
    
    private static func synthesizeResourceIDToBackingClass(backingClass: AnyClass) {
        
        self.addGetterBlock(
            methodName: RLMObject.RISResourceIDProperty,
            toBackingClass: backingClass
        )
        self.addSetterBlock(
            methodName: RLMObject.RISResourceIDSetter,
            toBackingClass: backingClass
        )
    }
    
    private static func synthesizeVersionToBackingClass(backingClass: AnyClass) {
        
        self.addGetterBlock(
            methodName: RLMObject.RISVersionProperty,
            toBackingClass: backingClass
        )
        self.addSetterBlock(
            methodName: RLMObject.RISVersionSetter,
            toBackingClass: backingClass
        )
    }
    
    private static func synthesizePropertyWithName(propertyName: String, toBackingClass backingClass: AnyClass) -> (iVar: String, getter: String, setter: String) {
        
        let iVarName = "_\(propertyName)"
        
        let getterName = propertyName
        self.addGetterBlock(
            methodName: getterName,
            toBackingClass: backingClass
        )
        
        let alphabetSet = NSCharacterSet(charactersInString: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let capitalized = propertyName.characters.enumerate().flatMap { (index, character) -> [Character] in
            
            if index == 0 {
                
                let string = String(character)
                if let _ = string.rangeOfCharacterFromSet(alphabetSet) {
                    
                    return Array(string.uppercaseString.characters)
                }
            }
            return [character]
        }
        let setterName = "set\(String(capitalized)):"
        self.addSetterBlock(
            methodName: setterName,
            toBackingClass: backingClass
        )
        return (iVar: iVarName, getter: getterName, setter: setterName)
    }
}
