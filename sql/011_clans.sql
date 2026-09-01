-- ==========================================================
--  PURPLE HAVOC - shop (Premium Points) + sistemul de clanuri
--
--    users.phone            - numar de telefon rezervat din /shop (unic, A-Z0-9)
--    users.clan_perms       - permisiuni de clan (CSV: changerank,vehmgmt,invite,kick,warn)
--    users.clan_tag_style   - stilul de tag ales cu /clantag (0..5)
--    users.clan_chat_hidden - /togc
--
--  `clans` era doar un schelet (sql/009); aici capata restul coloanelor.
--  clan_requests / clan_vehicles / clan_logs - noi.
--
--  ph_clans creeaza oricum toate astea la pornire daca lipsesc.
-- ==========================================================

USE `purple_havoc`;

-- ----------------------------------------------------------
--  users
-- ----------------------------------------------------------
ALTER TABLE `users`
  ADD COLUMN IF NOT EXISTS `phone`            VARCHAR(10) NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `clan_perms`       VARCHAR(64) NOT NULL DEFAULT '' AFTER `clan_warns`,
  ADD COLUMN IF NOT EXISTS `clan_tag_style`   TINYINT     NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `clan_chat_hidden` TINYINT     NOT NULL DEFAULT 0;

-- unic pe telefon (ignora eroarea daca deja exista)
ALTER TABLE `users` ADD UNIQUE KEY `uq_users_phone` (`phone`);

-- ----------------------------------------------------------
--  clans  (extinde scheletul din sql/009_stats_clans.sql)
-- ----------------------------------------------------------
ALTER TABLE `clans`
  ADD COLUMN IF NOT EXISTS `c_tag`          VARCHAR(5)   NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS `founder`        INT UNSIGNED NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `expires_at`     DATETIME     NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `money`          BIGINT       NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `premiumpoints`  BIGINT       NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `clan_points`    BIGINT       NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `chat_color`     VARCHAR(9)   NOT NULL DEFAULT '#b98cff',
  ADD COLUMN IF NOT EXISTS `rank_colors`    LONGTEXT     NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `motd`           VARCHAR(200) NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS `chat_lock_rank` TINYINT      NOT NULL DEFAULT 1;

-- ----------------------------------------------------------
--  clan_requests  (cererile de creare din /shop -> /clanreq)
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `clan_requests` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    INT UNSIGNED NOT NULL,
  `c_name`     VARCHAR(25)  NOT NULL,
  `c_tag`      VARCHAR(5)   NOT NULL,
  `status`     ENUM('pending','accepted','rejected') NOT NULL DEFAULT 'pending',
  `decided_by` INT UNSIGNED NULL DEFAULT NULL,
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), KEY `idx_cr_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------
--  clan_vehicles  (folosite de meniul de clan - Faza 2)
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `clan_vehicles` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `clan_id`    INT UNSIGNED NOT NULL,
  `model`      VARCHAR(64)  NOT NULL,
  `label`      VARCHAR(64)  NOT NULL,
  `category`   ENUM('car','heli','boat') NOT NULL DEFAULT 'car',
  `plate`      VARCHAR(8)   NOT NULL DEFAULT '',
  `props`      LONGTEXT     NULL DEFAULT NULL,
  `park`       LONGTEXT     NULL DEFAULT NULL,
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), KEY `idx_cv_clan` (`clan_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------
--  clan_logs
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `clan_logs` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `clan_id`    INT UNSIGNED NOT NULL,
  `actor_id`   INT UNSIGNED NULL, `actor_name` VARCHAR(24) NULL,
  `action`     VARCHAR(32)  NOT NULL,
  `target_id`  INT UNSIGNED NULL, `target_name` VARCHAR(24) NULL,
  `detail`     VARCHAR(255) NULL,
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), KEY `idx_clog` (`clan_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
