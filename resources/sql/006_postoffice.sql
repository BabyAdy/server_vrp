-- ==========================================================
--  PURPLE HAVOC - post office (ph_postoffice)
--  Iteme puse deoparte cand inventarul jucatorului nu incape
--  (ex: la expirarea unui abonament cu sloturi bonus).
--  ph_postoffice creeaza si el tabelul la pornire daca lipseste.
-- ==========================================================

USE `purple_havoc`;

CREATE TABLE IF NOT EXISTS `post_office_items` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    INT UNSIGNED NOT NULL,
  `name`       VARCHAR(64)  NOT NULL,
  `count`      INT          NOT NULL DEFAULT 1,
  `meta`       LONGTEXT     NULL DEFAULT NULL,
  `reason`     VARCHAR(128) NULL DEFAULT NULL,
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `claimed_at` TIMESTAMP    NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_po_user` (`user_id`, `claimed_at`),
  CONSTRAINT `fk_post_office_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
