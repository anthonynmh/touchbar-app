import CoreGraphics
import Foundation

/// Immutable render-time snapshot. Everything the renderer needs to draw a
/// single frame is here — no callbacks, no back-references. Constructing it
/// from a `SceneComposer` is separate from rendering it.
public struct SceneModel: Equatable {
    public let time: WorldTime
    public let celestial: CelestialPosition
    public let layout: LayoutEngine.Regions
    public let props: [SceneObject]
    public let pet: PetState

    public let battery: BatterySnapshot
    public let brightness: Double
    public let brightnessAvailable: Bool
    public let volume: Double
    public let volumeMuted: Bool
    public let volumeAvailable: Bool

    public let media: MediaSnapshot
    public let progressFraction: Double?

    public init(
        time: WorldTime,
        celestial: CelestialPosition,
        layout: LayoutEngine.Regions,
        props: [SceneObject],
        pet: PetState,
        battery: BatterySnapshot,
        brightness: Double, brightnessAvailable: Bool,
        volume: Double, volumeMuted: Bool, volumeAvailable: Bool,
        media: MediaSnapshot,
        progressFraction: Double?
    ) {
        self.time = time
        self.celestial = celestial
        self.layout = layout
        self.props = props
        self.pet = pet
        self.battery = battery
        self.brightness = brightness
        self.brightnessAvailable = brightnessAvailable
        self.volume = volume
        self.volumeMuted = volumeMuted
        self.volumeAvailable = volumeAvailable
        self.media = media
        self.progressFraction = progressFraction
    }
}

/// Pure function: assemble a SceneModel from provider snapshots. The renderer
/// is fed the result. Suitable for use in tests and preview code without any
/// AppKit dependency.
public struct SceneComposer {
    public let layout: LayoutEngine

    public init(layout: LayoutEngine) {
        self.layout = layout
    }

    public func compose(
        now: Date,
        calendar: Calendar = .current,
        pet: PetState,
        battery: BatterySnapshot,
        brightness: (value: Double, available: Bool),
        volume: (value: Double, muted: Bool, available: Bool),
        media: MediaSnapshot
    ) -> SceneModel {
        let regions = layout.regions
        let time = WorldTime(from: now, in: calendar)
        let bodyInset = min(CelestialSolver.bodyHalfWidth, regions.middle.width / 2)
        let celestial = CelestialSolver.position(
            for: time,
            sceneSize: layout.bounds.size,
            horizontalRange: (regions.middle.minX + bodyInset)...(regions.middle.maxX - bodyInset)
        )
        let props = SceneLayout.defaultObjects(inside: regions.middle)
        let progress = media.progressFraction(at: now)

        return SceneModel(
            time: time,
            celestial: celestial,
            layout: regions,
            props: props,
            pet: pet,
            battery: battery,
            brightness: brightness.value, brightnessAvailable: brightness.available,
            volume: volume.value, volumeMuted: volume.muted, volumeAvailable: volume.available,
            media: media,
            progressFraction: progress
        )
    }
}
