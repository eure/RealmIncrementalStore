//
//  RealmIncrementalStoreMetadata.swift
//  RealmIncrementalStore
//
//  Created by John Estropia on 2016/02/18.
//  Copyright © 2016年 John Estropia. All rights reserved.
//

import UIKit
import Realm


// MARK: - RealmIncrementalStoreMetadata

@objc
internal final class _RealmIncrementalStoreMetadata: RLMObject {
    
    @objc dynamic var _metadataVersion: NSNumber = 1
    @objc dynamic var _versionHashes: NSData = NSData()
    
    override class func primaryKey() -> String? {
        
        return "_metadataVersion"
    }
    
    
    // MARK: Internal
    
    @nonobjc
    internal class var versionHashesKey: String {
        
        return "_versionHashes"
    }
    
    @nonobjc
    internal class var currentPrimaryKeyValue: Int {
        
        return 1
    }
}
