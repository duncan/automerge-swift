# Tracking Changes and History

Track, inspect, and synchronize the changes within Automerge documents.

## Overview

An Automerge document is a little like a git repository in that it is composed of a graph of changes, each identified by a hash. 
Like a git repository, a point in the history of an Automerge document can be referenced by its hash. 
_Unlike_ a git repository, an Automerge document can have multiple heads for a given point in time, representing a merge of concurrent changes. 

### Heads and change hashes

From time to time you may want to refer to a particular point in the document history. 
For example, you may want to read values at a past point in time, or get the changes since that time.
Use ``Document/heads()`` to obtain the current heads of the document, which returns a set of ``ChangeHash``.
The set of `ChangeHash` that Automerge returns represent a discrete point in time for an Automerge document.
`Document` includes families of methods that accept `[ChangeHash]` to retrieve values or objects from that point in time.

Each ``Change`` carries the time it was made, an optional message, and the actor that made it.
To also record who made a change, give the document an author.

### Authors and actors

An ``ActorId`` identifies one copy of a document. Automerge creates it for you, and every change records it.
An ``AuthorId`` identifies who is making changes: a person, an app, or whatever else your app attributes changes to.
One author usually has several actors, for example one for each device they edit on.

Provide the author when you create or load a document, then look it up for any change:

```swift
let doc = try Document(savedData, author: AuthorId(uuid: currentUser.id))
try doc.put(obj: ObjId.ROOT, key: "title", value: .String("Hello"))

for hash in doc.getHistory() {
    if let change = doc.change(hash: hash), let author = doc.author(of: change) {
        print("\(author) made a change at \(change.timestamp)")
    }
}
```

The author isn't saved with the document, because the same data can be loaded by different people. Provide it each time you load.
Author IDs are permanent and sent to every peer, so use an opaque identifier such as a UUID rather than a name or an email address.

A few rules explain the rest of the API:

- **An actor has one author.** Automerge stores the author in the actor's first change, and it applies to all the actor's changes. That is why ``Change/recordedAuthor`` is `nil` for most changes, and why you look up authors with ``Document/author(of:)`` or ``Document/author(for:)``.
- **Changing the author changes the actor.** ``Document/setAuthor(_:)`` gives the document a new, random actor, after saving any changes in progress under the previous author.
- **Let the document choose its actors.** If you set ``Document/actor`` to one that has already made changes, those changes keep the author they started with, and Automerge reports no error. ``Document/author`` then tells you the author you asked for, while ``Document/author(for:)`` tells you the one that was recorded.
- **Lookups see finished changes.** ``Document/authors``, ``Document/author(for:)``, and ``Document/actors(for:)`` include a change once the document has saved or synced it, or you've called ``Document/heads()`` or ``Document/commitWith(message:timestamp:)``. Edits still in progress aren't included.

Both ``Document/fork()`` and ``Document/forkAt(heads:)`` keep the document's author.

### Forking and Merging

You can create a fork a document using ``Document/fork()``, or ``Document/forkAt(heads:)`` to get a fork of the document at a specific point in time.
Likewise, you can merge one Document into another using ``Document/merge(other:)``, which applies any changes from the other document.

When working with multiple documents, it is important that the documents source with the same shared history, or merges (or sync) may have unpredictable, although consistent, results.
To take full advantage of Automerge's capabilities, work from forks of a single document rather than creating separate Documents, even with the same schema.

### Getting notified of what changed

When you apply changes received from a remote document (or merged from a separate local document) you may want to know what changed within the `Document`, for example to update an app's user interface.
To get this detail, use ``Document/receiveSyncMessageWithPatches(state:message:)``, which operates like `Document/receiveSyncMessage(state:message:)`, and additionally returns an array of patches, represented by the type ``Patch``.

Inspect a patch to see what action Automerge applied by inspecting the ``Patch/action`` property (represented by the enumeration ``PatchAction``).
The property ``Patch/path`` represents the path through the document schema to the element that was updated, represented by an array of ``PathElement``.
`PathElement` has an object Id (``PathElement/obj``) property and a ``PathElement/prop`` property.
`Prop` is an enumeration that represents either a key to a dictionary and it's value, or the index location within an array.
