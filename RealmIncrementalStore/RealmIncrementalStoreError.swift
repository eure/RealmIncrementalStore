//
//  RealmIncrementalStoreError.swift
//  RealmIncrementalStore
//
//  Created by John Estropia on 2016/02/18.
//  Copyright © 2016年 John Estropia. All rights reserved.
//

import Foundation

public enum RealmIncrementalStoreError: ErrorType {

    case InvalidState
    case PersistentStoreURLMissing
    case PersistentStoreURLInvalid
    case PersistentStoreCorrupted
    case InvalidDataTypeInDataModel
}
