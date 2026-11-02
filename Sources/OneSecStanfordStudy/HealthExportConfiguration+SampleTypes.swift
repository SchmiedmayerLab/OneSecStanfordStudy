//
// This source file is part of the One Sec Stanford Study open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import HealthKit

extension HealthExportConfiguration {
    /// The default study sample types available on the current OS.
    public static var defaultSampleTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.flightsClimbed),
            HKQuantityType(.activeEnergyBurned),
            HKObjectType.workoutType()
        ]
        if #available(iOS 17, *) {
            types.insert(HKQuantityType(.timeInDaylight))
        }
        if #available(iOS 18, *) {
            types.insert(HKObjectType.stateOfMindType())
        }
        return types
    }
}
