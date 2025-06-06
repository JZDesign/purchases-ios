//
//  Copyright RevenueCat Inc. All Rights Reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://opensource.org/licenses/MIT
//
//  CustomerInfoResponse.swift
//
//  Created by Nacho Soto on 4/12/22.

import Foundation

/// The representation of ``CustomerInfo`` as sent by the backend.
/// Thanks to `@IgnoreHashable`, only `subscriber` is used for equality / hash.
struct CustomerInfoResponse {

    var subscriber: Subscriber

    @IgnoreHashable
    var requestDate: Date
    @IgnoreEncodable @IgnoreHashable
    var rawData: [String: Any]

}

extension CustomerInfoResponse {

    struct Subscriber {

        var originalAppUserId: String
        @IgnoreDecodeErrors<URL?>
        var managementUrl: URL?
        var originalApplicationVersion: String?
        var originalPurchaseDate: Date?
        var firstSeen: Date
        @DefaultDecodable.EmptyDictionary
        var subscriptions: [String: Subscription]
        @DefaultDecodable.EmptyDictionary
        var nonSubscriptions: [String: [Transaction]]
        @DefaultDecodable.EmptyDictionary
        var entitlements: [String: Entitlement]

    }

    struct Subscription {

        @IgnoreDecodeErrors<PeriodType>
        var periodType: PeriodType
        var purchaseDate: Date
        var originalPurchaseDate: Date?
        var expiresDate: Date?
        @IgnoreDecodeErrors<Store>
        var store: Store
        @DefaultDecodable.False
        var isSandbox: Bool
        var unsubscribeDetectedAt: Date?
        var billingIssuesDetectedAt: Date?
        @IgnoreDecodeErrors<PurchaseOwnershipType>
        var ownershipType: PurchaseOwnershipType
        var productPlanIdentifier: String?
        var metadata: [String: String]?
        var gracePeriodExpiresDate: Date?
        var refundedAt: Date?
        var storeTransactionId: String?

        var displayName: String?

        /// Price paid for the subscription
        var price: PurchasePaidPrice?

        /// Management URL for the purchase
        var managementUrl: URL?
    }

    struct PurchasePaidPrice {
        let currency: String
        let amount: Double
    }

    struct Transaction {

        var purchaseDate: Date
        var originalPurchaseDate: Date?
        var transactionIdentifier: String?
        var storeTransactionIdentifier: String?
        @IgnoreDecodeErrors<Store>
        var store: Store
        var isSandbox: Bool
        var displayName: String?

    }

    struct Entitlement {

        var expiresDate: Date?
        var productIdentifier: String
        var purchaseDate: Date?

        @IgnoreEncodable @IgnoreHashable
        var rawData: [String: Any]

    }

}

// MARK: - Codable

extension CustomerInfoResponse.Subscriber: Codable, Hashable {}
extension CustomerInfoResponse.Subscription: Codable, Hashable {}
extension CustomerInfoResponse.PurchasePaidPrice: Codable, Hashable {}

extension CustomerInfoResponse.Entitlement: Hashable {}
extension CustomerInfoResponse.Entitlement: Encodable {}
extension CustomerInfoResponse.Entitlement: Decodable {

    // Note: this must be manually implemented because of the custom call to `decodeRawData`
    // which can't be abstracted as a property wrapper.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.expiresDate = try container.decodeIfPresent(Date.self, forKey: .expiresDate)
        self.productIdentifier = try container.decode(String.self, forKey: .productIdentifier)
        self.purchaseDate = try container.decodeIfPresent(Date.self, forKey: .purchaseDate)

        self.rawData = decoder.decodeRawData()
    }

}

extension CustomerInfoResponse.Transaction: Codable, Hashable {

    private enum CodingKeys: String, CodingKey {

        case purchaseDate
        case originalPurchaseDate
        case transactionIdentifier = "id"
        case storeTransactionIdentifier = "storeTransactionId"
        case store
        case isSandbox
        case displayName

    }

}

extension CustomerInfoResponse: Codable {

    // Note: this must be manually implemented because of the custom call to `decodeRawData`
    // which can't be abstracted as a property wrapper.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.requestDate = try container.decode(Date.self, forKey: .requestDate)
        self.subscriber = try container.decode(Subscriber.self, forKey: .subscriber)

        self.rawData = decoder.decodeRawData()
    }

}

extension CustomerInfoResponse: Equatable, Hashable {}

// MARK: - Extensions

extension CustomerInfoResponse.Subscriber {

    init(
        originalAppUserId: String,
        managementUrl: URL? = nil,
        originalApplicationVersion: String? = nil,
        originalPurchaseDate: Date? = nil,
        firstSeen: Date,
        subscriptions: [String: CustomerInfoResponse.Subscription],
        nonSubscriptions: [String: [CustomerInfoResponse.Transaction]],
        entitlements: [String: CustomerInfoResponse.Entitlement]
    ) {
        self.originalAppUserId = originalAppUserId
        self.managementUrl = managementUrl
        self.originalApplicationVersion = originalApplicationVersion
        self.originalPurchaseDate = originalPurchaseDate
        self.firstSeen = firstSeen
        self.subscriptions = subscriptions
        self.nonSubscriptions = nonSubscriptions
        self.entitlements = entitlements
    }

}

extension CustomerInfoResponse.Transaction {

    init(
        purchaseDate: Date,
        originalPurchaseDate: Date?,
        transactionIdentifier: String?,
        storeTransactionIdentifier: String?,
        store: Store,
        isSandbox: Bool
    ) {
        self.purchaseDate = purchaseDate
        self.originalPurchaseDate = originalPurchaseDate
        self.transactionIdentifier = transactionIdentifier
        self.storeTransactionIdentifier = storeTransactionIdentifier
        self.store = store
        self.isSandbox = isSandbox
    }

    var asSubscription: CustomerInfoResponse.Subscription {
        return .init(purchaseDate: self.purchaseDate,
                     originalPurchaseDate: self.originalPurchaseDate,
                     store: self.store,
                     isSandbox: self.isSandbox)
    }

}

extension CustomerInfoResponse.Subscription {

    init(
        periodType: PeriodType = .defaultValue,
        purchaseDate: Date,
        originalPurchaseDate: Date? = nil,
        expiresDate: Date? = nil,
        store: Store = .defaultValue,
        isSandbox: Bool,
        unsubscribeDetectedAt: Date? = nil,
        billingIssuesDetectedAt: Date? = nil,
        ownershipType: PurchaseOwnershipType = .defaultValue,
        storeTransactionId: String? = nil
    ) {
        self.periodType = periodType
        self.purchaseDate = purchaseDate
        self.originalPurchaseDate = originalPurchaseDate
        self.expiresDate = expiresDate
        self.store = store
        self.isSandbox = isSandbox
        self.unsubscribeDetectedAt = unsubscribeDetectedAt
        self.billingIssuesDetectedAt = billingIssuesDetectedAt
        self.ownershipType = ownershipType
        self.storeTransactionId = storeTransactionId
    }

    var asTransaction: CustomerInfoResponse.Transaction {
        return .init(purchaseDate: self.purchaseDate,
                     originalPurchaseDate: self.originalPurchaseDate,
                     transactionIdentifier: nil,
                     storeTransactionIdentifier: nil,
                     store: self.store,
                     isSandbox: self.isSandbox)
    }

}

extension CustomerInfoResponse.Subscriber {

    var allTransactionsByProductId: [String: CustomerInfoResponse.Transaction] {
        return self.allPurchasesByProductId.mapValues { $0.asTransaction }
    }

    // This returns objects of type `Subscription` but also includes non-subscriptions
    var allPurchasesByProductId: [String: CustomerInfoResponse.Subscription] {
        let subscriptions = self.subscriptions
        let latestNonSubscriptionTransactionsByProductId = self.nonSubscriptions
            .compactMapValues { $0.last }
            .mapValues { $0.asSubscription }

        return subscriptions + latestNonSubscriptionTransactionsByProductId
    }

}
