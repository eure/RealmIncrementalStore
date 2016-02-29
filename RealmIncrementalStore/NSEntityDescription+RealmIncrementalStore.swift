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


internal typealias RealmBackingType = (backingClass: RLMObject.Type, objectSchema: RLMObjectSchema)

private let RISUserInfoKey = "_RISUserInfoKey"
private let RISObjectSchemaKey = "_RISObjectSchemaKey"

private enum Static {
    
    static let arrayBarrierQueue = dispatch_queue_create("RealmIncrementalStore.entities.queue", DISPATCH_QUEUE_CONCURRENT)
    static let entityBarrierQueue = dispatch_queue_create("RealmIncrementalStore.entity.queue", DISPATCH_QUEUE_CONCURRENT)
    static var classes = [NSData: RLMObject.Type]()
}

internal extension Array where Element: NSEntityDescription {
    
    internal func loadObjectSchemas() -> [RLMObjectSchema] {
        
        var objectSchema = [RLMObjectSchema]()
        dispatch_barrier_sync(Static.arrayBarrierQueue) {
            
            objectSchema = self.map {
                
                $0.loadRealmObjectSchemaForBackingClass()
            }
        }
        return objectSchema
    }
}


// MARK: - NSEntityDescription

internal extension NSEntityDescription {
    
    // MARK: Internal
    
    @nonobjc internal var realmBackingClass: RLMObject.Type {
        
        return self.loadRealmBackingClassIfNeeded()
    }
    
    @nonobjc internal var realmObjectSchema: RLMObjectSchema {
        
        return self.loadRealmObjectSchemaForBackingClass()
    }
    
    @nonobjc private var realmUserInfo: [String: AnyObject] {
        
        get {
            
            return (self.userInfo?[RISUserInfoKey] as? [String: AnyObject]) ?? [:]
        }
        set {
            
            if self.userInfo == nil {
                
                self.userInfo = [:]
            }
            self.userInfo?[RISUserInfoKey] = newValue
        }
    }
    
    private func loadRealmBackingClassIfNeeded() -> RLMObject.Type {
        
        // One day the realm-core will be opened to public and we won't have to rely on dynamic classes to build schemas.
        
        var backingClass: RLMObject.Type?
        dispatch_barrier_sync(Static.entityBarrierQueue) {
            
            let versionHash = self.versionHash
            if let existingClass = Static.classes[versionHash] {
                
                backingClass = existingClass
                return
            }
            
            let newClass = objc_allocateClassPair(
                RLMObject.self,
                RLMObject.RISBackingClassNameForEntity(self).UTF8String,
                0
            ) as! RLMObject.Type
            
            defer {
                
                objc_registerClassPair(newClass)
                Static.classes[versionHash] = newClass
                backingClass = newClass
            }
            
            var properties = [(propertyName: String, rawAttribute: NSString)]()
            var defaultValues: [String: AnyObject] = [RLMObject.RISVersionProperty: 0]
            
            self.attributesByName.forEach { (name, description) in
                
                guard !description.transient else {
                    
                    return
                }
                
                switch description.attributeType {
                    
                case .BooleanAttributeType:
                    properties.append((name, "\"NSNumber<RLMBool>\""))
                    
                case .Integer16AttributeType: fallthrough
                case .Integer32AttributeType: fallthrough
                case .Integer64AttributeType:
                    properties.append((name, "\"NSNumber<RLMInt>\""))
                    
                case .DateAttributeType:
                    properties.append((name, "\"NSNumber<NSDate>\""))
                    
                case .DoubleAttributeType:
                    properties.append((name, "\"NSNumber<RLMDouble>\""))
                    
                case .FloatAttributeType:
                    properties.append((name, "\"NSNumber<RLMFloat>\""))
                    
                case .StringAttributeType:
                    properties.append((name, "\"NSString\""))
                    
                case .BinaryDataAttributeType:
                    properties.append((name, "\"NSData\""))
                    
                case .DecimalAttributeType:
                    fatalError("Attribute data type unsupported")
                    
                case .TransformableAttributeType:
                    fatalError("Attribute data type unsupported")
                    
                case .ObjectIDAttributeType: fallthrough
                case .UndefinedAttributeType:
                    fatalError()
                }
                
                if let defaultValue = description.defaultValue as? NSObject {
                    
                    defaultValues[name] = defaultValue
                }
            }
            
            self.relationshipsByName.forEach { (name, description) in
                
                guard let destinationEntity = description.destinationEntity else {
                    
                    fatalError("Missing relationship destination for \"\(name)\" in class \"\(newClass)\"")
                }
                
                let destinationBackingClassName = RLMObject.RISBackingClassNameForEntity(destinationEntity)
                if description.toMany {
                    
                    let `protocol`: Protocol = objc_allocateProtocol(("" as NSString).UTF8String)
                    objc_registerProtocol(`protocol`)
                    
                    class_addProtocol(newClass, `protocol`)
                    
                    properties.append((name, "\"RLMArray<id><\(destinationBackingClassName)>\""))
                }
                else {
                    
                    properties.append((name, "\"\(destinationBackingClassName)\""))
                }
            }
            
            properties.forEach { (propertyName, rawAttribute) in
                
                let selectorNames = NSEntityDescription.synthesizePropertyWithNameIfNeeded(
                    propertyName,
                    toBackingClass: newClass
                )
                let rawAttributes = [
                    objc_property_attribute_t(
                        name: ("T@" as NSString).UTF8String,
                        value: rawAttribute.UTF8String
                    ),
                    objc_property_attribute_t(
                        name: ("&" as NSString).UTF8String,
                        value: ("" as NSString).UTF8String
                    ),
                    objc_property_attribute_t(
                        name: ("V" as NSString).UTF8String,
                        value: (selectorNames.iVar as NSString).UTF8String
                    )
                ]
                
                rawAttributes.withUnsafeBufferPointer { buffer in
                    
                    guard class_addProperty(newClass, propertyName, buffer.baseAddress, UInt32(buffer.count)) else {
                        
                        fatalError("Could not dynamically add property \"\(propertyName)\" to class \"\(newClass)\"")
                    }
                }
            }
            
            NSEntityDescription.synthesizeResourceIDToBackingClass(newClass)
            NSEntityDescription.synthesizeVersionToBackingClass(newClass)
            
            let metaClass: AnyClass = object_getClass(newClass)
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
        }
        return backingClass!
    }
    
    private func loadRealmObjectSchemaForBackingClass() -> RLMObjectSchema {
        
        if let objectSchema = self.realmUserInfo[RISObjectSchemaKey] as? RLMObjectSchema {
            
            return objectSchema
        }
        
        let backingClass = self.loadRealmBackingClassIfNeeded()
        
        let attributeProperties = self.attributesByName.flatMap { (name, description) -> RLMProperty? in
            
            guard !description.transient else {
                
                return nil
            }
            
            let realmPropertyType: RLMPropertyType
            switch description.attributeType {
                
            case .BooleanAttributeType:
                realmPropertyType = .Bool
                
            case .Integer16AttributeType: fallthrough
            case .Integer32AttributeType: fallthrough
            case .Integer64AttributeType:
                realmPropertyType = .Int
                
            case .DateAttributeType:
                realmPropertyType = .Date
                
            case .DoubleAttributeType:
                realmPropertyType = .Double
                
            case .FloatAttributeType:
                realmPropertyType = .Float
                
            case .StringAttributeType:
                realmPropertyType = .String
                
            case .BinaryDataAttributeType:
                realmPropertyType = .Data
                
            case .DecimalAttributeType:
                fatalError("Attribute data type unsupported")
                
            case .TransformableAttributeType:
                fatalError("Attribute data type unsupported")
                
            case .ObjectIDAttributeType: fallthrough
            case .UndefinedAttributeType:
                fatalError()
            }
            
            let selectorNames = NSEntityDescription.synthesizePropertyWithNameIfNeeded(
                name,
                toBackingClass: backingClass
            )
            
            let property = RLMProperty(
                name: name,
                type: realmPropertyType,
                objectClassName: nil,
                indexed: description.indexed,
                optional: true
            )
            property.getterName = selectorNames.getter
            property.getterSel = NSSelectorFromString(selectorNames.getter)
            property.setterName = selectorNames.setter
            property.setterSel = NSSelectorFromString(selectorNames.setter)
            return property
        }
        
        let relationshipProperties = self.relationshipsByName.flatMap { (name, description) -> RLMProperty? in
            
            guard let destinationEntity = description.destinationEntity else {
                
                fatalError("Missing relationship destination for \"\(name)\" in class \"\(backingClass)\"")
            }
            
            let realmPropertyType: RLMPropertyType
            let optional: Bool
            if description.toMany {
                
                realmPropertyType = .Array
                optional = false
            }
            else {
                
                realmPropertyType = .Object
                optional = true
            }
            
            let selectorNames = NSEntityDescription.synthesizePropertyWithNameIfNeeded(
                name,
                toBackingClass: backingClass
            )
            
            let destinationBackingClassName = RLMObject.RISBackingClassNameForEntity(destinationEntity)
            let property = RLMProperty(
                name: name,
                type: realmPropertyType,
                objectClassName: destinationBackingClassName as String,
                indexed: false,
                optional: optional
            )
            property.getterName = selectorNames.getter
            property.getterSel = NSSelectorFromString(selectorNames.getter)
            property.setterName = selectorNames.setter
            property.setterSel = NSSelectorFromString(selectorNames.setter)
            return property
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
                + attributeProperties
                + relationshipProperties
        )
        self.realmUserInfo[RISObjectSchemaKey] = objectSchema
        return objectSchema
    }
    
    
    // MARK: Private
    
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
    
    private static func synthesizePropertyWithNameIfNeeded(propertyName: String, toBackingClass backingClass: AnyClass) -> (iVar: String, getter: String, setter: String) {
        
        let iVarName = "_\(propertyName)"
        let getterName = propertyName
        
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
        
        if !backingClass.instancesRespondToSelector(NSSelectorFromString(getterName)) {
            
            self.addGetterBlock(
                methodName: getterName,
                toBackingClass: backingClass
            )
        }
        if !backingClass.instancesRespondToSelector(NSSelectorFromString(setterName)) {
            
            self.addSetterBlock(
                methodName: setterName,
                toBackingClass: backingClass
            )
        }
        return (iVar: iVarName, getter: getterName, setter: setterName)
    }
}
