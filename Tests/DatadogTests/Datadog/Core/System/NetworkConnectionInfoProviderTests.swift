/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import Network
import SystemConfiguration
@testable import Datadog

class NetworkConnectionInfoProviderTests: XCTestCase {
    /// Constantly pulls the `NetworkConnectionInfo` from given provider and fulfils the expectation if value is received.
    private func pullNetworkConnectionInfo(
        from provider: NetworkConnectionInfoProvider,
        on queue: DispatchQueue,
        thenFulfill expectation: XCTestExpectation
    ) {
        if provider.current != nil {
            expectation.fulfill()
        } else {
            queue.async { self.pullNetworkConnectionInfo(from: provider, on: queue, thenFulfill: expectation) }
        }
    }

    // MARK: - iOS 12+

    func testNWPathNetworkConnectionInfoProviderGivesValue() {
        if #available(iOS 12.0, tvOS 12, *) {
            let provider = NetworkConnectionInfoProvider(
                wrappedProvider: NWPathNetworkConnectionInfoProvider()
            )

            pullNetworkConnectionInfo(
                from: provider,
                on: DispatchQueue(label: "com.datadoghq.pulling-NWPathNetworkConnectionInfoProvider", target: .global(qos: .utility)),
                thenFulfill: expectation(description: "Receive `NetworkConnectionInfo` from `NWPathNetworkConnectionInfoProvider`")
            )

            waitForExpectations(timeout: 1, handler: nil)
        }
    }

    func testNWPathNetworkConnectionInfoProviderCanBeSafelyAccessedFromConcurrentThreads() {
        if #available(iOS 12.0, tvOS 12, *) {
            let provider = NetworkConnectionInfoProvider(
                wrappedProvider: NWPathNetworkConnectionInfoProvider()
            )

            DispatchQueue.concurrentPerform(iterations: 1_000) { _ in
                _ = provider.current
            }
        }
    }

    func testNWPathMonitorHandling() {
        if #available(iOS 12.0, tvOS 12, *) {
            weak var nwPathMonitorWeakReference: NWPathMonitor?

            autoreleasepool {
                let nwPathMonitor = NWPathMonitor()
                _ = NWPathNetworkConnectionInfoProvider(monitor: nwPathMonitor)
                nwPathMonitorWeakReference = nwPathMonitor
                XCTAssertNotNil(nwPathMonitor.queue, "`NWPathMonitor` is started with synchronization queue")
            }

            Thread.sleep(forTimeInterval: 0.5)

            XCTAssertNil(nwPathMonitorWeakReference, "`NWPathMonitor` is deallocated with `NWPathNetworkConnectionInfoProvider`")
        }
    }

    // MARK: - iOS 11

    func testiOS11NetworkConnectionInfoProviderGivesValue() {
        let provider = NetworkConnectionInfoProvider(
            wrappedProvider: iOS11NetworkConnectionInfoProvider()
        )

        pullNetworkConnectionInfo(
            from: provider,
            on: DispatchQueue(label: "com.datadoghq.pulling-iOS11NetworkConnectionInfoProvider", target: .global(qos: .utility)),
            thenFulfill: expectation(description: "Receive `NetworkConnectionInfo` from `iOS11NetworkConnectionInfoProvider`")
        )

        waitForExpectations(timeout: 1, handler: nil)
    }

    func testiOS11NetworkConnectionInfoProviderCanBeSafelyAccessedFromConcurrentThreads() {
        let provider = NetworkConnectionInfoProvider(
            wrappedProvider: iOS11NetworkConnectionInfoProvider()
        )

        DispatchQueue.concurrentPerform(iterations: 1_000) { _ in
            _ = provider.current
        }
    }
}

class NetworkConnectionInfoConversionTests: XCTestCase {
    typealias Reachability = NetworkConnectionInfo.Reachability
    typealias Interface = NetworkConnectionInfo.Interface

    func testNWPathStatus() {
        if #available(iOS 12.0, tvOS 12, *) {
            XCTAssertEqual(Reachability(.satisfied), .yes)
            XCTAssertEqual(Reachability(.unsatisfied), .no)
            XCTAssertEqual(Reachability(.requiresConnection), .maybe)
        }
    }

    func testNWInterface() {
        if #available(iOS 12.0, tvOS 12, *) {
            XCTAssertEqual(Interface(.wifi), .wifi)
            XCTAssertEqual(Interface(.wiredEthernet), .wiredEthernet)
            XCTAssertEqual(Interface(.loopback), .loopback)
            XCTAssertEqual(Interface(.cellular), .cellular)
            XCTAssertEqual(Interface(.other), .other)
        }
    }

    func testSCReachability() {
        let reachable = SCNetworkReachabilityFlags(arrayLiteral: .reachable)
        XCTAssertEqual(Reachability(reachable), .yes)

        let unreachable = SCNetworkReachabilityFlags(arrayLiteral: .connectionOnDemand)
        XCTAssertEqual(Reachability(unreachable), .no)

        let null: SCNetworkReachabilityFlags? = nil
        XCTAssertEqual(Reachability(null), .maybe)
    }

    func testSCInterface() {
        let cellular = SCNetworkReachabilityFlags(arrayLiteral: .isWWAN)
        XCTAssertEqual(Interface(cellular), .cellular)

        let null: SCNetworkReachabilityFlags? = nil
        XCTAssertNil(Interface(null))

        let nonCellularReachable = SCNetworkReachabilityFlags(arrayLiteral: .reachable)
        XCTAssertNil(Interface(nonCellularReachable))
    }
}
