use automerge as am;

use crate::{ActorId, ChangeHash};

pub struct Change {
    pub actor_id: ActorId,
    pub author: Option<Vec<u8>>,
    pub message: Option<String>,
    pub deps: Vec<ChangeHash>,
    pub timestamp: i64,
    pub bytes: Vec<u8>,
    pub hash: ChangeHash,
}

impl From<am::Change> for Change {
    fn from(mut value: am::Change) -> Self {
        Change {
            actor_id: value.actor_id().into(),
            author: value.author().map(|author| author.as_bytes().to_vec()),
            message: value.message().map(String::from),
            deps: value.deps().into_iter().map(ChangeHash::from).collect(),
            timestamp: value.timestamp(),
            bytes: value.bytes().into_owned(),
            hash: value.hash().into(),
        }
    }
}

/// What automerge records about a change, without the change's encoded operations.
pub struct ChangeMetadata {
    pub actor_id: ActorId,
    pub author: Option<Vec<u8>>,
    pub seq: u64,
    pub start_op: u64,
    pub max_op: u64,
    pub message: Option<String>,
    pub deps: Vec<ChangeHash>,
    pub timestamp: i64,
    pub hash: ChangeHash,
}

impl From<am::ChangeMetadata<'_>> for ChangeMetadata {
    fn from(value: am::ChangeMetadata<'_>) -> Self {
        ChangeMetadata {
            actor_id: value.actor.as_ref().into(),
            author: value.author.map(|author| author.as_bytes().to_vec()),
            seq: value.seq,
            start_op: value.start_op,
            max_op: value.max_op,
            message: value.message.map(|message| message.into_owned()),
            deps: value.deps.into_iter().map(ChangeHash::from).collect(),
            timestamp: value.timestamp,
            hash: value.hash.into(),
        }
    }
}

impl From<Change> for am::Change {
    fn from(value: Change) -> Self {
        // Can't fail: a Change's bytes always come from an automerge change this library converted.
        am::Change::try_from(value.bytes.as_slice()).unwrap()
    }
}

#[derive(Debug, thiserror::Error)]
pub enum DecodeChangeError {
    #[error(transparent)]
    Internal(#[from] am::LoadChangeError),
}

pub fn decode_change(bytes: Vec<u8>) -> Result<Change, DecodeChangeError> {
    am::Change::try_from(bytes.as_slice())
        .map(Change::from)
        .map_err(DecodeChangeError::from)
}
