use super::UniffiCustomTypeConverter;
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

// The bytes include the actor's index in the document, which is only a hint for finding the actor
// and can change in a merge, so Swift can't compare or hash them directly. automerge's own
// `PartialEq` and `Hash` ignore the index.
pub fn obj_id_equal(a: ObjId, b: ObjId) -> bool {
    am::ObjId::from(a) == am::ObjId::from(b)
}

pub fn obj_id_hash(id: ObjId) -> u64 {
    use std::hash::{Hash, Hasher};
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    am::ObjId::from(id).hash(&mut hasher);
    hasher.finish()
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

#[cfg(test)]
mod tests {
    use super::*;
    use am::transaction::Transactable;
    use am::{ActorId, AutoCommit, ReadDoc};

    #[test]
    fn ids_of_the_same_object_are_equal_after_a_merge_moves_its_actor() {
        // The fork's actor sorts first, so merging it moves the document's actor from index 0 to 1.
        let mut doc = AutoCommit::new().with_actor(ActorId::from([0xFF; 16]));
        let text = doc.put_object(am::ROOT, "text", am::ObjType::Text).unwrap();
        let mut fork = doc.fork().with_actor(ActorId::from([0x00; 16]));
        let other = fork
            .put_object(am::ROOT, "other", am::ObjType::Map)
            .unwrap();
        doc.merge(&mut fork).unwrap();
        let (_, text_after_merge) = doc.get(am::ROOT, "text").unwrap().unwrap();

        let before = ObjId::from(text);
        let after = ObjId::from(text_after_merge);
        assert_ne!(before.0, after.0);
        assert!(obj_id_equal(before.clone(), after.clone()));
        assert_eq!(obj_id_hash(before.clone()), obj_id_hash(after));

        assert!(!obj_id_equal(before.clone(), ObjId::from(other)));
        assert!(!obj_id_equal(before, root()));
        assert!(obj_id_equal(root(), root()));
    }
}
