use automerge as am;

pub struct ChangeHash(Vec<u8>);

impl From<ChangeHash> for am::ChangeHash {
    fn from(value: ChangeHash) -> Self {
        // Can't fail: Swift can't create a ChangeHash or decode one from data, so its bytes always
        // come from a 32-byte automerge change hash that this library converted.
        let inner: [u8; 32] = value.0.try_into().unwrap();
        am::ChangeHash(inner)
    }
}

impl From<am::ChangeHash> for ChangeHash {
    fn from(value: am::ChangeHash) -> Self {
        Self(value.0.to_vec())
    }
}

impl<'a> From<&'a am::ChangeHash> for ChangeHash {
    fn from(value: &'a am::ChangeHash) -> Self {
        Self(value.0.to_vec())
    }
}

uniffi::custom_newtype!(ChangeHash, Vec<u8>);
