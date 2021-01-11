SexyLib_Binlogs = SexyLib_Binlogs or {}

local util = SexyLib:Util()
local logger = SexyLib:Logger('Sexy Lib')

local DISTRIBUTE_CHANNEL = 'D'
local POSITION_CHANNEL = 'P'
local REQUEST_CHANNEL = 'R'
local SNAPSHOT_CHANNEL = 'S'

local binlogs = {}

-- Record format: {type name, position, data, signature}

local function getGuildMembersOnlineCount()
    local total = 0
    for i = 1, GetNumGuildMembers() do
        playerName, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if online then total = total + 1 end
    end
    return total
end

local function canDistribute(binlog)
    return binlog.loaded and getGuildMembersOnlineCount() > 3
end

local function newBinlog(name, accessModes)
    if not SexyLib_Binlogs[name] then
        SexyLib_Binlogs[name] = {
            records = {},
            snapshot = {},
            delayed = {}
        }
    end
    local network = SexyLib:InitNetwork('BL-' .. name, 1)
    local binlog = {
        SetupSnapshotting = function(self, maxRecords, recordsToKeep, accessModesIndices)
            self.maxRecords = maxRecords
            self.recordsToKeep = recordsToKeep
            self.accessModesIndices = accessModesIndices
        end,
        getData = function(self)
            return SexyLib_Binlogs[name]
        end,
        getDelayedRecords = function(self)
            return self:getData().delayed
        end,
        GetRecords = function(self)
            return self:getData().records
        end,
        GetSnapshot = function(self)
            return self:getData().snapshot
        end,
        GetCurrentState = function(self)
            if self.state == nil then self.state = util:CopyTable(self:GetSnapshot()) end
            return self.state
        end,
        RecordTypes = {},
        NewRecordType = function(self, typeName, accessLevel, recordHandler)
            if self.RecordTypes[typeName] then
                logger:LogErrorL('binlog_error_type_exists', typeName, name)
                return
            end
            self.RecordTypes[typeName] = {accessLevel, recordHandler}
        end,
        getRecordType = function(self, record)
            local type = self.RecordTypes[record[1]]
            if not type then
                logger:LogErrorL('binlog_error_no_type', record[1], name)
                return nil
            end
            return type
        end,
        checkRecordSignature = function(self, record)
            local type = self:getRecordType(record)
            if not type then return false end
            local accessMode = type[1]
            if accessMode ~= 0 then
                local keys = accessModes[accessMode]
                if not keys or not keys[1] then
                    logger:LogErrorL('binlog_error_wrong_access_mode', accessMode, name)
                    return false
                end
                if not record[2] then
                    logger:LogErrorL('binlog_error_no_signature_in_record', name)
                    return false
                end
                if not SexyLib:Hashing():Validate({record[2], record[3]}, record[4], keys[1]) then
                    logger:LogDebug('Record verification of type %s failed in binlog %s.', record[1], name)
                    return false
                end
            end
            return true
        end,
        handleRecord = function(self, record, withAccessCheck, rebuildingSnapshot)
            local type = self:getRecordType(record)
            if not type then return false end

            if rebuildingSnapshot then
                type[2](record[3], rebuildingSnapshot, true)
            else
                local pos, current = record[2], self:getData().position
                if current ~= nil and pos ~= current + 1 then return false end
                if withAccessCheck and not self:checkRecordSignature(record) then return false end
                type[2](record[3], self:GetCurrentState(), false)
                self:getData().position = pos
            end

            return true
        end,
        Load = function(self, callback)
            local time = util:Millis()
            for _, record in pairs(self:GetRecords) do
                self:handleRecord(record, false)
            end
            logger:LogDebug('Binlog %s loading took %d ms.', name, util:Millis(time))
            if callback then
                time = util:Millis()
                callback()
                logger:LogDebug('Binlog %s loading callback took %d ms.', name, util:Millis(time))
            end
            self.loaded = true
            if self:getDelayedRecords() then self:initDelayedTicker() end
        end,
        Clear = function(self)
            SexyLib_Binlogs[name] = {
                records = {},
                snapshot = {},
                delayed = {}
            }
        end,
        rebuildSnapshotIfNeeded = function(self)
            if not self.maxRecords then return end

            local modes = self.accessModesIndices or {#accessModes}
            local signMode = -1
            for _, idx in pairs(modes) do
                if idx == 0 or accessModes[idx] and accessModes[idx][1] and accessModes[idx][2] then
                    signMode = idx
                    break
                end
            end
            if signMode == -1 then return end

            local records = self:GetRecords()
            local size = #records
            if size < self.maxRecords then return end
            local time = util:Millis()
            local keepingRecords = {}
            local keepingIndex = size
            if self.recordsToKeep then
                keepingIndex = size - self.recordsToKeep + 1
                if keepingIndex < 2 then return end
                for i = keepingIndex, size do
                    keepingRecords[#keepingRecords + 1] = records[i]
                end
            end
            local snapshot = util:CopyTable(self:GetSnapshot())
            for i = 1, keepingIndex - 1 do
                self:handleRecord(records[i], false, snapshot)
            end
            snapshot._sign = nil
            snapshot._mode = nil
            if signMode then
                snapshot._mode = signMode
                local keys = accessModes[signMode]
                local signature, err = SexyLib:Hashing():Sign(snapshot, keys[2], keys[1])
                if err then
                    logger:LogErrorL('binlog_error_signing_snapshot_failed', name, err)
                    return
                end
                snapshot._sign = signature
            end
            self:getData().snapshot = snapshot
            self:getData().records = keepingRecords
            logger:LogDebug('Snapshot recreation of binlog %s took %d ms.', name, util:Millis(time))
        end,
        addRecord = function(self, record)
            if not self:handleRecord(record, true) then return false end
            local records = self:GetRecords()
            records[#records + 1] = record
            self:rebuildSnapshotIfNeeded()
            return true
        end,
        getNextPosition = function(self)
            local pos = self:getData().position
            if pos == nil then return 0 end
            return pos + 1
        end,
        distribute = function(self, record)
            network:Send(DISTRIBUTE_CHANNEL, 'GUILD', nil, {false, record}, 'NORMAL')
        end,
        initDelayedTicker = function(self)
            if self.delayedTickerInitialized then return end
            self.delayedTickerInitialized = true
            local that = self
            C_Timer.NewTicker(30, function()
                if not canDistribute(that) then return end
                for _, record in pairs(that:getDelayedRecords()) do
                    record[2] = that:getNextPosition()
                    if that:addRecord(record) then that:distribute(record) end
                end
                that:getData().delayed = {}
            end)
        end,
        createRecord = function(self, record)
            if not canDistribute(self) then
                local records = self:getDelayedRecords()
                records[#records + 1] = record
                return nil
            end
            if not self:addRecord(record) then return false end
            self:distribute(record)
            return true
        end,
        CreateRecord = function(self, typeName, data)
            local record = {typeName, self:getNextPosition(), data}
            local type = self:getRecordType(record)
            if not type then return false end
            local accessMode = type[1]
            if accessMode ~= 0 then
                local keys = accessModes[accessMode]
                if not keys or not keys[1] then
                    logger:LogErrorL('binlog_error_wrong_access_mode', accessMode, name)
                    return false
                end
                if not keys[2] then
                    logger:LogErrorL('binlog_error_cant_sign', typeName, name)
                    return false
                end
                local signature, err = SexyLib:Hashing():Sign({record[2], record[3]}, keys[2], keys[1])
                if err then
                    logger:LogErrorL('binlog_error_signing_failed', typeName, name, err)
                    return false
                end
                record[4] = signature
            end
            return self:createRecord(record)
        end
    }
    network:NewChannel(DISTRIBUTE_CHANNEL, 'GUILD', function(sender, parsed)
        if sender == UnitName('player') then
            if parsed[1] then binlog.sharingRows = false end
            return
        end
        if parsed[1] then
            local succeeded, failed = 0, 0
            for _, record in pairs(parsed[2]) do
                if binlog:addRecord(record) then
                    succeeded = succeeded + 1
                else
                    failed = failed + 1
                end
            end
            logger:LogDebug('Received %d records of binlog %s from %s: %d succeeded, %d failed.', #parsed[2], name, sender, succeeded, failed)
        else
            if not binlog:addRecord(parsed[2]) then return end
            logger:LogDebug('Received record %s of binlog %s from %s.', record[1], name, sender)
        end
    end)
    network:NewChannel(POSITION_CHANNEL, 'GUILD', function(sender, position)
        local current = binlog:getData().position
        if current ~= nil and current >= position then return end
        local currentTime = time()
        if binlog.lastRequest ~= nil and currentTime - binlog.lastRequest < 60 then return end
        binlog.lastRequest = currentTime
        network:Send(REQUEST_CHANNEL, 'WHISPER', sender, current, 'NORMAL')
    end)
    network:NewChannel(REQUEST_CHANNEL, 'WHISPER', function(sender, position)
        if binlog.sharingRows or binlog.sharingSnapshot then return end
        local current = binlog:getData().position
        if current == nil or position ~= nil and position >= current then return end
        local records = binlog:GetRecords()
        if not records or records[1][2] > position + 1 then
            binlog.sharingSnapshot = true
            network:Send(SNAPSHOT_CHANNEL, 'GUILD', nil, {current, binlog:GetSnapshot()}, 'ALERT')
            return
        end
        local recordsToShare = {}
        for _, record in pairs(records) do
            if record[2] > position then
                recordsToShare[#recordsToShare + 1] = record
            end
        end
        if recordsToShare then
            binlog.sharingRows = true
            network:Send(DISTRIBUTE_CHANNEL, 'GUILD', nil, {true, recordsToShare})
        end
    end)
    network:NewChannel(SNAPSHOT_CHANNEL, 'GUILD', function(sender, parsed)
        if sender == UnitName('player') then
            binlog.sharingSnapshot = false
            logger:LogDebug('Shared snapshot of binlog %s.', name)
            return
        end
        local position, snapshot = parsed[1], parsed[2]
        local data = binlog:getData()
        local current = data.position
        if current ~= nil and current >= position then return end

        local modes = self.accessModesIndices or {#accessModes}
        local signMode, modeValid = snapshot._mode or 0, false
        for _, idx in pairs(modes) do
            if idx == signMode then
                modeValid = true
                break
            end
        end
        if not modeValid then
            logger:LogDebug('Received snapshot with invalid signing access mode %d from %s.', signMode, sender)
            return
        end
        if signMode then
            if not snapshot._sign then
                logger:LogDebug('Received snapshot with signing access mode %d and without signature from %s.', signMode, sender)
                return
            end
            local keys = accessModes[signMode]
            if not keys or not keys[1] then
                logger:LogDebug('Received snapshot of unknown access mode %d from %s.', signMode, sender)
                return
            end
            local signature = snapshot._sign
            snapshot._sign = nil
            snapshot._mode = nil
            if not SexyLib:Hashing():Validate(snapshot, signature, keys[1]) then
                logger:LogDebug('Snapshot verification from sender %s failed in binlog %s.', sender, name)
                return
            end
            snapshot._sign = signature
            snapshot._mode = signMode
        end

        data.records = {}
        data.snapshot = snapshot
        binlog.state = util:CopyTable(snapshot)
        data.position = position
        logger:LogDebug('Received snapshot with position %d of binlog %s from %s.', position, name, sender)
    end)
    C_Timer.NewTicker(30, function()
        local position = binlog:getData().position
        if position == nil then return end
        network:Send(POSITION_CHANNEL, 'GUILD', nil, position, 'NORMAL')
    end)
    return binlog
end

function SexyLib:InitBinlog(name, accessModes)
    binlogs[name] = newBinlog(name, accessModes)
end

function SexyLib:Binlog(name)
    return binlogs[name]
end