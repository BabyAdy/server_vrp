-- ==========================================================
--  PURPLE HAVOC - user_session
--  Mapare intre "session id" (server id-ul FiveM, volatil) si
--  "sql id" = `users.id` (stabil).  ph-core intretine acest tabel
--  la conectare / deconectare; toate resursele lucreaza pe user_id.
--
--  ph-core creeaza si el acest tabel la pornire daca lipseste.
-- ==========================================================

USE `purple_havoc`;

CREATE TABLE IF NOT EXISTS `user_session` (
  `user_id`    INT UNSIGNED NOT NULL,             -- = users.id (cheia stabila peste reconectari)
  `session_id` INT          NOT NULL DEFAULT 0,   -- server id FiveM al sesiunii curente (0 = offline)
  `license`    VARCHAR(64)  NOT NULL DEFAULT '',
  `username`   VARCHAR(24)  NOT NULL DEFAULT '',
  `online`     TINYINT(1)   NOT NULL DEFAULT 0,
  `last_seen`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`),
  KEY `idx_user_session_sid`    (`session_id`),
  KEY `idx_user_session_online` (`online`),
  CONSTRAINT `fk_user_session_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- la un restart curat nu exista sesiuni active
UPDATE `user_session` SET `online` = 0, `session_id` = 0 WHERE `online` = 1;
