import Foundation
import Combine

// Layout preferences are separate from reading data and belong to this library.
@MainActor final class PaneLayout: ObservableObject {
    enum Pane { case library, tutor, notes }
    struct Ratios: Codable {
        var library: Double = 240.0 / 1380
        var tutor: Double = 400.0 / 1380
        var notes: Double = 300.0 / 1380
    }
    struct Widths { let library: CGFloat; let reader: CGFloat; let right: CGFloat }
    static let divider: CGFloat = 8
    static let readerMinimum: CGFloat = 520
    @Published private(set) var ratios = Ratios()
    private let file: URL

    init(root: URL) {
        file = root.appendingPathComponent("layout.json")
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Ratios.self, from: data),
           [saved.library, saved.tutor, saved.notes].allSatisfy({ $0.isFinite && $0 > 0 && $0 < 1 }) {
            ratios = saved
        }
    }
    func minimum(_ pane: Pane) -> CGFloat { pane == .library ? 200 : pane == .tutor ? 320 : 280 }
    func ratio(_ pane: Pane) -> Double { pane == .library ? ratios.library : pane == .tutor ? ratios.tutor : ratios.notes }
    func widths(total: CGFloat, libraryVisible: Bool, right: Pane?) -> Widths {
        let available = max(0, total - Self.divider * CGFloat((libraryVisible ? 1 : 0) + (right == nil ? 0 : 1)))
        let leftMin: CGFloat = libraryVisible ? minimum(.library) : 0
        let rightMin: CGFloat = right.map(minimum) ?? 0
        var left: CGFloat = libraryVisible ? min(420, max(leftMin, total * ratio(.library))) : 0
        var trailing: CGFloat = right.map { max(rightMin, total * ratio($0)) } ?? 0
        // Reduce only the space above each minimum; never overwrite the saved proportions
        // when a smaller window temporarily constrains them.
        let excess = max(0, left + trailing + Self.readerMinimum - available)
        let flexible = left - leftMin + trailing - rightMin
        if excess > 0 && flexible > 0 {
            let reduction = min(1, excess / flexible)
            left -= (left - leftMin) * reduction
            trailing -= (trailing - rightMin) * reduction
        }
        return Widths(library: left, reader: max(0, available - left - trailing), right: trailing)
    }
    func adjust(_ pane: Pane, by delta: CGFloat, total: CGFloat, libraryVisible: Bool, right: Pane?) {
        guard total > 0, delta.isFinite else { return }
        let w = widths(total: total, libraryVisible: libraryVisible, right: right)
        let current = pane == .library ? w.library : w.right
        let ceiling = current + max(0, w.reader - Self.readerMinimum)
        let next = min(pane == .library ? min(420, ceiling) : ceiling, max(minimum(pane), current + delta))
        // A deliberate drag starts from the visible widths, even if the window has
        // temporarily compressed both saved proportions. Keep the opposite edge still.
        if pane == .library, let right {
            if right == .tutor { ratios.tutor = w.right / total }
            else { ratios.notes = w.right / total }
        } else if pane != .library && libraryVisible { ratios.library = w.library / total }
        switch pane {
        case .library: ratios.library = next / total
        case .tutor: ratios.tutor = next / total
        case .notes: ratios.notes = next / total
        }
    }
    func reset(_ pane: Pane) {
        let defaults = Ratios()
        switch pane {
        case .library: ratios.library = defaults.library
        case .tutor: ratios.tutor = defaults.tutor
        case .notes: ratios.notes = defaults.notes
        }
        save()
    }
    func resetAll() { ratios = Ratios(); save() }
    func save() {
        do { try JSONEncoder().encode(ratios).write(to: file, options: .atomic) }
        catch { NSLog("伴读布局保存失败：%@", error.localizedDescription) }
    }
}
