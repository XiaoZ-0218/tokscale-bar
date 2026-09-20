import XCTest
@testable import TokscaleBar

final class SubscriptionStoreTests: XCTestCase {
    /// 每个测试一个全新 suite，互不影响也不碰真实 UserDefaults。
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SubscriptionStoreTests.\(UUID().uuidString)")!
    }

    private func sample(name: String = "Claude Pro") -> Subscription {
        Subscription(name: name, price: 20, currency: .usd, billingDay: 15, keywords: ["claude"])
    }

    func testAddPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let store = SubscriptionStore(defaults: defaults)
        let sub = sample()
        store.add(sub)

        let reloaded = SubscriptionStore(defaults: defaults)
        XCTAssertEqual(reloaded.subscriptions, [sub])
    }

    func testUpdateWritesNewValues() {
        let defaults = makeDefaults()
        let store = SubscriptionStore(defaults: defaults)
        var sub = sample()
        store.add(sub)
        sub.price = 40
        sub.billingDay = 1
        store.update(sub)

        let reloaded = SubscriptionStore(defaults: defaults)
        XCTAssertEqual(reloaded.subscriptions.first?.price, 40)
        XCTAssertEqual(reloaded.subscriptions.first?.billingDay, 1)
    }

    func testRemoveDeletes() {
        let defaults = makeDefaults()
        let store = SubscriptionStore(defaults: defaults)
        let sub = sample()
        store.add(sub)
        store.remove(id: sub.id)

        XCTAssertEqual(SubscriptionStore(defaults: defaults).subscriptions, [])
    }

    /// persists=false（mock / render-png）不得写盘。
    func testNonPersistingStoreWritesNothing() {
        let defaults = makeDefaults()
        let store = SubscriptionStore(defaults: defaults)
        store.persists = false
        store.add(sample())

        XCTAssertEqual(SubscriptionStore(defaults: defaults).subscriptions, [])
    }

    /// replace 是 mock 通道：改内存，不落盘。
    func testReplaceSwapsInMemoryOnly() {
        let defaults = makeDefaults()
        let store = SubscriptionStore(defaults: defaults)
        store.add(sample(name: "Real"))
        store.replace([sample(name: "Mock")])

        XCTAssertEqual(store.subscriptions.map(\.name), ["Mock"])
        XCTAssertEqual(SubscriptionStore(defaults: defaults).subscriptions.map(\.name), ["Real"])
    }

    /// 磁盘上的坏数据不得 crash，按空列表处理。
    func testCorruptDataLoadsEmpty() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "subscriptions.v1")
        XCTAssertEqual(SubscriptionStore(defaults: defaults).subscriptions, [])
    }
}
