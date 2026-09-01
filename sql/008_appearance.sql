-- ==========================================================
--  PURPLE HAVOC - character appearance (ph_appearance)
--  ph_appearance creeaza si el aceste tabele la pornire daca lipsesc.
-- ==========================================================

USE `purple_havoc`;

-- `users.appearance` (LONGTEXT, JSON) exista deja din ph-core.
-- El tine aspectul LIVE al personajului (fata / heritage / par / overlays / ochi).
-- Hainele NU se tin aici - se aplica automat din Config.DefaultOutfit.

-- ----------------------------------------------------------
--  character_templates
--    Preset-uri de aspect salvate din /editcharacter ("Save Character"),
--    unul per (user_id, gender).  La un /editcharacter urmator, cand se
--    selecteaza acel gen, preset-ul se poate re-incarca.
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `character_templates` (
  `user_id`    INT UNSIGNED NOT NULL,
  `gender`     TINYINT      NOT NULL,          -- 0 = male, 1 = female
  `appearance` LONGTEXT     NOT NULL,          -- JSON (acelasi format ca users.appearance)
  `updated_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`, `gender`),
  CONSTRAINT `fk_ctpl_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
