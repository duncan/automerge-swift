use automerge as am;

use crate::{ActorId, ObjId};

/// The identifier of an element in a list or text object: the operation that created its value, with the object
/// that holds it.
pub struct ElementId {
    pub obj: ObjId,
    pub actor: ActorId,
    pub counter: u64,
}

impl ElementId {
    pub(crate) fn from_exid(obj: &am::ObjId, id: &am::ObjId) -> Option<Self> {
        match id {
            am::ObjId::Id(counter, actor, _) => Some(ElementId {
                obj: obj.clone().into(),
                actor: actor.into(),
                counter: *counter,
            }),
            am::ObjId::Root => None,
        }
    }

    pub(crate) fn into_parts(self) -> (am::ObjId, am::ActorId, u64) {
        (self.obj.into(), self.actor.into(), self.counter)
    }
}
