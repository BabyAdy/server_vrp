-- ==========================================================
--  PURPLE HAVOC - staff_menu (tickets / bans / warns / logs)
--  staff_menu creeaza si el aceste tabele la pornire daca lipsesc,
--  dar le tii versionate aici.
-- ==========================================================

USE `purple_havoc`;

-- ----------------------------------------------------------
--  Tickete create de jucatori prin /ticket
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `tickets` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`       INT UNSIGNED NOT NULL,                 -- users.id al celui care a deschis
  `username`      VARCHAR(24)  NOT NULL,                 -- snapshot nume
  `category`      VARCHAR(32)  NOT NULL DEFAULT 'general',
  `message`       TEXT         NOT NULL,
  `status`        ENUM('open','active','closed') NOT NULL DEFAULT 'open',
  `assigned_to`   INT UNSIGNED NULL,                     -- users.id al staff-ului care a acceptat
  `assigned_name` VARCHAR(24)  NULL,
  `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `closed_at`     TIMESTAMP    NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_tickets_status` (`status`),
  KEY `idx_tickets_assigned` (`assigned_to`),
  CONSTRAINT `fk_tickets_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------
--  Raspunsuri pe tickete (staff <-> jucator)
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `ticket_replies` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `ticket_id`   INT UNSIGNED NOT NULL,
  `author_id`   INT UNSIGNED NOT NULL,                   -- users.id
  `author_name` VARCHAR(24)  NOT NULL,
  `is_staff`    TINYINT(1)   NOT NULL DEFAULT 0,
  `message`     TEXT         NOT NULL,
  `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_replies_ticket` (`ticket_id`),
  CONSTRAINT `fk_replies_ticket` FOREIGN KEY (`ticket_id`) REFERENCES `tickets` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------
--  Log de actiuni staff
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `staff_logs` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `staff_id`    INT UNSIGNED NOT NULL,
  `staff_name`  VARCHAR(24)  NOT NULL,
  `action`      VARCHAR(32)  NOT NULL,
  `target_id`   INT UNSIGNED NULL,
  `target_name` VARCHAR(24)  NULL,
  `detail`      TEXT         NULL,
  `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_logs_staff` (`staff_id`),
  KEY `idx_logs_action` (`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------
--  Ban-uri (expires_at = UNIX timestamp secunde; NULL = permanent)
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `bans` (
  `id`             INT UNSIGNED   NOT NULL AUTO_INCREMENT,
  `user_id`        INT UNSIGNED   NULL,
  `license`        VARCHAR(64)    NOT NULL,
  `username`       VARCHAR(24)    NULL,
  `reason`         TEXT           NOT NULL,
  `banned_by`      INT UNSIGNED   NULL,
  `banned_by_name` VARCHAR(24)    NULL,
  `created_at`     TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_at`     BIGINT UNSIGNED NULL,
  `active`         TINYINT(1)     NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `idx_bans_license` (`license`),
  KEY `idx_bans_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------
--  Avertismente
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `warns` (
  `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`        INT UNSIGNED NOT NULL,
  `username`       VARCHAR(24)  NOT NULL,
  `reason`         TEXT         NOT NULL,
  `warned_by`      INT UNSIGNED NULL,
  `warned_by_name` VARCHAR(24)  NULL,
  `created_at`     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_warns_user` (`user_id`),
  CONSTRAINT `fk_warns_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
