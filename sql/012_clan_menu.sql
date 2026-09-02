-- ==========================================================
--  PURPLE HAVOC - Clan System Faza 2 (meniul /clan + vehicule de clan)
--
--  Coloane noi pe `clan_vehicles` pentru Buy / Sell / Upgrade.
--  ph_clans le creeaza oricum la pornire daca lipsesc (server.lua -> migrate()).
-- ==========================================================

USE `purple_havoc`;

ALTER TABLE `clan_vehicles`
  ADD COLUMN IF NOT EXISTS `upgrade`   TINYINT      NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `bought_by` INT UNSIGNED NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `bought_at` TIMESTAMP    NULL DEFAULT NULL;
