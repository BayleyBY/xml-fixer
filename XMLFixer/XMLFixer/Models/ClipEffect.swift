import Foundation

struct ClipEffect: Identifiable, Hashable {
    let id: UUID
    let name: String
    let effectID: String?
    let effectCategory: String?
    let effectType: String?
    let filterIndex: Int
    var parameters: [ClipParameter]

    init(id: UUID = UUID(), name: String, effectID: String? = nil, effectCategory: String? = nil, effectType: String? = nil, filterIndex: Int, parameters: [ClipParameter] = []) {
        self.id = id
        self.name = name
        self.effectID = effectID
        self.effectCategory = effectCategory
        self.effectType = effectType
        self.filterIndex = filterIndex
        self.parameters = parameters
    }
}

struct ClipParameter: Identifiable, Hashable {
    let id: UUID
    let parameterID: String
    let name: String
    let value: String?
    let valueMin: String?
    let valueMax: String?
    var keyframes: [ClipKeyframe]

    init(id: UUID = UUID(), parameterID: String, name: String, value: String? = nil, valueMin: String? = nil, valueMax: String? = nil, keyframes: [ClipKeyframe] = []) {
        self.id = id
        self.parameterID = parameterID
        self.name = name
        self.value = value
        self.valueMin = valueMin
        self.valueMax = valueMax
        self.keyframes = keyframes
    }
}

struct ClipKeyframe: Identifiable, Hashable {
    let id: UUID
    let when: String
    let value: String

    init(id: UUID = UUID(), when: String, value: String) {
        self.id = id
        self.when = when
        self.value = value
    }
}
