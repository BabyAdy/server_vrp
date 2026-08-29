-- ==========================================================
--  PURPLE HAVOC - schema initiala (v1)
--  Structura tip SAMP / RageMP: un singur tabel `users`
--  (cont = personaj, un personaj / cont, legat de licenta FiveM).
--
--  ph-core creeaza oricum tabelul la pornire daca lipseste,
--  dar este bine sa il ai versionat aici.
-- ==========================================================

CREATE DATABASE IF NOT EXISTS `purple_havoc`
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

USE `purple_havoc`;

CREATE TABLE IF NOT EXISTS `users` (
  `id`            INT UNSIGNED    NOT NULL AUTO_INCREMENT,
  `username`      VARCHAR(24)     NOT NULL,               -- si numele in joc
  `email`         VARCHAR(120)    NOT NULL,
  `password`      VARCHAR(255)    NOT NULL,               -- hash scrypt
  `license`       VARCHAR(64)     NOT NULL,

  -- date de personaj (NULL pana la creare; dob IS NULL => fara personaj)
  `dob`           DATE            NULL DEFAULT NULL,
  `gender`        TINYINT         NOT NULL DEFAULT 0,     -- 0 = masculin, 1 = feminin
  `height`        SMALLINT        NOT NULL DEFAULT 180,   -- cm
  `level`         INT UNSIGNED    NOT NULL DEFAULT 1,
  `rp`            BIGINT UNSIGNED NOT NULL DEFAULT 0,     -- respect / experienta
  `money`         BIGINT          NOT NULL DEFAULT 500,   -- cash
  `bank`          BIGINT          NOT NULL DEFAULT 0,
  `premiumpoints` INT UNSIGNED    NOT NULL DEFAULT 0,
  `appearance`    LONGTEXT        NULL DEFAULT NULL,      -- JSON (editor de aspect - v2)
  `playtime`      INT UNSIGNED    NOT NULL DEFAULT 0,     -- secunde jucate

  `created_at`    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_login`    TIMESTAMP       NULL DEFAULT NULL,

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_users_username` (`username`),
  UNIQUE KEY `uq_users_email`    (`email`),
  UNIQUE KEY `uq_users_license`  (`license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
