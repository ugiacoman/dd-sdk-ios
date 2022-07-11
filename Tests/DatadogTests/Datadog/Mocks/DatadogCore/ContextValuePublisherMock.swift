/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
@testable import Datadog

internal class ContextValuePublisherMock<Value>: ContextValuePublisher {
    let initialValue: Value

    var value: Value {
        didSet { receiver?(value) }
    }

    private var receiver: ContextValueReceiver<Value>?

    init(initialValue: Value) {
        self.initialValue = initialValue
        self.value = initialValue
    }

    init() where Value: ExpressibleByNilLiteral {
        initialValue = nil
        value = nil
    }

    func publish(to receiver: @escaping ContextValueReceiver<Value>) {
        self.receiver = receiver
    }

    func cancel() {
        receiver = nil
    }
}

extension ContextValuePublisher {
    static func mockAny() -> ContextValuePublisherMock<Value> where Value: ExpressibleByNilLiteral {
        .init()
    }

    static func mockWith(initialValue: Value) -> ContextValuePublisherMock<Value> {
        .init(initialValue: initialValue)
    }
}
