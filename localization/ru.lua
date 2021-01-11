if SexyLib.Localization and GetLocale() == 'ruRu' then
    SexyLib:Localization('Sexy Lib'):Add({
        binlog_error_type_exists = 'Тип записи %s уже существует для бинлога %s.',
        binlog_error_no_type = 'Тип записи %s не существует для бинлога %s.',
        binlog_error_wrong_access_mode = 'Уровень доступа %d не определен для бинлога %s.',
        binlog_error_no_signature_in_record = 'При попытке добавить запись в бинлог %s не найдена подпись.',
        binlog_error_cant_sign = 'Вы не можете подписать запись типа %s для бинлога %s.',
        binlog_error_signing_failed = 'Ошибка подписи записи типа %s для бинлога %s: %s.',
        binlog_error_signing_snapshot_failed = 'Ошибка подписи снепшота для бинлога %s: %s.'
    })
end