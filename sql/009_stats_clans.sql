-- ==========================================================
--  PURPLE HAVOC - coloane pentru /stats + tabelul `clans`
--  Resursele le creeaza si singure la pornire (ph-core / ph_chat).
-- ==========================================================

USE `purple_havoc`;

-- ----------------------------------------------------------
--  users: warn-uri (toate plafonate la 3) + apartenenta la clan
-- ----------------------------------------------------------
ALTER TABLE `users`
  ADD COLUMN IF NOT EXISTS `warns`        TINYINT      NOT NULL DEFAULT 0 AFTER `playtime`,  -- warn-uri de jucator (Info)
  ADD COLUMN IF NOT EXISTS `staff_warns`  TINYINT      NOT NULL DEFAULT 0 AFTER `warns`,     -- SW (Admin / Helper)
  ADD COLUMN IF NOT EXISTS `leader_warns` TINYINT      NOT NULL DEFAULT 0 AFTER `staff_warns`,-- LW (Leader)
  ADD COLUMN IF NOT EXISTS `clan`         INT UNSIGNED NOT NULL DEFAULT 0 AFTER `leader_warns`,
  ADD COLUMN IF NOT EXISTS `clan_rank`    TINYINT      NOT NULL DEFAULT 0 AFTER `clan`,       -- 0 = fara ; 1..7
  ADD COLUMN IF NOT EXISTS `clan_warns`   TINYINT      NOT NULL DEFAULT 0 AFTER `clan_rank`,  -- CW
  ADD COLUMN IF NOT EXISTS `clan_join`    DATETIME     NULL DEFAULT NULL  AFTER `clan_warns`;

-- ----------------------------------------------------------
--  chat: scala interfetei de chat (procent), persistata ca la chat_lines
-- ----------------------------------------------------------
ALTER TABLE `users`
  ADD COLUMN IF NOT EXISTS `chat_scale` SMALLINT NOT NULL DEFAULT 100 AFTER `pc_hidden`;

-- ----------------------------------------------------------
--  clans  (schelet - mirror simplu al `factions`; sistemul de clanuri
--          propriu-zis vine separat, deocamdata doar citit de /stats)
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `clans` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `c_name`     VARCHAR(64)  NOT NULL,
  `c_short`    VARCHAR(12)  NOT NULL DEFAULT '',
  `ranks`      LONGTEXT     NOT NULL,                 -- JSON: 7 denumiri ["Rank 1"..."Co-Leader","Leader"]
  `leader`     INT UNSIGNED NULL DEFAULT NULL,        -- users.id
  `active`     TINYINT(1)   NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_clans_name` (`c_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
