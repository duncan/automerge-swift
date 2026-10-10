use super::UniffiCustomTypeConverter;
use automerge as am;

#[derive(Debug, Clone)]
pub struct ObjId(Vec<u8>);

impl From<ObjId> for automerge::ObjId {
    fn from(value: ObjId) -> Self {
        // Can't fail: Swift can't create an ObjId or decode one from data, so its bytes always come
        // from a valid automerge object ID that this library converted.
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

impl UniffiCustomTypeConverter for ObjId {
    type Builtin = Vec<u8>;

    fn into_custom(val: Self::Builtin) -> uniffi::Result<Self>
    where
        Self: Sized,
    {
        Ok(Self(val))
    }

    fn from_custom(obj: Self) -> Self::Builtin {
        obj.0
    }
}
