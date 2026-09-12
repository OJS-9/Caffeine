//
//  SleepPreventionManager.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import AppKit
import Foundation
import IOKit.pwr_mgt

/// Manages the core functionality of preventing system sleep
final class SleepPreventionManager {
    static let shared = SleepPreventionManager()

    private var sleepAssertionID: IOPMAssertionID?
    private var assertionTimer: Timer?
    private var isUserSessionActive = true

    private init() {
        self.setupWorkspaceNotifications()
    }

    deinit {
        releaseSleepAssertion()
        assertionTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public Methods

    /// Prevents the system from sleeping
    func preventSleep() {
        // Start or restart the assertion timer
        self.assertionTimer?.invalidate()
        self.assertionTimer = Timer.scheduledTimer(
            withTimeInterval: 10.0,
            repeats: true
        ) { [weak self] _ in
            self?.refreshSleepAssertion()
        }
        self.assertionTimer?.fire() // Fire immediately
    }

    /// Allows the system to sleep normally
    func allowSleep() {
        self.assertionTimer?.invalidate()
        self.assertionTimer = nil
        self.releaseSleepAssertion()
    }

    // MARK: - Private Methods

    private func refreshSleepAssertion() {
        guard self.isUserSessionActive else { return }

        // Create the new assertion BEFORE releasing the old one, and let it outlive the
        // refresh interval: any uncovered moment lets the system sleep while Caffeine is active
        var assertionID: IOPMAssertionID = 0
        let reason = String(localized: "Caffeine prevents sleep") as CFString
        let result = IOPMAssertionCreateWithDescription(
            // System sleep only: the display may idle so the screen saver can start
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            reason,
            nil as CFString?,
            nil as CFString?,
            nil as CFString?,
            30, // Expires 30s after the last refresh, so sleep resumes if Caffeine dies
            nil as CFString?,
            &assertionID
        )

        guard result == kIOReturnSuccess else { return }

        // New assertion is live; now drop the previous one
        if let previousAssertionID = sleepAssertionID {
            IOPMAssertionRelease(previousAssertionID)
        }

        self.sleepAssertionID = assertionID
    }

    private func releaseSleepAssertion() {
        if let assertionID = sleepAssertionID {
            IOPMAssertionRelease(assertionID)
            self.sleepAssertionID = nil
        }
    }

    private func setupWorkspaceNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        notificationCenter.addObserver(
            self,
            selector: #selector(self.sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(self.sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    @objc
    private func sessionDidResignActive() {
        self.isUserSessionActive = false
    }

    @objc
    private func sessionDidBecomeActive() {
        self.isUserSessionActive = true
    }
}
