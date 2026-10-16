//! Locks that keep working after a panic.
//!
//! UniFFI catches a Rust panic and reports it to Swift, as an error from functions that throw and as
//! a crash from those that don't. If the panic happens while a document or sync state is locked for
//! writing, the standard library marks the lock as poisoned, and every later attempt to take it
//! returns an error. Unwrapping that error would turn one panic into a panic on every later call,
//! so a document that hit one bug would fail on every throwing call and crash the app on the next
//! call that doesn't throw.
//!
//! These functions take the lock anyway, and clear the poison so later calls don't see it either.
//! automerge rolls back the pending change when an operation returns an error, but a panic partway
//! through an operation may leave the in-memory document in whatever state automerge reached.

use std::sync::{RwLock, RwLockReadGuard, RwLockWriteGuard};

/// Locks `lock` for reading, even if a panic poisoned it.
pub(crate) fn read<T>(lock: &RwLock<T>) -> RwLockReadGuard<'_, T> {
    lock.read().unwrap_or_else(|poisoned| {
        lock.clear_poison();
        poisoned.into_inner()
    })
}

/// Locks `lock` for writing, even if a panic poisoned it.
pub(crate) fn write<T>(lock: &RwLock<T>) -> RwLockWriteGuard<'_, T> {
    lock.write().unwrap_or_else(|poisoned| {
        lock.clear_poison();
        poisoned.into_inner()
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::panic::{catch_unwind, AssertUnwindSafe};

    #[test]
    fn a_panic_while_writing_does_not_break_later_locks() {
        let lock = RwLock::new(1);
        let result = catch_unwind(AssertUnwindSafe(|| {
            let mut value = write(&lock);
            *value = 2;
            panic!("simulated panic while holding the write lock");
        }));
        assert!(result.is_err());
        assert!(lock.is_poisoned());

        assert_eq!(*read(&lock), 2);
        assert!(!lock.is_poisoned());
        *write(&lock) = 3;
        assert_eq!(*read(&lock), 3);
    }
}
