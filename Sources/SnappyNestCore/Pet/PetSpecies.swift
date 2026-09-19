import Foundation

/// Which body the pet wears. Behaviour (actions, scheduling, movement) is
/// shared; only the renderer's sprite drawer differs. `rawValue` is the
/// persisted preference key.
public enum PetSpecies: String, CaseIterable, Equatable, Hashable {
    case cat
    case mecha
    case cactus
    case eldritchEye

    public var displayName: String {
        switch self {
        case .cat:         return "Cat"
        case .mecha:       return "Mecha"
        case .cactus:      return "Cactus"
        case .eldritchEye: return "Eldritch Eye"
        }
    }
}
