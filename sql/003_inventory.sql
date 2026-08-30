-- ==========================================================
--  PURPLE HAVOC - ph_inventory
--  ph_inventory adauga si el aceste coloane la pornire daca lipsesc.
-- ==========================================================

USE `purple_havoc`;

ALTER TABLE `users`
  ADD COLUMN IF NOT EXISTS `inventory` LONGTEXT NULL DEFAULT NULL AFTER `appearance`,
  ADD COLUMN IF NOT EXISTS `inv_slots` SMALLINT NOT NULL DEFAULT 100 AFTER `inventory`;
