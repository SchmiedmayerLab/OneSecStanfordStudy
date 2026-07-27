//
// This source file is part of the OneSecStanfordStudy open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import HealthKit
@preconcurrency import ModelsR4
@testable import OneSecStanfordStudy
import Testing


@Suite
struct OneSecStanfordStudyTests {
    @Test
    func healthExportConfigurationStoresValues() {
        let destination = URL(fileURLWithPath: "/tmp/one-sec-export")
        let sampleTypes: Set<HKObjectType> = []
        let timeRange = Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 1)

        let configuration = HealthExportConfiguration(
            destination: destination,
            sampleTypes: sampleTypes,
            timeRange: timeRange,
            didStartExport: { _ in },
            didEndExport: {}
        )

        #expect(configuration.destination == destination)
        #expect(configuration.sampleTypes == sampleTypes)
        #expect(configuration.timeRange == timeRange)
    }

    @Test
    func anyAsyncSequenceWrapsNonThrowingSequences() async throws {
        let stream = AsyncStream<Int> { continuation in
            continuation.yield(1)
            continuation.yield(2)
            continuation.yield(3)
            continuation.finish()
        }
        let sequence = AnyAsyncSequence<Int, Never>(unsafelyAssumingDoesntThrow: stream)

        var values: [Int] = []
        for try await value in sequence {
            values.append(value)
        }

        #expect(values == [1, 2, 3])
    }

    @Test
    func anyAsyncSequencePropagatesErrors() async throws {
        enum TestError: Error, Equatable {
            case failure
        }

        let stream = AsyncThrowingStream<Int, any Error> { continuation in
            continuation.yield(1)
            continuation.finish(throwing: TestError.failure)
        }
        let sequence = AnyAsyncSequence<Int, any Error>(stream)

        var values: [Int] = []
        var caughtError: (any Error)?
        do {
            for try await value in sequence {
                values.append(value)
            }
        } catch {
            caughtError = error
        }

        #expect(values == [1])
        #expect(caughtError as? TestError == .failure)
    }

    @available(iOS 18.0, *)
    @Test
    func anyAsyncSequenceSupportsIsolationAwareIteration() async {
        let stream = AsyncStream<Int> { continuation in
            continuation.yield(1)
            continuation.finish()
        }
        let sequence = AnyAsyncSequence<Int, Never>(stream)
        var iterator = sequence.makeAsyncIterator()

        let firstValue = await iterator.next(isolation: nil)
        let secondValue = await iterator.next(isolation: nil)

        #expect(firstValue == 1)
        #expect(secondValue == nil)
    }
    
    
    @available(iOS 18.0, *)
    @Test(arguments: [
        Observation.stepCountSample,
        Observation.sleepAnalysisSampleAppleWatch,
        Observation.sleepAnalysisSampleAutoSleep,
        Observation.stateOfMindSample
    ])
    func healthKitMetadataStripping(_ observation: Observation) throws {
        let toJson = {
            try #require(String(bytes: try JSONEncoder().encode($0 as Observation), encoding: .utf8))
        }
        let containsNameBefore = try toJson(observation).localizedCaseInsensitiveContains("lukas")
        observation.stripDeviceNameMetadata()
        let containsNameAfter = try toJson(observation).localizedCaseInsensitiveContains("lukas")
        #expect(containsNameBefore || !containsNameAfter, "name not correctly removed!")
    }
}


// swiftlint:disable file_length force_try

extension Observation {
    fileprivate static var stepCountSample: Observation {
        try! JSONDecoder().decode(Observation.self, from: Data(
            """
            {
              "code" : {
                "coding" : [
                  {
                    "code" : "55423-8",
                    "display" : "Number of steps in unspecified time Pedometer",
                    "system" : "http://loinc.org"
                  },
                  {
                    "code" : "HKQuantityTypeIdentifierStepCount",
                    "display" : "Step Count",
                    "system" : "http://developer.apple.com/documentation/healthkit"
                  }
                ]
              },
              "effectivePeriod" : {
                "end" : "2025-07-27T15:55:54.554791688+02:00",
                "start" : "2025-07-27T15:55:49.459158658+02:00"
              },
              "extension" : [
                {
                  "extension" : [
                    {
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceDevice/name",
                      "valueString" : "Apple Watch"
                    },
                    {
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceDevice/manufacturer",
                      "valueString" : "Apple Inc."
                    },
                    {
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceDevice/model",
                      "valueString" : "Watch"
                    },
                    {
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceDevice/hardwareVersion",
                      "valueString" : "Watch6,15"
                    },
                    {
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceDevice/softwareVersion",
                      "valueString" : "11.5"
                    }
                  ],
                  "url" : "https://bdh.stanford.edu/fhir/defs/sourceDevice"
                },
                {
                  "extension" : [
                    {
                      "extension" : [
                        {
                          "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/source/name",
                          "valueString" : "Lukas' Apple Watch"
                        },
                        {
                          "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/source/bundleIdentifier",
                          "valueString" : "com.apple.health.94C8E349-0D09-4184-BF6C-AF11692FA465"
                        }
                      ],
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/source"
                    },
                    {
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/version",
                      "valueString" : "11.5"
            
                    },
                    {
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/productType",
                      "valueString" : "Watch6,15"
                    },
                    {
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/OSVersion",
                      "valueString" : "11.5.0"
                    }
                  ],
                  "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision"
                }
              ],
              "id" : "549A247B-2769-4399-B0FF-8B5577314B1C",
              "identifier" : [
                {
                  "id" : "549A247B-2769-4399-B0FF-8B5577314B1C"
                }
              ],
              "issued" : "2026-07-27T15:30:56.491983056+02:00",
              "resourceType" : "Observation",
              "status" : "final",
              "valueQuantity" : {
                "unit" : "steps",
                "value" : 10
              }
            }
            """.utf8
        ))
    }
    
    fileprivate static var sleepAnalysisSampleAutoSleep: Observation {
        try! JSONDecoder().decode(Observation.self, from: Data(
            """
            {
              "code" : {
                "coding" : [
                  {
                    "code" : "HKCategoryTypeIdentifierSleepAnalysis",
                    "display" : "Sleep Analysis",
                    "system" : "http://developer.apple.com/documentation/healthkit"
                  }
                ]
              },
              "effectivePeriod" : {
                "end" : "2025-07-28T02:12:00+02:00",
                "start" : "2025-07-28T01:20:00+02:00"
              },
              "extension" : [
                {
                  "extension" : [
                    {
                      "extension" : [
                        {
                          "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/source/name",
                          "valueString" : "AutoSleep"
                        },
                        {
                          "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/source/bundleIdentifier",
                          "valueString" : "com.tantsissa.AutoSleep"
                        }
                      ],
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/source"
                    },
                    {
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/version",
                      "valueString" : "6.14.0"
                    },
                    {
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/productType",
                      "valueString" : "iPhone16,2"
                    },
                    {
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/OSVersion",
                      "valueString" : "18.5.0"
                    }
                  ],
                  "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision"
                }
              ],
              "id" : "F8A59190-87C9-4652-BC3D-2C2653654C25",
              "identifier" : [
                {
                  "id" : "F8A59190-87C9-4652-BC3D-2C2653654C25"
                }
              ],
              "issued" : "2026-07-27T15:35:50.035006046+02:00",
              "resourceType" : "Observation",
              "status" : "final",
              "valueCodeableConcept" : {
                "coding" : [
                  {
                    "code" : "1",
                    "display" : "asleep unspecified",
                    "system" : "https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis"
                  }
                ]
              }
            }
            """.utf8
        ))
    }
    
    fileprivate static var sleepAnalysisSampleAppleWatch: Observation {
        try! JSONDecoder().decode(Observation.self, from: Data(
            """
            {
              "code" : {
                "coding" : [
                  {
                    "code" : "HKCategoryTypeIdentifierSleepAnalysis",
                    "display" : "Sleep Analysis",
                    "system" : "http://developer.apple.com/documentation/healthkit"
                  }
                ]
              },
              "effectivePeriod" : {
                "end" : "2026-07-01T00:53:21.225054979+02:00",
                "start" : "2026-07-01T00:30:14.864213943+02:00"
              },
              "extension" : [
                {
                  "extension" : [
                    {
                      "extension" : [
                        {
                          "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/source/name",
                          "valueString" : "Lukas' Apple Watch"
                        },
                        {
                          "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/source/bundleIdentifier",
                          "valueString" : "com.apple.health.B83FE7C9-B62D-44D9-92A8-5CB2AE037A06"
                        }
                      ],
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/source"
                    },
                    {
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/version",
                      "valueString" : "26.5"
                    },
                    {
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/productType",
                      "valueString" : "Watch7,12"
                    },
                    {
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/OSVersion",
                      "valueString" : "26.5.0"
                    }
                  ],
                  "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision"
                },
                {
                  "extension" : [
                    {
                      "url" : "https://bdh.stanford.edu/fhir/defs/metadata/HKTimeZone",
                      "valueString" : "Europe/Berlin"
                    }
                  ],
                  "url" : "https://bdh.stanford.edu/fhir/defs/metadata"
                }
              ],
              "id" : "C7C7E250-F086-4C54-B9DF-8C9A52E65050",
              "identifier" : [
                {
                  "id" : "C7C7E250-F086-4C54-B9DF-8C9A52E65050"
                }
              ],
              "issued" : "2026-07-27T15:36:32.384843945+02:00",
              "resourceType" : "Observation",
              "status" : "final",
              "valueCodeableConcept" : {
                "coding" : [
                  {
                    "code" : "3",
                    "display" : "asleep core",
                    "system" : "https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis"
                  }
                ]
              }
            }
            """.utf8
        ))
    }
    
    fileprivate static var stateOfMindSample: Observation {
        try! JSONDecoder().decode(Observation.self, from: Data(
            """
            {
              "category" : [
                {
                  "coding" : [
                    {
                      "code" : "survey",
                      "display" : "Survey",
                      "system" : "http://terminology.hl7.org/CodeSystem/observation-category"
                    }
                  ]
                }
              ],
              "code" : {
                "coding" : [
                  {
                    "code" : "HKStateOfMind",
                    "display" : "State of Mind",
                    "system" : "http://developer.apple.com/documentation/healthkit"
                  }
                ]
              },
              "component" : [
                {
                  "code" : {
                    "coding" : [
                      {
                        "code" : "HKStateOfMindKind",
                        "display" : "State of Mind Kind",
                        "system" : "http://developer.apple.com/documentation/healthkit"
                      }
                    ]
                  },
                  "valueString" : "momentary emotion"
                },
                {
                  "code" : {
                    "coding" : [
                      {
                        "code" : "HKStateOfMindValence",
                        "display" : "State of Mind Valence",
                        "system" : "http://developer.apple.com/documentation/healthkit"
                      }
                    ]
                  },
                  "valueQuantity" : {
                    "value" : 0
                  }
                },
                {
                  "code" : {
                    "coding" : [
                      {
                        "code" : "HKStateOfMindValenceClassification",
                        "display" : "State of Mind Valence Classification",
                        "system" : "http://developer.apple.com/documentation/healthkit"
                      }
                    ]
                  },
                  "valueString" : "neutral"
                },
                {
                  "code" : {
                    "coding" : [
                      {
                        "code" : "HKStateOfMindLabel",
                        "display" : "State of Mind Label",
                        "system" : "http://developer.apple.com/documentation/healthkit"
                      }
                    ]
                  },
                  "valueString" : "indifferent"
                }
              ],
              "effectiveDateTime" : "2025-11-14T15:54:26.086753964+01:00",
              "extension" : [
                {
                  "extension" : [
                    {
                      "extension" : [
                        {
                          "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/source/name",
                          "valueString" : "Lukas' Apple Watch"
                        },
                        {
                          "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/source/bundleIdentifier",
                          "valueString" : "com.apple.health.B83FE7C9-B62D-44D9-92A8-5CB2AE037A06"
                        }
                      ],
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/source"
                    },
                    {
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/version",
                      "valueString" : "26.1"
                    },
                    {
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/productType",
                      "valueString" : "Watch7,12"
                    },
                    {
                      "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision/OSVersion",
                      "valueString" : "26.1.0"
                    }
                  ],
                  "url" : "https://bdh.stanford.edu/fhir/defs/sourceRevision"
                }
              ],
              "id" : "77E3A6C9-5272-4D6B-AC5F-82F48AABD190",
              "identifier" : [
                {
                  "id" : "77E3A6C9-5272-4D6B-AC5F-82F48AABD190"
                }
              ],
              "issued" : "2026-07-27T15:37:02.204658985+02:00",
              "resourceType" : "Observation",
              "status" : "final"
            }
            """.utf8
        ))
    }
}
