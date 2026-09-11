//
//  ScreenSaverLauncher.swift
//  Caffeine
//
//  Starts the screen saver once the user has been idle for a while,
//  so a static image never stays on screen while Caffeine keeps the Mac awake.
//

import AppKit
import CoreGraphics
import Foundation
import IOKit

final class ScreenSaverLauncher {
    static let shared = ScreenSaverLauncher()
    static let defaultDelayMinutes = 5

    private static let screenSaverBundleID = "com.apple.ScreenSaver.Engine"
    private static let screenSaverURL = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")

    private var checkTimer: Timer?
    private var didLaunchThisIdlePeriod = false
    private let checkInterval: TimeInterval = 15

    /// Minutes of inactivity before starting the screen saver; 0 means never
    private var delayMinutes: Int {
        UserDefaults.standard.object(forKey: PreferenceKeys.screenSaverDelay) as? Int ?? Self.defaultDelayMinutes
    }

    private init() {}

    deinit {
        stopMonitoring()
    }

    // MARK: - Public Methods

    func startMonitoring() {
        self.stopMonitoring()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.checkTimer = Timer.scheduledTimer(
                withTimeInterval: self.checkInterval,
                repeats: true
            ) { [weak self] _ in
                self?.checkAndLaunchIfNeeded()
            }
        }
    }

    func stopMonitoring() {
        self.checkTimer?.invalidate()
        self.checkTimer = nil
        self.didLaunchThisIdlePeriod = false
    }

    // MARK: - Private Methods

    private func checkAndLaunchIfNeeded() {
        let delayMinutes = self.delayMinutes
        guard delayMinutes > 0, self.getSystemIdleTime() >= TimeInterval(delayMinutes * 60) else {
            // User is back; allow launching again next time they go idle
            self.didLaunchThisIdlePeriod = false
            return
        }

        // Launch once per idle period, and never wake a display that already went to sleep
        guard
            !self.didLaunchThisIdlePeriod,
            !self.isScreenSaverRunning(),
            CGDisplayIsAsleep(CGMainDisplayID()) == 0 else { return }

        self.didLaunchThisIdlePeriod = true
        NSWorkspace.shared.openApplication(
            at: Self.screenSaverURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private func isScreenSaverRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.screenSaverBundleID).isEmpty
    }

    private func getSystemIdleTime() -> TimeInterval {
        var iterator: io_iterator_t = 0

        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching("IOHIDSystem"),
                &iterator
            ) == KERN_SUCCESS else { return 0 }

        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return 0 }

        defer { IOObjectRelease(entry) }

        var unmanagedDict: Unmanaged<CFMutableDictionary>?
        guard
            IORegistryEntryCreateCFProperties(
                entry,
                &unmanagedDict,
                kCFAllocatorDefault,
                0
            ) == KERN_SUCCESS,
            let dict = unmanagedDict?.takeRetainedValue() as? [String: Any],
            let idleTime = dict["HIDIdleTime"] as? Int64 else { return 0 }

        // HIDIdleTime is in nanoseconds
        return TimeInterval(idleTime) / 1_000_000_000
    }
}
