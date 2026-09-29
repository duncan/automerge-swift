use automerge as am;

#[derive(Debug, Clone)]
pub struct ObjId(Vec<u8>);

impl From<ObjId> for automerge::ObjId {
    fn from(value: ObjId) -> Self {
        // There is no way to construct ObjId except in this library, where we always construct it
        // from a valid object ID byte array am::ObjId::try_from(&value.0[..]).unwrap()
        am::ObjId::try_from(value.0.as_slice()).unwrap()
    }
}

impl From<am::ObjId> for ObjId {
    fn from(value: am::ObjId) -> Self {
        ObjId(value.to_bytes())
    }
}

pub fn root() -> ObjId {
    am::ROOT.into()
}

uniffi::custom_newtype!(ObjId, Vec<u8>);
