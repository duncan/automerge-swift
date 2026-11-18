use automerge as am;

pub struct Cursor(Vec<u8>);

pub enum Position {
    Cursor { position: Cursor },
    Index { position: u64 },
}

/// Where a cursor goes when the element it refers to is deleted. Mirrors `automerge::MoveCursor`.
pub enum MoveCursor {
    Before,
    After,
}

impl From<MoveCursor> for am::MoveCursor {
    fn from(value: MoveCursor) -> Self {
        match value {
            MoveCursor::Before => am::MoveCursor::Before,
            MoveCursor::After => am::MoveCursor::After,
        }
    }
}

impl From<Cursor> for am::Cursor {
    fn from(value: Cursor) -> Self {
        // Can't fail: Swift can't create a Cursor or decode one from data, so its bytes always come
        // from a valid automerge cursor that this library converted.
        am::Cursor::try_from(value.0).unwrap()
    }
}

impl From<am::Cursor> for Cursor {
    fn from(value: am::Cursor) -> Self {
        Cursor(value.to_bytes())
    }
}

uniffi::custom_newtype!(Cursor, Vec<u8>);
