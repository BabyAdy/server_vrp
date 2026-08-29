/*
 * ph-core / server / crypto.js
 * ----------------------------------------------------------
 * Hashing de parole fara dependinte externe (foloseste modulul
 * `crypto` din runtime-ul Node al serverului FiveM).
 *
 * Format stocat in DB:  scrypt$<salt_hex>$<hash_hex>
 *
 * Expus catre Lua ca export-uri:
 *   exports['ph-core']:hashPassword(plain)      -> string
 *   exports['ph-core']:verifyPassword(plain, stored) -> boolean
 */

const crypto = require('crypto');

const KEYLEN = 64;
const SCRYPT_OPTS = { N: 16384, r: 8, p: 1 };

function hashPassword(plain) {
    const salt = crypto.randomBytes(16).toString('hex');
    const derived = crypto
        .scryptSync(String(plain), salt, KEYLEN, SCRYPT_OPTS)
        .toString('hex');
    return `scrypt$${salt}$${derived}`;
}

function verifyPassword(plain, stored) {
    try {
        if (typeof stored !== 'string') return false;
        const parts = stored.split('$');
        if (parts.length !== 3 || parts[0] !== 'scrypt') return false;

        const [, salt, hashHex] = parts;
        const derived = crypto.scryptSync(String(plain), salt, KEYLEN, SCRYPT_OPTS);
        const expected = Buffer.from(hashHex, 'hex');

        if (expected.length !== derived.length) return false;
        return crypto.timingSafeEqual(expected, derived);
    } catch (err) {
        console.log(`[ph-core] verifyPassword error: ${err.message}`);
        return false;
    }
}

exports('hashPassword', hashPassword);
exports('verifyPassword', verifyPassword);
