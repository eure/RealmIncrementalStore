# RealmIncrementalStore

Realm-powered Core Data persistent store

### Wait, what?
I like [Realm](https://realm.io). Realm's memory-mapped DB blows other databases out of the water.
It's fast and memory efficient.

I also like Core Data. (disclaimer: I'm the author of [CoreStore](https://github.com/JohnEstropia/CoreStore).)
It's a very stable ORM framework and it works on top of any persistent store.

Here's the kicker: Core Data is stuck with SQLite until a better lightweight DB comes along, and Realm's database engine is phenomenal but its Cocoa framework is [still lacking some features](https://realm.io/docs/objc/latest/#current-limitations).

Fortunately, Core Data's `NSIncrementalStore` interface lets us use the best of both worlds. `RealmIncrementalStore` is an `NSIncrementalStore` subclass that dynamically creates Realm schema using your Core Data models.

Here's an `NSFetchedResultsController` running on Realm back-end (right: [Realm Browser](https://itunes.apple.com/us/app/realm-browser/id1007457278?mt=12)):

<img src="https://cloud.githubusercontent.com/assets/3029684/13276802/427c5398-db06-11e5-952b-19264a700bc5.gif" alt="Demo App and Realm Browser" />


(Check the *RealmIncrementalStoreDemo* to see how it works)

That said, **this project is still in its prototype stages and is more of a proof-of-concept than a working product. Use at your own risk!**


## How to setup
Just include RealmIncrementalStore in your project and everything else is good old Core Data code. You just have to specify `RealmIncrementalStore.storeType` when calling `addPersistentStoreWithType()` on the `NSPersistentStoreCoordinator`:

```swift
let coordinator = NSPersistentStoreCoordinator(...)
do {
    
    try coordinator.addPersistentStoreWithType(
        RealmIncrementalStore.storeType, // here
        configuration: nil,
        URL: url,
        options: nil
    )
}
catch {
    
    // ...
}
```


## Features
Right now, most of Core Data's functionality works:

- Inserting / Updating / Deleting
- Fetching
- `NSFetchedResultsController`s
- Relationships
- Basically most of what `NSIncrementalStore`s were designed to work in


## Missing bits / To Do
(Pull Requests are welcome!)

- ~~Relationships (in progress, halfway there)~~ Done
- Migrations
- Fine-grained handling of `NSFetchRequest`s
- Optimizations (still waiting for the Realm folks to open-source the **realm-core**)
- Try to implement `NSPredicates` that are not yet supported in Realm (?)
- Benchmark!


## Author

https://github.com/JohnEstropia


## License
RealmIncrementalStore is released under an MIT license. See the LICENSE file for more information

