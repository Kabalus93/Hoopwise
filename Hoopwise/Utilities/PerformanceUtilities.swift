import SwiftUI
import Combine

// MARK: - Debounced Search Publisher
/// A property wrapper that debounces text input for search fields
/// Reduces expensive filter operations during rapid typing
@propertyWrapper
struct DebouncedState<Value>: DynamicProperty {
    @StateObject private var debouncer: Debouncer<Value>
    
    var wrappedValue: Value {
        get { debouncer.value }
        nonmutating set { debouncer.subject.send(newValue) }
    }
    
    var projectedValue: Binding<Value> {
        Binding(
            get: { debouncer.value },
            set: { debouncer.subject.send($0) }
        )
    }
    
    init(wrappedValue: Value, delay: TimeInterval = 0.3) {
        _debouncer = StateObject(wrappedValue: Debouncer(initialValue: wrappedValue, delay: delay))
    }
}

private class Debouncer<Value>: ObservableObject {
    @Published var value: Value
    let subject = PassthroughSubject<Value, Never>()
    private var cancellable: AnyCancellable?
    
    init(initialValue: Value, delay: TimeInterval) {
        self.value = initialValue
        self.cancellable = subject
            .debounce(for: .seconds(delay), scheduler: DispatchQueue.main)
            .sink { [weak self] newValue in
                self?.value = newValue
            }
    }
}

// MARK: - Lazy View Modifier
/// Wraps a view to defer its body evaluation until it appears
struct LazyView<Content: View>: View {
    let build: () -> Content
    
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    
    var body: Content {
        build()
    }
}

// MARK: - Equatable View Wrapper
/// Prevents unnecessary view updates when content hasn't changed
struct EquatableView<Content: View, Value: Equatable>: View, Equatable {
    let content: Content
    let value: Value
    
    init(value: Value, @ViewBuilder content: () -> Content) {
        self.value = value
        self.content = content()
    }
    
    var body: some View {
        content
    }
    
    static func == (lhs: EquatableView<Content, Value>, rhs: EquatableView<Content, Value>) -> Bool {
        lhs.value == rhs.value
    }
}

// MARK: - View Extensions for Performance
extension View {
    /// Wrap view in equatable container to prevent unnecessary updates
    func equatable<Value: Equatable>(by value: Value) -> some View {
        EquatableView(value: value) { self }
    }
    
    /// Add drawing group for complex views with many layers
    func optimizedRendering() -> some View {
        self.drawingGroup()
    }
    
    /// Conditionally apply drawing group only when needed
    func optimizedRenderingIf(_ condition: Bool) -> some View {
        Group {
            if condition {
                self.drawingGroup()
            } else {
                self
            }
        }
    }
}

// MARK: - Cached Computed Value
/// Caches a computed value and only recomputes when dependencies change
class CachedValue<T, Dependencies: Equatable> {
    private var cachedValue: T?
    private var lastDependencies: Dependencies?
    private let compute: (Dependencies) -> T
    
    init(_ compute: @escaping (Dependencies) -> T) {
        self.compute = compute
    }
    
    func value(for dependencies: Dependencies) -> T {
        if let cached = cachedValue, lastDependencies == dependencies {
            return cached
        }
        let newValue = compute(dependencies)
        cachedValue = newValue
        lastDependencies = dependencies
        return newValue
    }
    
    func invalidate() {
        cachedValue = nil
        lastDependencies = nil
    }
}

// MARK: - Task Throttler
/// Throttles async operations to prevent rapid repeated calls
actor TaskThrottler {
    private var lastExecutionTime: Date?
    private let minimumInterval: TimeInterval
    
    init(minimumInterval: TimeInterval = 0.5) {
        self.minimumInterval = minimumInterval
    }
    
    func shouldExecute() -> Bool {
        let now = Date()
        if let lastTime = lastExecutionTime {
            guard now.timeIntervalSince(lastTime) >= minimumInterval else {
                return false
            }
        }
        lastExecutionTime = now
        return true
    }
}

// MARK: - Memory Efficient Array Extension
extension Array {
    /// Process array in chunks to avoid memory spikes
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Performance Monitoring
#if DEBUG
enum PerformanceMonitor {
    static func measure<T>(_ label: String, _ block: () -> T) -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = block()
        let end = CFAbsoluteTimeGetCurrent()
        let ms = (end - start) * 1000
        if ms > 16 { // Log if taking more than one frame (16ms)
            debugLog("⚠️ PERF: \(label) took \(String(format: "%.2f", ms))ms")
        }
        return result
    }
    
    static func measureAsync<T>(_ label: String, _ block: () async -> T) async -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = await block()
        let end = CFAbsoluteTimeGetCurrent()
        let ms = (end - start) * 1000
        if ms > 100 { // Log if taking more than 100ms for async
            debugLog("⚠️ PERF: \(label) took \(String(format: "%.2f", ms))ms")
        }
        return result
    }
}
#endif
