import Foundation
import Combine

/// Persistence + CRUD for coach-authored phase templates. UserDefaults-backed
/// because templates are small (a few KB) and few (one or two per age group
/// in practice). Falls through to `FEBPhasePresets` when the coach hasn't
/// authored a template for a given age group.
@MainActor
final class PhaseTemplateStore: ObservableObject {
    static let shared = PhaseTemplateStore()

    @Published private(set) var templates: [UserPhaseTemplate] = []

    private static let storageKey = "phase_templates_v1"

    private init() {
        load()
    }

    // MARK: - Resolution

    /// Templates the coach has authored for this age group.
    func userTemplates(for age: AgeGroup) -> [UserPhaseTemplate] {
        templates.filter { $0.ageGroup == age }
    }

    /// Phase chain to apply by default for an age group: the coach's most
    /// recently updated template if one exists, else FEB defaults.
    func defaultPhases(for age: AgeGroup) -> [PhaseTemplate] {
        if let preferred = userTemplates(for: age).max(by: { $0.updatedAt < $1.updatedAt }) {
            return preferred.phases
        }
        return FEBPhasePresets.phases(for: age)
    }

    // MARK: - CRUD

    func save(_ template: UserPhaseTemplate) {
        var updated = template
        updated.updatedAt = Date()
        if let i = templates.firstIndex(where: { $0.id == template.id }) {
            templates[i] = updated
        } else {
            templates.append(updated)
        }
        persist()
    }

    func delete(_ template: UserPhaseTemplate) {
        templates.removeAll { $0.id == template.id }
        persist()
    }

    /// Seed a new user template from FEB defaults so coaches can edit instead
    /// of starting from a blank screen.
    func seedFromFEB(name: String, age: AgeGroup) -> UserPhaseTemplate {
        let template = UserPhaseTemplate(
            name: name,
            ageGroup: age,
            phases: FEBPhasePresets.phases(for: age)
        )
        save(template)
        return template
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([UserPhaseTemplate].self, from: data) {
            templates = decoded
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(templates) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
