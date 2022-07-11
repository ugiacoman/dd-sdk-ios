/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DatadogContextProviderTests: XCTestCase {
    let context: DatadogContext = .mockAny()

    // MARK: - Thread Safety

    func testConcurrentReadWrite() {
        let provider = DatadogContextProvider(context: context)

        DispatchQueue.concurrentPerform(iterations: 50) { iteration in
            provider.read { _ in }
            provider.write { $0 = .mockAny() }
        }
    }

    // MARK: - Test Propagation

    func testPublisherPropagation() throws {
        // Given
        let serverOffsetPublisher = ContextValuePublisherMock<TimeInterval>(initialValue: 0)
        let networkConnectionInfoPublisher = ContextValuePublisherMock<NetworkConnectionInfo?>()
        let carrierInfoPublisher = ContextValuePublisherMock<CarrierInfo?>()

        let provider = DatadogContextProvider(context: context)
        provider.subscribe(\.serverTimeOffset, to: serverOffsetPublisher)
        provider.subscribe(\.networkConnectionInfo, to: networkConnectionInfoPublisher)
        provider.subscribe(\.carrierInfo, to: carrierInfoPublisher)

        // When
        let serverTimeOffset: TimeInterval = .mockRandomInThePast()
        serverOffsetPublisher.value = serverTimeOffset

        let networkConnectionInfo: NetworkConnectionInfo = .mockRandom()
        networkConnectionInfoPublisher.value = networkConnectionInfo

        let carrierInfo: CarrierInfo = .mockRandom()
        carrierInfoPublisher.value = carrierInfo

        // Then
        let context = try provider.read()
        XCTAssertEqual(context.serverTimeOffset, serverTimeOffset)
        XCTAssertEqual(context.networkConnectionInfo, networkConnectionInfo)
        XCTAssertEqual(context.carrierInfo, carrierInfo)
    }

    func testReaderPropagation() throws {
        // Given
        let serverOffsetReader = ContextValueReaderMock<TimeInterval>(initialValue: 0)
        let networkConnectionInfoReader = ContextValueReaderMock<NetworkConnectionInfo?>()
        let carrierInfoReader = ContextValueReaderMock<CarrierInfo?>()

        let provider = DatadogContextProvider(context: context)
        provider.assign(reader: serverOffsetReader, to: \.serverTimeOffset)
        provider.assign(reader: networkConnectionInfoReader, to: \.networkConnectionInfo)
        provider.assign(reader: carrierInfoReader, to: \.carrierInfo)

        // When
        let serverTimeOffset: TimeInterval = .mockRandomInThePast()
        serverOffsetReader.value = serverTimeOffset

        let networkConnectionInfo: NetworkConnectionInfo = .mockRandom()
        networkConnectionInfoReader.value = networkConnectionInfo

        let carrierInfo: CarrierInfo = .mockRandom()
        carrierInfoReader.value = carrierInfo

        // Then
        let context = try provider.read()
        XCTAssertEqual(context.serverTimeOffset, serverTimeOffset)
        XCTAssertEqual(context.networkConnectionInfo, networkConnectionInfo)
        XCTAssertEqual(context.carrierInfo, carrierInfo)
    }
}
