/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class RUMSessionScope: RUMScope, RUMContextProvider {
    struct Constants {
        /// If no interaction is registered within this period, a new session is started.
        static let sessionTimeoutDuration: TimeInterval = 15 * 60 // 15 minutes
        /// Maximum duration of a session. If it gets exceeded, a new session is started.
        static let sessionMaxDuration: TimeInterval = 4 * 60 * 60 // 4 hours
    }

    // MARK: - Child Scopes

    /// Active View scopes. Scopes are added / removed when the View starts / stops displaying.
    private(set) var viewScopes: [RUMViewScope] = [] {
        didSet {
            if !state.hasTrackedAnyView && !viewScopes.isEmpty {
                state = RUMSessionState(sessionUUID: state.sessionUUID, isInitialSession: state.isInitialSession, hasTrackedAnyView: true)
            }
        }
    }

    /// Information about this session state, shared with `CrashContext`.
    private var state: RUMSessionState {
        didSet {
            dependencies.crashContextIntegration?.update(lastRUMSessionState: state)
        }
    }

    // MARK: - Initialization

    unowned let parent: RUMContextProvider
    private let dependencies: RUMScopeDependencies

    /// Automatically detect background events by creating "Background" view if no other view is active
    internal let backgroundEventTrackingEnabled: Bool

    /// This Session UUID. Equals `.nullUUID` if the Session is sampled.
    let sessionUUID: RUMUUID
    /// Tells if events from this Session should be sampled-out (not send).
    let shouldBeSampledOut: Bool
    /// If this is the very first session created in the current app process (`false` for session created upon expiration of a previous one).
    let isInitialSession: Bool
    /// RUM Session sampling rate.
    private let samplingRate: Float
    /// The start time of this Session, measured in device date. In initial session this is the time of SDK init.
    private let sessionStartTime: Date
    /// Time of the last RUM interaction noticed by this Session.
    private var lastInteractionTime: Date

    init(
        isInitialSession: Bool,
        parent: RUMContextProvider,
        dependencies: RUMScopeDependencies,
        samplingRate: Float,
        startTime: Date,
        backgroundEventTrackingEnabled: Bool
    ) {
        self.parent = parent
        self.dependencies = dependencies
        self.samplingRate = samplingRate
        self.shouldBeSampledOut = RUMSessionScope.randomizeSampling(using: samplingRate)
        self.sessionUUID = shouldBeSampledOut ? .nullUUID : dependencies.rumUUIDGenerator.generateUnique()
        self.isInitialSession = isInitialSession
        self.sessionStartTime = startTime
        self.lastInteractionTime = startTime
        self.backgroundEventTrackingEnabled = backgroundEventTrackingEnabled
        self.state = RUMSessionState(sessionUUID: sessionUUID.rawValue, isInitialSession: isInitialSession, hasTrackedAnyView: false)

        // Update `CrashContext` with recent RUM session state:
        dependencies.crashContextIntegration?.update(lastRUMSessionState: state)
    }

    /// Creates a new Session upon expiration of the previous one.
    convenience init(
        from expiredSession: RUMSessionScope,
        startTime: Date
    ) {
        self.init(
            isInitialSession: false,
            parent: expiredSession.parent,
            dependencies: expiredSession.dependencies,
            samplingRate: expiredSession.samplingRate,
            startTime: startTime,
            backgroundEventTrackingEnabled: expiredSession.backgroundEventTrackingEnabled
        )

        // Transfer active Views by creating new `RUMViewScopes` for their identity objects:
        self.viewScopes = expiredSession.viewScopes.compactMap { expiredView in
            guard let expiredViewIdentifiable = expiredView.identity.identifiable else {
                return nil // if the underlying identifiable (`UIVIewController`) no longer exists, skip transferring its scope
            }
            return RUMViewScope(
                isInitialView: false,
                parent: self,
                dependencies: dependencies,
                identity: expiredViewIdentifiable,
                path: expiredView.viewPath,
                name: expiredView.viewName,
                attributes: expiredView.attributes,
                customTimings: expiredView.customTimings,
                startTime: startTime
            )
        }
    }

    // MARK: - RUMContextProvider

    var context: RUMContext {
        var context = parent.context
        context.sessionID = sessionUUID
        return context
    }

    // MARK: - RUMScope

    func process(command: RUMCommand) -> Bool {
        if timedOutOrExpired(currentTime: command.time) {
            return false // no longer keep this session
        }
        lastInteractionTime = command.time

        if shouldBeSampledOut {
            return true
        }

        if let startViewCommand = command as? RUMStartViewCommand {
            // Start view scope explicitly on receiving "start view" command
            startView(on: startViewCommand)
        } else if !hasActiveView {
            // Otherwise, if there is no active view scope, consider starting artificial scope for handling this command
            let handlingRule = RUMOffViewEventsHandlingRule(
                sessionState: state,
                isAppInForeground: dependencies.appStateListener.history.currentState.isActive,
                isBETEnabled: backgroundEventTrackingEnabled
            )

            switch handlingRule {
            case .handleInApplicationLaunchView where command.canStartApplicationLaunchView:
                startApplicationLaunchView(on: command)
            case .handleInBackgroundView where command.canStartBackgroundView:
                startBackgroundView(on: command)
            default:
                // As no view scope will handle this command, warn the user on dropping it
                userLogger.warn(
                    """
                    \(String(describing: command)) was detected, but no view is active. To track views automatically, try calling the
                    DatadogConfiguration.Builder.trackUIKitRUMViews() method. You can also track views manually using
                    the RumMonitor.startView() and RumMonitor.stopView() methods.
                    """
                )
            }
        }

        // Propagate command
        if !viewScopes.isEmpty {
            viewScopes = manage(childScopes: viewScopes, byPropagatingCommand: command)
        }

        return true
    }

    /// If there is an active view.
    private var hasActiveView: Bool {
        return viewScopes.contains { $0.isActiveView }
    }

    // MARK: - RUMCommands Processing

    private func startView(on command: RUMStartViewCommand) {
        let isStartingInitialView = isInitialSession && !state.hasTrackedAnyView
        viewScopes.append(
            RUMViewScope(
                isInitialView: isStartingInitialView,
                parent: self,
                dependencies: dependencies,
                identity: command.identity,
                path: command.path,
                name: command.name,
                attributes: command.attributes,
                customTimings: [:],
                startTime: command.time
            )
        )
    }

    private func startApplicationLaunchView(on command: RUMCommand) {
        viewScopes.append(
            RUMViewScope(
                isInitialView: true,
                parent: self,
                dependencies: dependencies,
                identity: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL,
                path: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL,
                name: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName,
                attributes: command.attributes,
                customTimings: [:],
                startTime: sessionStartTime
            )
        )
    }

    private func startBackgroundView(on command: RUMCommand) {
        let isStartingInitialView = isInitialSession && !state.hasTrackedAnyView
        viewScopes.append(
            RUMViewScope(
                isInitialView: isStartingInitialView,
                parent: self,
                dependencies: dependencies,
                identity: RUMOffViewEventsHandlingRule.Constants.backgroundViewURL,
                path: RUMOffViewEventsHandlingRule.Constants.backgroundViewURL,
                name: RUMOffViewEventsHandlingRule.Constants.backgroundViewName,
                attributes: command.attributes,
                customTimings: [:],
                startTime: command.time
            )
        )
    }

    private func timedOutOrExpired(currentTime: Date) -> Bool {
        let timeElapsedSinceLastInteraction = currentTime.timeIntervalSince(lastInteractionTime)
        let timedOut = timeElapsedSinceLastInteraction >= Constants.sessionTimeoutDuration

        let sessionDuration = currentTime.timeIntervalSince(sessionStartTime)
        let expired = sessionDuration >= Constants.sessionMaxDuration

        return timedOut || expired
    }

    private static func randomizeSampling(using samplingRate: Float) -> Bool {
        let sendSessionEvents = Float.random(in: 0.0..<100.0) < samplingRate
        return !sendSessionEvents
    }
}
