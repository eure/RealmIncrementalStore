//
//  NSEntityDescription+RealmIncrementalStore.swift
//  RealmIncrementalStore
//
//  Created by John Estropia on 2016/02/19.
//  Copyright © 2016年 John Estropia. All rights reserved.
//

import Foundation
import CoreData
import Realm

internal extension NSEntityDescription {
    
    internal typealias RealmBackingType = (backingClass: RLMObject.Type, objectSchema: RLMObjectSchema)
    
    internal var realmBackingType: RealmBackingType {
        
        enum Static {
            
            static let safeQueue = dispatch_queue_create("RealmIncrementalStore.backingType.queue", DISPATCH_QUEUE_CONCURRENT)
            static let posixLocale = NSLocale(localeIdentifier: "en_US_POSIX")
            static var classes = [NSData: RealmBackingType]()
        }
        
        var backingClass: RealmBackingType?
        dispatch_barrier_sync(Static.safeQueue) {
            
            let versionHash = self.versionHash
            if let existingClass = Static.classes[versionHash] {
                
                backingClass = existingClass
                return
            }
            
            let newClass: AnyClass = objc_allocateClassPair(
                RLMObject.self,
                RLMObject.IncrementalStoreBackingClassNameForEntity(self).UTF8String,
                0
            )
            var defaultValues: [String: AnyObject] = [:]
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
                
                let selectorNames = self.synthesizePropertyWithName(
                    attributeName,
                    toBackingClass: newClass,
                    getter: getterConverter,
                    setter: setterConverter
                )
                let rawAttributes = [
                    objc_property_attribute_t(name: ("T" as NSString).UTF8String, value: rawAttribute.UTF8String),
                    objc_property_attribute_t(name: ("&" as NSString).UTF8String, value: ("" as NSString).UTF8String),
                    objc_property_attribute_t(name: ("V" as NSString).UTF8String, value: (selectorNames.iVar as NSString).UTF8String)
                ]
                rawAttributes.withUnsafeBufferPointer { buffer in
                    
                    guard class_addProperty(newClass, attributeName, buffer.baseAddress, UInt32(buffer.count)) else {
                        
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
            
            self.synthesizePrimaryKeyToBackingClass(newClass)
            
            let metaClass: AnyClass = object_getClass(newClass)
            self.addGetterBlock(
                { _, _ in RLMObject.IncrementalStoreResourceIDProperty },
                methodName: "primaryKey",
                toBackingClass: metaClass
            )
            
            // TODO: transient
            
            if !defaultValues.isEmpty {
                
                self.addGetterBlock(
                    { _, _ in defaultValues },
                    methodName: "defaultPropertyValues",
                    toBackingClass: metaClass
                )
            }
            
            objc_registerClassPair(newClass)
            
            let primaryKeyProperty = RLMProperty(
                name: RLMObject.IncrementalStoreResourceIDProperty,
                type: .String,
                objectClassName: nil,
                indexed: true,
                optional: false
            )
            primaryKeyProperty.isPrimary = true
            primaryKeyProperty.getterName = RLMObject.IncrementalStoreResourceIDProperty
            primaryKeyProperty.getterSel = NSSelectorFromString(RLMObject.IncrementalStoreResourceIDProperty)
            primaryKeyProperty.setterName = RLMObject.IncrementalStoreResourceIDSetter
            primaryKeyProperty.setterSel = NSSelectorFromString(RLMObject.IncrementalStoreResourceIDSetter)
            
            let objectSchema = RLMObjectSchema(
                className: NSStringFromClass(newClass),
                objectClass: newClass,
                properties: [primaryKeyProperty] + properties.map({ $0() })
            )
            
            backingClass = (newClass as! RLMObject.Type, objectSchema)
            Static.classes[versionHash] = backingClass
        }
        return backingClass!
    }
    
    private typealias IMPGetterFunction = @convention(block) (AnyObject, Selector) -> AnyObject?
    private typealias IMPSetterFunction = @convention(block) (AnyObject, Selector, AnyObject?) -> Void
    private typealias IMPValueConverterFunction = @convention(block) (AnyObject?) -> AnyObject?
    
    private func addGetterBlock(getter: IMPGetterFunction, methodName: String, toBackingClass backingClass: AnyClass) {
        
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
    
    private func addSetterBlock(getter: IMPSetterFunction, methodName: String, toBackingClass backingClass: AnyClass) {
        
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
    
    private func synthesizePrimaryKeyToBackingClass(backingClass: AnyClass) {
        
        self.addGetterBlock(
            { (`self`, _) -> AnyObject? in
                
                return object_getIvar(self, class_getInstanceVariable(backingClass, RLMObject.IncrementalStoreResourceIDIVar))
            },
            methodName: RLMObject.IncrementalStoreResourceIDProperty,
            toBackingClass: backingClass
        )
        self.addSetterBlock(
            { (`self`, _, value) -> Void in
                
                object_setIvar(self, class_getInstanceVariable(backingClass, RLMObject.IncrementalStoreResourceIDIVar), value)
            },
            methodName: RLMObject.IncrementalStoreResourceIDSetter,
            toBackingClass: backingClass
        )
    }
    
    private func synthesizePropertyWithName(propertyName: String, toBackingClass backingClass: AnyClass, getter: IMPValueConverterFunction? = nil, setter: IMPValueConverterFunction? = nil) -> (iVar: String, getter: String, setter: String) {
        
        let iVarName = "_\(propertyName)"
        
        let actualGetter: IMPGetterFunction
        if let getter = getter {
            
            actualGetter = { (`self`, _) -> AnyObject? in
                
                return getter(object_getIvar(self, class_getInstanceVariable(backingClass, iVarName)))
            }
        }
        else {
            
            actualGetter = { (`self`, _) -> AnyObject? in
                
                return object_getIvar(self, class_getInstanceVariable(backingClass, iVarName))
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
                
                object_setIvar(self, class_getInstanceVariable(backingClass, iVarName), setter(value))
            }
        }
        else {
            
            actualSetter = { (`self`, _, value) -> Void in
                
                object_setIvar(self, class_getInstanceVariable(backingClass, iVarName), value)
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
