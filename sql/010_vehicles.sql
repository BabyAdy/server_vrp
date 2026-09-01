-- ==========================================================
--  PURPLE HAVOC - vehicule personale
--    users.slots        -> cate vehicule personale poate detine un jucator
--    player_vehicles    -> vehiculele detinute efectiv
--
--  ph_vehicles creeaza oricum astea la pornire daca lipsesc; e bine sa fie
--  si versionat aici.
-- ==========================================================

USE `purple_havoc`;

-- ----------------------------------------------------------
--  users: sloturi de vehicule
-- ----------------------------------------------------------
ALTER TABLE `users`
  ADD COLUMN IF NOT EXISTS `slots` TINYINT UNSIGNED NOT NULL DEFAULT 2 AFTER `playtime`;

-- ----------------------------------------------------------
--  player_vehicles
--    odometer  = metri parcursi (afisati ca km in HUD / /v)
--    park      = JSON {x,y,z,h}  - locul setat cu /park (butonul "Spawn")
--    last_pos  = JSON {x,y,z,h}  - ultimul loc din care s-a coborat
--                (butonul "Spawn Last Location"); NULL dupa distrugere / disconnect
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `player_vehicles` (
  `id`         INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  `owner_id`   INT UNSIGNED     NOT NULL,                       -- users.id
  `model`      VARCHAR(64)      NOT NULL,
  `label`      VARCHAR(64)      NOT NULL,
  `category`   ENUM('car','heli','boat') NOT NULL DEFAULT 'car',
  `plate`      VARCHAR(8)       NOT NULL DEFAULT '',
  `props`      LONGTEXT         NULL DEFAULT NULL,              -- JSON: culori / mods / plate custom
  `odometer`   BIGINT UNSIGNED  NOT NULL DEFAULT 0,            -- metri
  `fuel`       FLOAT            NOT NULL DEFAULT 100,           -- 0..100
  `park`       LONGTEXT         NULL DEFAULT NULL,
  `last_pos`   LONGTEXT         NULL DEFAULT NULL,
  `created_at` TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_pv_owner` (`owner_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
