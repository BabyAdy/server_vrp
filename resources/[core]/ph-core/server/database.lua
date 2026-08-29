PH = PH or {}
PH.DB = PH.DB or { ready = false }

local USERS_SQL = [[
CREATE TABLE IF NOT EXISTS `users` (
  `id`            INT UNSIGNED    NOT NULL AUTO_INCREMENT,
  `username`      VARCHAR(24)     NOT NULL,
  `email`         VARCHAR(120)    NOT NULL,
  `password`      VARCHAR(255)    NOT NULL,
  `license`       VARCHAR(64)     NOT NULL,
  `dob`           DATE            NULL DEFAULT NULL,
  `gender`        TINYINT         NOT NULL DEFAULT 0,
  `height`        SMALLINT        NOT NULL DEFAULT 180,
  `level`         INT UNSIGNED    NOT NULL DEFAULT 1,
  `rp`            BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `money`         BIGINT          NOT NULL DEFAULT 500,
  `bank`          BIGINT          NOT NULL DEFAULT 0,
  `premiumpoints` INT UNSIGNED    NOT NULL DEFAULT 0,
  `appearance`    LONGTEXT        NULL DEFAULT NULL,
  `playtime`      INT UNSIGNED    NOT NULL DEFAULT 0,
  `created_at`    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_login`    TIMESTAMP       NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_users_username` (`username`),
  UNIQUE KEY `uq_users_email`    (`email`),
  UNIQUE KEY `uq_users_license`  (`license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]]

CreateThread(function()
    -- asteapta oxmysql
    while GetResourceState('oxmysql') ~= 'started' do
        Wait(200)
    end

    local ok, err = pcall(function()
        MySQL.query.await(USERS_SQL)
    end)

    if not ok then
        print('^1[ph-core] EROARE la initializarea bazei de date:^7 ' .. tostring(err))
        print('^1[ph-core] Verifica `set mysql_connection_string` din server.cfg.^7')
        return
    end

    PH.DB.ready = true
    PH.Log('Baza de date este pregatita (tabel `users`).')
end)

exports('IsDatabaseReady', function()
    return PH.DB.ready == true
end)
