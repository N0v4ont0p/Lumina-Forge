import Foundation

// MARK: - AsyncSemaphore

/// A Swift-concurrency-native counting semaphore that caps the number of
/// concurrent operations without blocking any OS thread.
///
/// Unlike `DispatchSemaphore`, waiting on `AsyncSemaphore` suspends the
/// calling Swift Task – it does NOT block a thread from the cooperative pool.
/// This makes it safe to use inside actor methods and TaskGroups.
///
/// Usage:
/// ```swift
/// let sem = AsyncSemaphore(limit: 8)
///
/// await withTaskGroup(of: Void.self) { group in
///     for url in urls {
///         group.addTask {
///             await sem.wait()
///             defer { Task { await sem.signal() } }
///             // ... at most 8 of these run simultaneously ...
///         }
///     }
/// }
/// ```
actor AsyncSemaphore {

    // MARK: - State

    private let limit: Int
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    // MARK: - Init

    /// - Parameter limit: Maximum number of concurrent operations allowed.
    init(limit: Int) {
        precondition(limit > 0, "AsyncSemaphore limit must be greater than zero.")
        self.limit     = limit
        self.available = limit
    }

    // MARK: - Public API

    /// Acquire a slot.  Suspends until a slot becomes available.
    func wait() async {
        if available > 0 {
            // Fast path: a slot is free, take it immediately.
            available -= 1
        } else {
            // Slow path: all slots occupied, park the caller.
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    /// Release a slot, waking the longest-waiting caller if one exists.
    func signal() {
        if let waiter = waiters.first {
            // Hand the slot directly to the next waiter (FIFO).
            waiters.removeFirst()
            waiter.resume()
        } else {
            available += 1
        }
    }
}
