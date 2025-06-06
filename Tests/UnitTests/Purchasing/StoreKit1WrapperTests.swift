//
//  StoreKit1WrapperTests.swift
//  PurchasesTests
//
//  Created by RevenueCat.
//  Copyright © 2019 RevenueCat. All rights reserved.
//

import Foundation
import Nimble
import StoreKit
import XCTest

@testable import RevenueCat

class StoreKit1WrapperTests: TestCase, StoreKit1WrapperDelegate {
    private var operationDispatcher: MockOperationDispatcher!
    private var paymentQueue: MockPaymentQueue!
    private var sandboxEnvironmentDetector: MockSandboxEnvironmentDetector!

    var diagnosticsTracker: DiagnosticsTrackerType?

    @available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *)
    var mockDiagnosticsTracker: MockDiagnosticsTracker {
        get throws {
            return try XCTUnwrap(self.diagnosticsTracker as? MockDiagnosticsTracker)
        }
    }

    private var wrapper: StoreKit1Wrapper!

    override func setUp() {
        super.setUp()

        self.operationDispatcher = .init()
        self.paymentQueue = .init()
        self.sandboxEnvironmentDetector = .init(isSandbox: true)

        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *) {
            self.diagnosticsTracker = MockDiagnosticsTracker()
        } else {
            self.diagnosticsTracker = nil
        }

        self.wrapper = StoreKit1Wrapper(paymentQueue: self.paymentQueue,
                                        operationDispatcher: self.operationDispatcher,
                                        observerMode: false,
                                        sandboxEnvironmentDetector: self.sandboxEnvironmentDetector,
                                        diagnosticsTracker: self.diagnosticsTracker)
        self.wrapper.delegate = self
    }

    var updatedTransactions: [SKPaymentTransaction] = []

    func storeKit1Wrapper(_ storeKit1Wrapper: StoreKit1Wrapper, updatedTransaction transaction: SKPaymentTransaction) {
        updatedTransactions.append(transaction)
    }

    var removedTransactions: [SKPaymentTransaction] = []

    func storeKit1Wrapper(_ storeKit1Wrapper: StoreKit1Wrapper, removedTransaction transaction: SKPaymentTransaction) {
        removedTransactions.append(transaction)
    }

    var promoPayment: SKPayment?
    var promoProduct: SK1Product?
    var shouldAddPromo = false
    func storeKit1Wrapper(_ storeKit1Wrapper: StoreKit1Wrapper,
                          shouldAddStorePayment payment: SKPayment,
                          for product: SK1Product) -> Bool {
        promoPayment = payment
        promoProduct = product
        return shouldAddPromo
    }

    var storefrontChangesCount: Int = 0
    func storeKit1WrapperDidChangeStorefront(_ storeKit1Wrapper: StoreKit1Wrapper) {
        storefrontChangesCount += 1
    }

    var storeKit1WrapperShouldShowPriceConsent = true

    var productIdentifiersWithRevokedEntitlements: [String]?

    func storeKit1Wrapper(
        _ storeKit1Wrapper: StoreKit1Wrapper,
        didRevokeEntitlementsForProductIdentifiers productIdentifiers: [String]
    ) {
        productIdentifiersWithRevokedEntitlements = productIdentifiers
    }

    func testObservesThePaymentQueue() {
        expect(self.paymentQueue.observers.count).to(equal(1))
    }

    func testAddsPaymentsToTheQueue() {
        let payment = SKPayment(product: SK1Product())

        wrapper?.add(payment)

        expect(self.paymentQueue.addedPayments).to(contain(payment))
    }

    func testCallsDelegateWhenTransactionsAreUpdated() {
        let payment = SKPayment(product: SK1Product())
        wrapper?.add(payment)

        let transaction = MockTransaction()
        transaction.mockPayment = payment

        wrapper?.paymentQueue(paymentQueue, updatedTransactions: [transaction])

        expect(self.updatedTransactions).to(contain(transaction))
    }

    func testCallsDelegateToProcessTransactionsOnWorkerThread() {
        let payment = SKPayment(product: SK1Product())
        self.wrapper.add(payment)

        let transactions = [
            Self.transaction(with: payment),
            Self.transaction(with: payment)
        ]

        self.wrapper.paymentQueue(self.paymentQueue, updatedTransactions: transactions)
        expect(self.operationDispatcher.invokedDispatchOnWorkerThread) == true
        expect(self.operationDispatcher.invokedDispatchOnWorkerThreadCount) == 1
    }

    #if !os(watchOS)
    func testCallsDelegateWhenPromoPurchaseIsAvailable() {
        let product = SK1Product()
        let payment = SKPayment(product: product)

        _ = self.wrapper?.paymentQueue(paymentQueue, shouldAddStorePayment: payment, for: product)
        expect(self.promoPayment).to(be(payment))
        expect(self.promoProduct).to(be(product))
    }

    func testPromoDelegateMethodPassesBackReturnValueFromOwnDelegate() {
        let product = SK1Product()
        let payment = SKPayment(product: product)

        self.shouldAddPromo = Bool.random()

        let result = self.wrapper?.paymentQueue(paymentQueue, shouldAddStorePayment: payment, for: product)

        expect(result).to(equal(self.shouldAddPromo))
    }
    #endif

    func testCallsDelegateOncePerTransaction() {
        let payment1 = SKPayment(product: SK1Product())
        wrapper?.add(payment1)

        let payment2 = SKPayment(product: SK1Product())
        wrapper?.add(payment2)

        let transaction1 = MockTransaction()
        transaction1.mockPayment = payment1
        let transaction2 = MockTransaction()
        transaction2.mockPayment = payment2

        wrapper?.paymentQueue(paymentQueue, updatedTransactions: [transaction1,
                                                                  transaction2])

        expect(self.updatedTransactions).to(contain([transaction1, transaction2]))
    }

    func testFinishesTransactions() {
        let payment = SKPayment(product: SK1Product())
        self.wrapper.add(payment)

        let transaction = Self.transaction(with: payment)

        self.wrapper.paymentQueue(self.paymentQueue, updatedTransactions: [transaction])

        waitUntil { completion in
            self.wrapper.finishTransaction(transaction, completion: completion)

            // `SKPaymentQueue.finishTransaction` is asynchronous, and this is how
            // it notifies of finished transactions.
            self.wrapper.paymentQueue(self.paymentQueue, removedTransactions: [transaction])
        }

        expect(self.paymentQueue.finishedTransactions).to(contain(transaction))
    }

    func testFinishesTransactionOnlyOnceWhenRequestedMultipleTimesConcurrently() {
        let payment = SKPayment(product: SK1Product())
        self.wrapper.add(payment)

        let transaction = Self.transaction(with: payment)

        self.wrapper.paymentQueue(self.paymentQueue, updatedTransactions: [transaction])

        var firstTransactionCompletionBlockedInvoked = false

        // 1. Finish transaction
        self.wrapper.finishTransaction(transaction) {
            firstTransactionCompletionBlockedInvoked = true
        }

        waitUntil { completion in
            // 2. Finish transaction again
            self.wrapper.finishTransaction(transaction, completion: completion)

            // 3. Notify of removed transaction
            self.wrapper.paymentQueue(self.paymentQueue, removedTransactions: [transaction])
        }

        // 4. Verify transaction is only finished once
        expect(self.paymentQueue.finishedTransactions).to(haveCount(1))
        expect(self.paymentQueue.finishedTransactions).to(contain(transaction))

        // 5. But both callbacks were invoked
        expect(firstTransactionCompletionBlockedInvoked) == true
    }

    func testCallsRemovedTransactionDelegateMethod() {
        let transaction1 = MockTransaction()
        transaction1.mockPayment = SKPayment(product: SK1Product())
        let transaction2 = MockTransaction()
        transaction2.mockPayment = SKPayment(product: SK1Product())

        wrapper?.paymentQueue(paymentQueue, removedTransactions: [transaction1, transaction2])

        expect(self.removedTransactions).to(contain([transaction1, transaction2]))
    }

    func testCallsStorefrontDidUpdateDelegateMethod() {
        wrapper?.paymentQueueDidChangeStorefront(self.paymentQueue)

        expect(self.storefrontChangesCount) == 1
    }

    func testDoesntAddObserverWithoutDelegate() {
        wrapper?.delegate = nil

        expect(self.paymentQueue.observers.count).to(equal(0))

        wrapper?.delegate = self

        expect(self.paymentQueue.observers.count).to(equal(1))

    }

    func testDidRevokeEntitlementsForProductIdentifiersCallsDelegateWithRightArguments() throws {
        guard #available(iOS 14.0, macOS 14.0, tvOS 14.0, watchOS 7.0, *) else { throw XCTSkip() }

        expect(self.productIdentifiersWithRevokedEntitlements).to(beNil())
        let revokedProductIdentifiers = [
            "mySuperProduct",
            "theOtherProduct"
        ]

        wrapper?.paymentQueue(paymentQueue, didRevokeEntitlementsForProductIdentifiers: revokedProductIdentifiers)
        expect(self.productIdentifiersWithRevokedEntitlements) == revokedProductIdentifiers
    }

    func testPaymentWithProductReturnsCorrectPayment() {
        guard let wrapper = wrapper else { fatalError("wrapper is not initialized!") }

        let productId = "mySuperProduct"
        let mockProduct = MockSK1Product(mockProductIdentifier: productId)
        let payment = wrapper.payment(with: mockProduct)
        expect(payment.productIdentifier) == productId
    }

    @available(macOS 10.14, *)
    func testPaymentWithProductSetsSimulatesAskToBuyInSandbox() {
        guard let wrapper = wrapper else { fatalError("wrapper is not initialized!") }

        let mockProduct = MockSK1Product(mockProductIdentifier: "mySuperProduct")

        StoreKit1Wrapper.simulatesAskToBuyInSandbox = false
        let payment1 = wrapper.payment(with: mockProduct)
        expect(payment1.simulatesAskToBuyInSandbox) == false

        StoreKit1Wrapper.simulatesAskToBuyInSandbox = true
        let payment2 = wrapper.payment(with: mockProduct)
        expect(payment2.simulatesAskToBuyInSandbox) == true
    }

    func testPaymentWithProductAndDiscountReturnsCorrectPaymentWithDiscount() throws {
        guard let wrapper = wrapper else { fatalError("wrapper is not initialized!") }

        let productId = "mySuperProduct"
        let discountId = "mySuperDiscount"

        let mockProduct = MockSK1Product(mockProductIdentifier: productId)
        let mockDiscount = MockPaymentDiscount(mockIdentifier: discountId)
        let payment = wrapper.payment(with: mockProduct, discount: mockDiscount)
        expect(payment.productIdentifier) == productId
        expect(payment.paymentDiscount) == mockDiscount
    }

    func testPaymentWithProductAndDiscountSetsSimulatesAskToBuyInSandbox() throws {
        guard let wrapper = wrapper else { fatalError("wrapper is not initialized!") }

        let mockProduct = MockSK1Product(mockProductIdentifier: "mySuperProduct")
        let mockDiscount = MockPaymentDiscount(mockIdentifier: "mySuperDiscount")

        StoreKit1Wrapper.simulatesAskToBuyInSandbox = false
        let payment1 = wrapper.payment(with: mockProduct, discount: mockDiscount)
        expect(payment1.simulatesAskToBuyInSandbox) == false

        StoreKit1Wrapper.simulatesAskToBuyInSandbox = true
        let payment2 = wrapper.payment(with: mockProduct)
        expect(payment2.simulatesAskToBuyInSandbox) == true
    }

    func testUpdatedTransactionsDoesNotLogWarningForLowNumberOfTransactions() {
        self.wrapper.paymentQueue(self.paymentQueue, updatedTransactions: [Self.randomTransaction()])

        self.logger.verifyMessageWasNotLogged("This high number is unexpected")
    }

    func testUpdatedTransactionsLogsWarningWhenSendingTooManyTransactions() {
        let payment = SKPayment(product: .init())
        let transactions = (0..<110).map { _ in
            Self.transaction(with: payment)
        }

        self.wrapper.paymentQueue(self.paymentQueue, updatedTransactions: transactions)

        self.logger.verifyMessageWasLogged(Strings.storeKit.sk1_payment_queue_too_many_transactions(
            count: transactions.count,
            isSandbox: self.sandboxEnvironmentDetector.isSandbox
        ),
                                      level: .warn)
    }

#if os(iOS) || targetEnvironment(macCatalyst) || VISION_OS
    func testShouldShowPriceConsentWiredUp() throws {
        guard #available(iOS 13.4, macCatalyst 13.4, *) else {
            throw XCTSkip()
        }
        expect(self.storeKit1WrapperShouldShowPriceConsent) == true

        self.storeKit1WrapperShouldShowPriceConsent = false

        let consentStatuses = self.paymentQueue.simulatePaymentQueueShouldShowPriceConsent()
        expect(consentStatuses) == [false]
    }
#endif

}

@available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *)
extension StoreKit1WrapperTests {

    func testDoesNotTrackDiagnosticsWhenTransactionsUpdatedAreEmpty() throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        wrapper?.paymentQueue(paymentQueue, updatedTransactions: [])

        let mockDiagnosticsTracker = try XCTUnwrap(self.mockDiagnosticsTracker)
        expect(mockDiagnosticsTracker.trackedAppleTransactionQueueReceivedParams.value).to(beEmpty())
    }

    func testTracksDiagnosticsWhenTransactionsAreUpdated() throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        let product0 = MockSK1Product(mockProductIdentifier: "product_id_0",
                                      mockSubscriptionGroupIdentifier: "group_0")
        let payment0 = SKPayment(product: product0)
        wrapper?.add(payment0)

        let transaction0 = MockTransaction()
        transaction0.mockState = .purchasing
        transaction0.mockPayment = payment0

        let product1 = MockSK1Product(mockProductIdentifier: "product_id_1",
                                      mockSubscriptionGroupIdentifier: "group_1")
        let payment1 = SKPayment(product: product1)
        wrapper?.add(payment1)

        let transaction1 = MockTransaction()
        transaction1.mockState = .restored
        transaction1.mockPayment = payment1

        let product2 = MockSK1Product(mockProductIdentifier: "product_id_2",
                                      mockSubscriptionGroupIdentifier: "group_2")
        let payment2 = SKPayment(product: product2)
        wrapper?.add(payment2)

        let transaction2 = MockTransaction()
        transaction2.mockState = .failed
        transaction2.mockPayment = payment2

        let error2 = NSError(domain: SKErrorDomain, code: SKError.paymentNotAllowed.rawValue)
        transaction2.mockError = error2

        paymentQueue.stubbedStorefront = MockSK1Storefront(countryCode: "USA")

        wrapper?.paymentQueue(paymentQueue, updatedTransactions: [transaction0, transaction1, transaction2])

        let mockDiagnosticsTracker = try XCTUnwrap(self.mockDiagnosticsTracker)
        expect(mockDiagnosticsTracker.trackedAppleTransactionQueueReceivedParams.value.count) == 3

        let params0 = mockDiagnosticsTracker.trackedAppleTransactionQueueReceivedParams.value[0]
        expect(params0.productId) == "product_id_0"
        expect(params0.paymentDiscountId) == nil
        expect(params0.transactionState) == "PURCHASING"
        expect(params0.errorMessage) == nil
        expect(params0.storefront) == "USA"

        let params1 = mockDiagnosticsTracker.trackedAppleTransactionQueueReceivedParams.value[1]
        expect(params1.productId) == "product_id_1"
        expect(params1.paymentDiscountId) == nil
        expect(params1.transactionState) == "RESTORED"
        expect(params1.errorMessage) == nil
        expect(params1.storefront) == "USA"

        let params2 = mockDiagnosticsTracker.trackedAppleTransactionQueueReceivedParams.value[2]
        expect(params2.productId) == "product_id_2"
        expect(params2.paymentDiscountId) == nil
        expect(params2.transactionState) == "FAILED"
        expect(params2.errorMessage) == error2.localizedDescription
        expect(params2.storefront) == "USA"
    }
}

private extension StoreKit1WrapperTests {

    static func transaction(with: SKPayment) -> MockTransaction {
        let transaction = MockTransaction()
        transaction.mockPayment = SKPayment(product: SK1Product())

        return transaction
    }

    static func randomTransaction() -> MockTransaction {
        return Self.transaction(with: .init(product: .init()))
    }

}
