//
//  KeychainAccess.swift
//  iina
//
//  Created by Collider LI on 25/8/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation

class KeychainAccess {

  enum KeychainError: Error {
    case noResult
    case unhandledError(message: String)
    case unexpectedData
  }

  struct ServiceName: RawRepresentable {
    typealias RawValue = String
    var rawValue: String
    var legacyRawValues: [String]

    init(rawValue: String) {
      self.rawValue = rawValue
      self.legacyRawValues = []
    }

    init(rawValue: String, legacyRawValues: [String]) {
      self.rawValue = rawValue
      self.legacyRawValues = legacyRawValues
    }

    init(_ rawValue: String) {
      self.init(rawValue: rawValue)
    }

    static let openSubAccount = ServiceName(
      rawValue: "Rawya OpenSubtitles Account",
      legacyRawValues: ["IINA OpenSubtitles Account"]
    )
    static let httpAuth = ServiceName(
      rawValue: "Rawya Saved HTTP Password",
      legacyRawValues: ["IINA Saved HTTP Password"]
    )
  }

  static func write(username: String, password: String, forService serviceName: ServiceName, server: String? = nil, port: Int? = nil) throws {
    let status: OSStatus

    if let _ = try? readExact(username: username,
                              serviceRawValue: serviceName.rawValue,
                              server: server,
                              port: port) {

      // if password exists, try to update the password
      var query: [String: Any] = [kSecAttrService as String: serviceName.rawValue]
      if let server = server { query[kSecAttrServer as String] = server }
      if let port = port { query[kSecAttrPort as String] = port }
      query[kSecClass as String] = server == nil && port == nil ? kSecClassGenericPassword : kSecClassInternetPassword

      // create attributes for updating
      let passwordData = password.data(using: String.Encoding.utf8)!
      let attributes: [String: Any] = [kSecAttrAccount as String: username,
                                       kSecValueData as String: passwordData]
      // update
      status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

    } else {

      // try to write the password
      var query: [String: Any] = [kSecAttrService as String: serviceName.rawValue,
                                  kSecAttrLabel as String: serviceName.rawValue,
                                  kSecAttrAccount as String: username,
                                  kSecValueData as String: password.data(using: .utf8)!]
      if let server = server { query[kSecAttrServer as String] = server }
      if let port = port { query[kSecAttrPort as String] = port }
      query[kSecClass as String] = server == nil && port == nil ? kSecClassGenericPassword : kSecClassInternetPassword

      status = SecItemAdd(query as CFDictionary, nil)
    }

    try check(status)
    for legacyRawValue in serviceName.legacyRawValues {
      try? deleteExact(username: username,
                       serviceRawValue: legacyRawValue,
                       server: server,
                       port: port)
    }
  }

  static func read(username: String?, forService serviceName: ServiceName, server: String? = nil, port: Int? = nil) throws -> (username: String, password: String) {
    do {
      return try readExact(username: username,
                           serviceRawValue: serviceName.rawValue,
                           server: server,
                           port: port)
    } catch KeychainError.noResult {
      for legacyRawValue in serviceName.legacyRawValues {
        guard let credentials = try? readExact(username: username,
                                               serviceRawValue: legacyRawValue,
                                               server: server,
                                               port: port) else { continue }
        try write(username: credentials.username,
                  password: credentials.password,
                  forService: serviceName,
                  server: server,
                  port: port)
        return credentials
      }
      throw KeychainError.noResult
    }
  }

  private static func readExact(username: String?,
                                serviceRawValue: String,
                                server: String?,
                                port: Int?) throws -> (username: String, password: String) {
    var query: [String: Any] = [kSecAttrService as String: serviceRawValue,
                                kSecMatchLimit as String: kSecMatchLimitOne,
                                kSecReturnAttributes as String: true,
                                kSecReturnData as String: true]
    if let username = username { query[kSecAttrAccount as String] = username }
    if let server = server { query[kSecAttrServer as String] = server }
    if let port = port { query[kSecAttrPort as String] = port }

    query[kSecClass as String] = server == nil && port == nil ? kSecClassGenericPassword : kSecClassInternetPassword

    // initiate the search
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    try check(status)

    // get data
    guard let existingItem = item as? [String : Any],
      let passwordData = existingItem[kSecValueData as String] as? Data,
      let password = String(data: passwordData, encoding: String.Encoding.utf8),
      let account = existingItem[kSecAttrAccount as String] as? String
      else {
        throw KeychainError.unexpectedData
    }
    return (account, password)
  }

  static func delete(username: String? = nil,
                     forService serviceName: ServiceName,
                     server: String? = nil,
                     port: Int? = nil) throws {
    try deleteExact(username: username,
                    serviceRawValue: serviceName.rawValue,
                    server: server,
                    port: port)
    for legacyRawValue in serviceName.legacyRawValues {
      try deleteExact(username: username,
                      serviceRawValue: legacyRawValue,
                      server: server,
                      port: port)
    }
  }

  private static func deleteExact(username: String?,
                                  serviceRawValue: String,
                                  server: String?,
                                  port: Int?) throws {
    var query: [String: Any] = [kSecAttrService as String: serviceRawValue]
    if let username = username { query[kSecAttrAccount as String] = username }
    if let server = server { query[kSecAttrServer as String] = server }
    if let port = port { query[kSecAttrPort as String] = port }
    query[kSecClass as String] = server == nil && port == nil
      ? kSecClassGenericPassword
      : kSecClassInternetPassword
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      let message = (SecCopyErrorMessageString(status, nil) as String?) ?? ""
      throw KeychainError.unhandledError(message: message)
    }
  }

  private static func check(_ status: OSStatus) throws {
    guard status != errSecItemNotFound else { throw KeychainError.noResult }
    guard status == errSecSuccess else {
      let message = (SecCopyErrorMessageString(status, nil) as String?) ?? ""
      throw KeychainError.unhandledError(message: message)
    }
  }

}
