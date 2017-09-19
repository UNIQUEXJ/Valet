//
//  Valet.swift
//  Valet
//
//  Created by Dan Federman and Eric Muller on 9/17/17.
//  Copyright © 2017 Square, Inc.
//
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

/// Reads and writes keychain elements.
public final class Valet: NSObject, KeychainQueryConvertible {
    
    // MARK: Flavor
    
    public enum Flavor {
        /// Reads and writes keychain elements that do not sync to other devices.
        case vanilla(Accessibility)
        /// Reads and writes keychain elements that are synchronized with iCloud
        case synchronizable(SynchronizableAccessibility)
    }
    
    // MARK: Public Class Methods
    
    /// - parameter identifier: A non-empty string that uniquely identifies a Valet.
    /// - parameter flavor: A description of the Valet's capabilities.
    /// - returns: A Valet that reads/writes keychain elements with the desired accessibility.
    public class func valet(with identifier: Identifier, of flavor: Flavor) -> Valet {
        let key: NSString
        switch flavor {
        case let .vanilla(accessibility):
            key = Service.standard(identifier, accessibility, .vanilla).description as NSString
            
        case let .synchronizable(synchronizableAccessibility):
            key = Service.standard(identifier, synchronizableAccessibility.accessibility, .synchronizable).description as NSString
        }
        
        if let existingValet = identifierToValetMap.object(forKey: key) {
            return existingValet
            
        } else {
            let valet = Valet(identifier: identifier, flavor: flavor)
            identifierToValetMap.setObject(valet, forKey: key)
            return valet
        }
    }
    
    /// - parameter identifier: A non-empty string that must correspond with the value for keychain-access-groups in your Entitlements file.
    /// - parameter flavor: A description of the Valet's capabilities.
    /// - returns: A Valet that reads/writes keychain elements that can be shared across applications written by the same development team.
    public class func sharedAccessGroupValet(with identifier: Identifier, of flavor: Flavor) -> Valet {
        let key: NSString
        switch flavor {
        case let .vanilla(accessibility):
            key = Service.standard(identifier, accessibility, .vanilla).description as NSString
            
        case let .synchronizable(synchronizableAccessibility):
            key = Service.standard(identifier, synchronizableAccessibility.accessibility, .synchronizable).description as NSString
        }
        
        if let existingValet = identifierToValetMap.object(forKey: key) {
            return existingValet
            
        } else {
            let valet = Valet(sharedAccess: identifier, flavor: flavor)
            identifierToValetMap.setObject(valet, forKey: key)
            return valet
        }
    }
    
    // MARK: Equatable
    
    /// - returns: `true` if lhs and rhs both read from and write to the same sandbox within the keychain.
    public static func ==(lhs: Valet, rhs: Valet) -> Bool {
        return lhs.service == rhs.service
    }
    
    // MARK: Private Class Properties
    
    private static let identifierToValetMap = NSMapTable<NSString, Valet>.strongToWeakObjects()
    
    // MARK: Initialization
    
    @available(*, deprecated)
    public override init() {
        fatalError("Do not use this initializer")
    }
    
    private init(identifier: Identifier, flavor: Flavor) {
        switch flavor {
        case let .vanilla(accessibility):
            service = .standard(identifier, accessibility, .vanilla)
            self.accessibility = accessibility
            self.flavor = flavor
        case let .synchronizable(synchronizableAccessibility):
            service = .standard(identifier, synchronizableAccessibility.accessibility, .synchronizable)
            accessibility = synchronizableAccessibility.accessibility
            self.flavor = flavor
        }
        
        keychainQuery = service.baseQuery
        self.identifier = identifier
    }
    
    private init(sharedAccess identifier: Identifier, flavor: Flavor) {
        switch flavor {
        case let .vanilla(accessibility):
            service = .sharedAccessGroup(identifier, accessibility, .vanilla)
            self.accessibility = accessibility
            self.flavor = flavor
            
        case let .synchronizable(synchronizableAccessibility):
            service = .sharedAccessGroup(identifier, synchronizableAccessibility.accessibility, .synchronizable)
            accessibility = synchronizableAccessibility.accessibility
            self.flavor = flavor
        }
        
        keychainQuery = service.baseQuery
        self.identifier = identifier
    }
    
    // MARK: KeychainQueryConvertible
    
    public let keychainQuery: [String : AnyHashable]
    
    // MARK: Hashable
    
    public override var hashValue: Int {
        return service.description.hashValue
    }
    
    // MARK: Public Properties
    
    public let accessibility: Accessibility
    public let identifier: Identifier
    public let flavor: Flavor
    
    // MARK: Public Methods
    
    /// - returns: `true` if the keychain is accessible for reading and writing, `false` otherwise.
    /// - note: Determined by writing a value to the keychain and then reading it back out.
    public func canAccessKeychain() -> Bool {
        return execute(in: lock) {
            return Keychain.canAccess(attributes: keychainQuery)
        }
    }
    
    /// - parameter object: A Data value to be inserted into the keychain.
    /// - parameter key: A Key that can be used to retrieve the `object` from the keychain.
    /// - returns: `false` if the keychain is not accessible.
    @discardableResult
    public func set(object: Data, for key: Key) -> Bool {
        return execute(in: lock) {
            switch Keychain.set(object: object, for: key, options: keychainQuery) {
            case .success:
                return true
                
            case .error:
                return false
            }
        }
    }
    
    /// - parameter key: A Key used to retrieve the desired object from the keychain.
    /// - returns: The data currently stored in the keychain for the provided key. Returns `nil` if no object exists in the keychain for the specified key, or if the keychain is inaccessible.
    public func object(for key: Key) -> Data? {
        return execute(in: lock) {
            switch Keychain.object(for: key, options: keychainQuery) {
            case let .success(data):
                return data
                
            case .error:
                return nil
            }
        }
    }
    
    /// - parameter key: The key to look up in the keychain.
    /// - returns: `true` if a value has been set for the given key, `false` otherwise.
    public func containsObject(for key: Key) -> Bool {
        return execute(in: lock) {
            switch Keychain.containsObject(for: key, options: keychainQuery) {
            case .success:
                return true
            case .error:
                return false
            }
        }
    }
    
    /// - parameter string: A String value to be inserted into the keychain.
    /// - parameter key: A Key that can be used to retrieve the `string` from the keychain.
    /// @return NO if the keychain is not accessible.
    @discardableResult
    public func set(string: String, for key: Key) -> Bool {
        return execute(in: lock) {
            switch Keychain.set(string: string, for: key, options: keychainQuery) {
            case .success:
                return true
                
            case .error:
                return false
            }
        }
    }
    
    /// - parameter key: A Key used to retrieve the desired object from the keychain.
    /// - returns: The string currently stored in the keychain for the provided key. Returns `nil` if no string exists in the keychain for the specified key, or if the keychain is inaccessible.
    public func string(for key: Key) -> String? {
        return execute(in: lock) {
            switch Keychain.string(for: key, options: keychainQuery) {
            case let .success(data):
                return data
                
            case .error:
                return nil
            }
        }
    }
    
    /// - returns: The set of all (String) keys currently stored in this Valet instance.
    public func allKeys() -> Set<String> {
        return execute(in: lock) {
            switch Keychain.allKeys(options: keychainQuery) {
            case let .success(allKeys):
                return allKeys
                
            case .error:
                return Set()
            }
        }
    }
    
    /// Removes a key/object pair from the keychain.
    /// - returns: `false` if the keychain is not accessible.
    @discardableResult
    public func removeObject(for key: Key) -> Bool {
        return execute(in: lock) {
            switch Keychain.removeObject(for: key, options: keychainQuery) {
            case .success:
                return true
                
            case .error:
                return false
            }
        }
    }
    
    /// Removes all key/object pairs accessible by this Valet instance from the keychain.
    /// - returns: `false` if the keychain is not accessible.
    @discardableResult
    public func removeAllObjects() -> Bool {
        return execute(in: lock) {
            switch Keychain.removeAllObjects(matching: keychainQuery) {
            case .success:
                return true
                
            case .error:
                return false
            }
        }
    }
    
    /// Migrates objects matching the input query into the receiving Valet instance.
    /// - parameter query: The query with which to retrieve existing keychain data via a call to SecItemCopyMatching.
    /// - parameter removeOnCompletion: If `true`, the migrated data will be removed from the keychain if the migration succeeds.
    /// - returns: Whether the migration succeeded or failed.
    /// - note: The keychain is not modified if a failure occurs.
    public func migrateObjects(matching query: [String : AnyHashable], removeOnCompletion: Bool) -> MigrationResult {
        return execute(in: lock) {
            return Keychain.migrateObjects(matching: query, into: keychainQuery, removeOnCompletion: removeOnCompletion)
        }
    }
    
    /// Migrates objects matching the vended keychain query into the receiving Valet instance.
    /// - parameter keychain: An objects whose vended keychain query is used to retrieve existing keychain data via a call to SecItemCopyMatching.
    /// - parameter removeOnCompletion: If `true`, the migrated data will be removed from the keychfain if the migration succeeds.
    /// - returns: Whether the migration succeeded or failed.
    /// - note: The keychain is not modified if a failure occurs.
    public func migrateObjects(from keychain: KeychainQueryConvertible, removeOnCompletion: Bool) -> MigrationResult {
        return migrateObjects(matching: keychain.keychainQuery, removeOnCompletion: removeOnCompletion)
    }
    
    // MARK: Private Properties
    
    private let service: Service
    private let lock = NSLock()
}
