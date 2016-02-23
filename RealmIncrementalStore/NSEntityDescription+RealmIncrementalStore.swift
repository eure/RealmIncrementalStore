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
    
    @nonobjc internal static let RISBackingClassKey = "_RISBackingClassKey"
    @nonobjc internal static let RISObjectSchemaKey = "_RISObjectSchemaKey"
    
    @nonobjc internal var realmBackingClass: RLMObject.Type {
        
        if let userInfo = self.userInfo,
            let backingClass = userInfo[NSEntityDescription.RISBackingClassKey] as? RLMObject.Type {
                
                return backingClass
        }
        return self.loadRealmBackingTypeIfNeeded().backingClass
    }
    
    @nonobjc internal var realmObjectSchema: RLMObjectSchema {
        
        if let userInfo = self.userInfo,
            let objectSchema = userInfo[NSEntityDescription.RISObjectSchemaKey] as? RLMObjectSchema {
                
                return objectSchema
        }
        return self.loadRealmBackingTypeIfNeeded().objectSchema
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
            var defaultValues: [String: AnyObject] = [
                RLMObject.RISVersionProperty: 0
            ]
            let properties = self.attributesByName.map { (attributeName, attributeDescription) -> (() -> RLMProperty) in
                
                let rawAttribute: NSString
                let realmPropertyType: RLMPropertyType
                let getterConverter: IMPValueConverterFunction?
                let setterConverter: IMPValueConverterFunction?
                switch attributeDescription.attributeType {
                    
                case .BooleanAttributeType:
                    rawAttribute = "\"NSNumber<RLMBool>\""
                    realmPropertyType = .Bool
                    getterConverter = nil
                    setterConverter = nil
                    
                case .Integer16AttributeType: fallthrough
                case .Integer32AttributeType: fallthrough
                case .Integer64AttributeType:
                    rawAttribute = "\"NSNumber<RLMInt>\""
                    realmPropertyType = .Int
                    getterConverter = nil
                    setterConverter = nil
                    
                case .DateAttributeType:
                    rawAttribute = "\"NSNumber<RLMDouble>\""
                    realmPropertyType = .Double
                    getterConverter = { ($0 as? NSNumber).flatMap { NSDate(timeIntervalSince1970: $0.doubleValue) } }
                    setterConverter = { ($0 as? NSDate).flatMap { $0.timeIntervalSince1970 } }
                    
                case .DoubleAttributeType:
                    rawAttribute = "\"NSNumber<RLMDouble>\""
                    realmPropertyType = .Double
                    getterConverter = nil
                    setterConverter = nil
                    
                case .FloatAttributeType:
                    rawAttribute = "\"NSNumber<RLMFloat>\""
                    realmPropertyType = .Float
                    getterConverter = nil
                    setterConverter = nil
                    
                case .DecimalAttributeType:
                    rawAttribute = "\"NSString\""
                    realmPropertyType = .String
                    getterConverter = { ($0 as? String).flatMap { NSDecimalNumber(string: $0, locale: Static.posixLocale) } }
                    setterConverter = { ($0 as? NSDecimalNumber).flatMap { $0.descriptionWithLocale(Static.posixLocale) } }
                    
                case .StringAttributeType:
                    rawAttribute = "\"NSString\""
                    realmPropertyType = .String
                    getterConverter = nil
                    setterConverter = nil
                    
                case .BinaryDataAttributeType:
                    rawAttribute = "\"NSData\""
                    realmPropertyType = .Data
                    getterConverter = nil
                    setterConverter = nil
                    
                case .TransformableAttributeType:
                    // If your attribute is of NSTransformableAttributeType, the attributeValueClassName must be set or attribute value class must implement NSCopying.
                    // TODO: implement
                    fatalError()
                    
                case .ObjectIDAttributeType: fallthrough
                case .UndefinedAttributeType:
                    fatalError()
                }
                
                let selectorNames = NSEntityDescription.synthesizePropertyWithName(
                    attributeName,
                    toBackingClass: backingClass,
                    getter: getterConverter,
                    setter: setterConverter
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
                    
                    if let setterConverter = setterConverter {
                        
                        defaultValues[attributeName] = setterConverter(defaultValue)
                    }
                    else {
                        
                        defaultValues[attributeName] = defaultValue
                    }
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
            
            NSEntityDescription.synthesizeResourceIDToBackingClass(backingClass)
            NSEntityDescription.synthesizeVersionToBackingClass(backingClass)
            
            let metaClass: AnyClass = object_getClass(backingClass)
            NSEntityDescription.addGetterBlock(
                { _, _ in RLMObject.RISResourceIDProperty },
                methodName: "primaryKey",
                toBackingClass: metaClass
            )
            
            // TODO: transient
            
            if !defaultValues.isEmpty {
                
                NSEntityDescription.addGetterBlock(
                    { _, _ in defaultValues },
                    methodName: "defaultPropertyValues",
                    toBackingClass: metaClass
                )
            }
            
            objc_registerClassPair(backingClass)
            
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
                properties: [resourceIDProperty, versionProperty] + properties.map({ $0() })
            )
            
            backingType = (backingClass as! RLMObject.Type, objectSchema)
            Static.classes[versionHash] = backingType
        }
        
        var userInfo = self.userInfo ?? [:]
        userInfo[NSEntityDescription.RISBackingClassKey] = backingType!.backingClass
        userInfo[NSEntityDescription.RISObjectSchemaKey] = backingType!.objectSchema
        self.userInfo = userInfo
        
        return backingType!
    }
    
    private typealias IMPGetterFunction = @convention(block) (AnyObject, Selector) -> AnyObject?
    private typealias IMPSetterFunction = @convention(block) (AnyObject, Selector, AnyObject?) -> Void
    private typealias IMPValueConverterFunction = @convention(block) (AnyObject?) -> AnyObject?
    
    private static func addGetterBlock(getter: IMPGetterFunction, methodName: String, toBackingClass backingClass: AnyClass) {
        
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
    
    private static func addSetterBlock(getter: IMPSetterFunction, methodName: String, toBackingClass backingClass: AnyClass) {
        
        let succeeded = class_addMethod(
            backingClass,
            NSSelectorFromString(methodName),
            imp_implementationWithBlock(unsafeBitCast(getter, AnyObject.self)),
            "v@:@"
        )
        guard succeeded else {
            
            fatalError("Could not dynamically add setter method \"\(methodName)\" to class \"\(backingClass)\"")
        }
    }
    
    private static func synthesizeResourceIDToBackingClass(backingClass: AnyClass) {
        
        self.addGetterBlock(
            { (`self`, _) -> AnyObject? in
                
                return object_getIvar(
                    self,
                    class_getInstanceVariable(backingClass, RLMObject.RISResourceIDIVar)
                )
            },
            methodName: RLMObject.RISResourceIDProperty,
            toBackingClass: backingClass
        )
        self.addSetterBlock(
            { (`self`, _, value) -> Void in
                
                object_setIvar(
                    self,
                    class_getInstanceVariable(backingClass, RLMObject.RISResourceIDIVar),
                    value
                )
            },
            methodName: RLMObject.RISResourceIDSetter,
            toBackingClass: backingClass
        )
    }
    
    private static func synthesizeVersionToBackingClass(backingClass: AnyClass) {
        
        self.addGetterBlock(
            { (`self`, _) -> AnyObject? in
                
                return object_getIvar(
                    self,
                    class_getInstanceVariable(backingClass, RLMObject.RISVersionIVar)
                )
            },
            methodName: RLMObject.RISVersionProperty,
            toBackingClass: backingClass
        )
        self.addSetterBlock(
            { (`self`, _, value) -> Void in
                
                object_setIvar(
                    self,
                    class_getInstanceVariable(backingClass, RLMObject.RISVersionIVar),
                    value
                )
            },
            methodName: RLMObject.RISVersionSetter,
            toBackingClass: backingClass
        )
    }
    
    private static func synthesizePropertyWithName(propertyName: String, toBackingClass backingClass: AnyClass, getter: IMPValueConverterFunction? = nil, setter: IMPValueConverterFunction? = nil) -> (iVar: String, getter: String, setter: String) {
        
        let iVarName = "_\(propertyName)"
        
        let actualGetter: IMPGetterFunction
        if let getter = getter {
            
            actualGetter = { (`self`, _) -> AnyObject? in
                
                return getter(
                    object_getIvar(
                        self,
                        class_getInstanceVariable(backingClass, iVarName)
                    )
                )
            }
        }
        else {
            
            actualGetter = { (`self`, _) -> AnyObject? in
                
                return object_getIvar(
                    self,
                    class_getInstanceVariable(backingClass, iVarName)
                )
            }
        }
        
        let getterName = propertyName
        self.addGetterBlock(
            actualGetter,
            methodName: getterName,
            toBackingClass: backingClass
        )
        
        let actualSetter: IMPSetterFunction
        if let setter = setter {
            
            actualSetter = { (`self`, _, value) -> Void in
                
                object_setIvar(
                    self,
                    class_getInstanceVariable(backingClass, iVarName),
                    setter(value)
                )
            }
        }
        else {
            
            actualSetter = { (`self`, _, value) -> Void in
                
                object_setIvar(
                    self,
                    class_getInstanceVariable(backingClass, iVarName),
                    value
                )
            }
        }
        let setterName = "set\(propertyName.capitalizedString):"
        self.addSetterBlock(
            actualSetter,
            methodName: setterName,
            toBackingClass: backingClass
        )
        return (iVar: iVarName, getter: getterName, setter: setterName)
    }
}
