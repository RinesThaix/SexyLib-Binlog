# SexyLib-Binlog

## Overview
This is a module that allows you to use guild-level binlogs. Binlog is a history of records (logs) being persisted. Records can be of different types that you can specify in your addon (as much as their handler).

### How it works
Binlog has 3 main entities: `records history`, `current state` and `latest snapshot`.
- `records history` is just a history of all the records since last snapshot that were stored within this binlog.
- `current state` is the current state of the binlog. By default it's just an empty table. Whenever new record appears, it must be handled with your own record handler, that has to modify current state with this record data so that effect of this record appearance will be persisted.
- `snapshot` is the state of binlog before very first record in it's history. Be default it's empty, but you as developer can enable snapshotting (read below).

### Where is it being stored
It's not stored server-side, but every guild member has a local copy of binlog. All records start at index zero and have strict order. There could not be two records of the same index. Once per 30 seconds every guild member online sends an addon message with their current binlog position (highest record index). If someone sees there's a mate with position higher than local, he requests the update, and target starts translating all necessary records (and possible a snapshot) using guild addon channel.

### Security
When you initialize a binlog in your addon, you can specify various access modes. Each access mode is a pair of private and public keys. Whenever new record is created, it must be signed with a private key of an access mode that's specified for this record's type, so only those who own it may create them. Whenever new record is received from another guild member, receiver validates it's signature with his public key.

For snapshots you can specify those access modes with which they may be signed.

### Snapshotting
Snapshotting is one of possible binlog working modes. Without snapshots you can face a problem when your records history is too huge: because of records having strict order and unique indices, all new guild members (or users of your addon) will need to request and download all the records from other members of a guild.

If you used to enable snapshotting, this problem can be easily resolved: you can setup your binlog to create snapshots every *N* records (with leaving last *M* records in history if it's necessary). If you did so, players with hugely outdated binlog won't have to download the whole record history, but will download latest snapshot and only those records that appeared after it.

Disadvantages of snapshotting is as follows: records in history may contain some data that's affecting your record handler, but that's not being persisted in the state of binlog. For example, if you're making a DKP addon and there's a type of records for changing the DKP for some reason, this reason will be stored inside records, but you may not want to additionally save it into the state of binlog: you may want to save into the state of binlog the exact state of DKP: which players have which amount of DKP. So, whenever new snapshot is being created, you will keep amounts of DKP of players, but lose reasons (and history) of DKP changing for some period in the past.

## Requirements
- **SexyLib-Network** is required.
- **SexyLib-Hashing** is required.
- **SexyLib-Localization** is optional, but recommended.

## Usage
`SexyLib:InitBinlog(name, accessModes)` - create new binlog.
- `name` - unique name of this binlog.
- `accessModes` - table of `accessMode` entry.
- `accessMode` entry - table consisting of 2 elements: `publicKey` and `privateKey`. Their exact structure can be found in `DSA_test` function of `dsa.lua` file in `SexyLib-Hashing` module.

`SexyLib:Binlog(name)` - returns already existing binlog of given name.
- `name` - unique name of the binlog you're trying to retrieve.

`binlog:SetupSnapshotting(maxRecords, recordsToKeep, accessModesIndices)` - if you want your binlog to have snapshots, it's the way.
- `maxRecords` - Maximum records that could be in history. When the limit exceeded, snapshot will be created and those records will be truncated.
- `recordsToKeep` - amount of last records to be kept when the snapshot is being created.
For example, if `maxRecords` is set to 10000 and `recordsToKeep` is set to 2000, snapshots will be created every 10000 records, and every time snapshot is being created last 2000 records will be saved in history.
- `accessModesIndices` - table of access modes indices with which snapshots may be signed. If not specified, snapshots may be signed only with the highest access mode of this binlog.

`binlog:GetRecords()` - get records history.

`binlog:GetCurrentState()` - get current state of binlog (latest snapshot + all records in history applied to it).

`binlog:GetSnapshot()` - get latest snapshot.

`binlog:NewRecordType(typeName, accessLevel, recordHandler)` - create new record type for this binlog.
- `typeName` - unique name for the record type.
- `accessLevel` - access required to sign the record. If it equals to zero, signing is not required at all.
- `recordHandler` - function with arguments `recordData`, `state`, `whether snapshot rebuilding is in progress (bool)`. If there's a snapshot rebuilding in progress, state is a 'rebuilding snapshot', otherwise it's the current state of binlog.

`binlog:Load(callback)` - method that has to be explicitly called whenever you ready to load the binlog.
- `callback` - function without any arguments that will be called once binlog is loaded. Can be nil.

`binlog:Clear()` - clear all the data from the binlog. After such action you will be able to retrieve data from other guild members from scratch.

`binlog:CreateRecord(typeName, data)` - create new record. If it succeeds, returns true. If it fails, returns false. Otherwise returns nil. It's stated that this method fails if there's something that went wrong internally (like you can't sign records of this type, your binlog is broken and etc). Nil is being returned if your binlog is not loaded yet or whether there're less than 3 other guild members online.
- `typeName` - name of the record type.
- `data` - the data of the record itself.