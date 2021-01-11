if SexyLib.Localization and not SexyLib:Localization('Sexy Lib'):IsPresent('binlog_error_type_exists') then
    SexyLib:Localization('Sexy Lib'):Add({
        binlog_error_type_exists = 'Record type %s already exists for binlog %s.',
        binlog_error_no_type = 'Record type %s does not exist for binlog %s.',
        binlog_error_wrong_access_mode = 'There is no access mode %d present for binlog %s.',
        binlog_error_no_signature_in_record = 'No signature could be found on record that is being added to binlog %s.',
        binlog_error_cant_sign = 'You can not sign record of type %s for binlog %s.',
        binlog_error_signing_failed = 'Error occurred whilst signing record of type %s for binlog %s: %s.',
        binlog_error_signing_snapshot_failed = 'Error occurred whilst signing snapshot for binlog %s: %s.'
    })
end