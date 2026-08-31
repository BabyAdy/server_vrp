-- ==========================================================
--  PURPLE HAVOC - abonamente (ph_subscriptions)
--  Gold / Platinum, cu data de expirare ca unix epoch (secunde).
--  0 sau in trecut = inactiv.  ph_subscriptions creeaza si el tabelul
--  la pornire daca lipseste.
-- ==========================================================

USE `purple_havoc`;

CREATE TABLE IF NOT EXISTS `subscriptions` (
  `user_id`             INT UNSIGNED    NOT NULL,
  `gold_expires_at`     BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `platinum_expires_at` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `updated_at`          TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_subscriptions_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- optiuni de chat per user (folosite de ph_chat)
ALTER TABLE `users`
  ADD COLUMN IF NOT EXISTS `chat_lines` SMALLINT     NOT NULL DEFAULT 10 AFTER `inv_slots`,
  ADD COLUMN IF NOT EXISTS `pc_hidden`  TINYINT(1)   NOT NULL DEFAULT 0  AFTER `chat_lines`;
