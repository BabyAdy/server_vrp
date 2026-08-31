-- ==========================================================
--  PURPLE HAVOC - sistem de factiuni (ph_factions)
--  ph_factions creeaza si el aceste tabele / coloane la pornire daca lipsesc.
-- ==========================================================

USE `purple_havoc`;

-- ----------------------------------------------------------
--  factions
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `factions` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,          -- ID-ul factiunii
  `f_name`     VARCHAR(64)  NOT NULL,                         -- Numele factiunii
  `f_short`    VARCHAR(12)  NOT NULL DEFAULT '',              -- tag scurt (chat / duty)
  `ranks`      LONGTEXT     NOT NULL,                         -- JSON: 7 denumiri ["Rank 1"..."Co-Leader","Leader"]
  `leader`     INT UNSIGNED NULL DEFAULT NULL,               -- users.id (username se extrage)
  `manager`    INT UNSIGNED NULL DEFAULT NULL,               -- users.id (username se extrage)
  `hq_enter`   LONGTEXT     NULL DEFAULT NULL,               -- JSON {x,y,z,h}  intrare HQ (vw 0): blip + textdraw + [E]
  `hq_exit`    LONGTEXT     NULL DEFAULT NULL,               -- JSON {x,y,z,h}  interior HQ (vw separat): [E] iesire
  `hq_vw`      INT          NOT NULL DEFAULT 0,               -- routing bucket interior; 0 => auto (HQBucketBase + id)
  `blip`       LONGTEXT     NULL DEFAULT NULL,               -- JSON {sprite,color,scale}
  `vgarage`    LONGTEXT     NULL DEFAULT NULL,               -- JSON {label,x,y,z,h, sx,sy,sz,sh}  garaj masini
  `hgarage`    LONGTEXT     NULL DEFAULT NULL,               -- garaj heliuri
  `bgarage`    LONGTEXT     NULL DEFAULT NULL,               -- garaj barci
  `active`     TINYINT(1)   NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_factions_name` (`f_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------
--  faction_vehicles  (masinile de factiune, pe rank-uri; custom sau vanilla)
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `faction_vehicles` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `faction_id` INT UNSIGNED NOT NULL,
  `category`   ENUM('car','heli','boat') NOT NULL DEFAULT 'car',
  `model`      VARCHAR(64)  NOT NULL,                         -- spawn name (vanilla acum, custom ulterior)
  `label`      VARCHAR(64)  NOT NULL,
  `min_rank`   TINYINT      NOT NULL DEFAULT 1,               -- 1..7
  `props`      LONGTEXT     NULL DEFAULT NULL,                -- JSON: culori / mods (pentru custom)
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_fv` (`faction_id`, `category`, `min_rank`),
  CONSTRAINT `fk_fv_faction` FOREIGN KEY (`faction_id`) REFERENCES `factions` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------
--  faction_logs  (join / leave / promote / warn / kick / vehicle ...)
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `faction_logs` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `faction_id`  INT UNSIGNED NOT NULL,
  `actor_id`    INT UNSIGNED NULL,
  `actor_name`  VARCHAR(24)  NULL,
  `action`      VARCHAR(32)  NOT NULL,
  `target_id`   INT UNSIGNED NULL,
  `target_name` VARCHAR(24)  NULL,
  `detail`      VARCHAR(255) NULL,
  `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_flog` (`faction_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------
--  users: apartenenta la factiune
-- ----------------------------------------------------------
ALTER TABLE `users`
  ADD COLUMN IF NOT EXISTS `faction`       INT UNSIGNED NOT NULL DEFAULT 0  AFTER `staff`,  -- factions.id (0 = fara)
  ADD COLUMN IF NOT EXISTS `faction_rank`  TINYINT      NOT NULL DEFAULT 0  AFTER `faction`, -- 0 = fara; 1..7
  ADD COLUMN IF NOT EXISTS `is_tester`     TINYINT(1)   NOT NULL DEFAULT 0  AFTER `faction_rank`,
  ADD COLUMN IF NOT EXISTS `is_supervisor` TINYINT(1)   NOT NULL DEFAULT 0  AFTER `is_tester`,
  ADD COLUMN IF NOT EXISTS `faction_join`  DATETIME     NULL DEFAULT NULL   AFTER `is_supervisor`,
  ADD COLUMN IF NOT EXISTS `faction_warns` TINYINT      NOT NULL DEFAULT 0  AFTER `faction_join`;
