<?php

declare(strict_types=1);

/**
 * Migração gradual de senhaAdmin: plaintext legado → password_hash.
 * Nunca usa MD5/SHA1. Compatível com PHP 7.4–8.2.
 */
final class PasswordHasher
{
    /**
     * @return string hash bcrypt/argon (PASSWORD_DEFAULT)
     */
    public static function hash($password)
    {
        $password = is_string($password) ? $password : '';
        if ($password === '') {
            throw new InvalidArgumentException('Senha vazia.');
        }

        $hash = password_hash($password, PASSWORD_DEFAULT);
        if (!is_string($hash) || $hash === '') {
            throw new RuntimeException('Falha ao gerar hash de senha.');
        }

        return $hash;
    }

    /**
     * @param mixed $stored
     */
    public static function looksLikePasswordHash($stored)
    {
        if (!is_string($stored) || $stored === '') {
            return false;
        }

        $info = password_get_info($stored);
        if (isset($info['algo']) && $info['algo'] !== 0 && $info['algo'] !== null) {
            return true;
        }

        return strpos($stored, '$2y$') === 0
            || strpos($stored, '$2a$') === 0
            || strpos($stored, '$2b$') === 0
            || strpos($stored, '$argon2') === 0;
    }

    /**
     * @param mixed $stored
     * @param mixed $password
     */
    public static function verify($password, $stored)
    {
        if (!is_string($password) || $password === '' || !is_string($stored) || $stored === '') {
            return false;
        }

        if (self::looksLikePasswordHash($stored)) {
            return password_verify($password, $stored);
        }

        return hash_equals($stored, $password);
    }

    /**
     * Autentica e, se o valor legado for plaintext, grava hash uma única vez.
     * UPDATE atômico: só reescreve se senhaAdmin ainda for o valor antigo.
     *
     * @return array{ok:bool,upgraded:bool}
     */
    public static function verifyAndUpgrade(PDO $pdo, $userId, $stored, $password)
    {
        $userId = (int) $userId;
        if ($userId < 1 || !self::verify($password, $stored)) {
            return array('ok' => false, 'upgraded' => false);
        }

        $needsHash = !self::looksLikePasswordHash($stored)
            || password_needs_rehash($stored, PASSWORD_DEFAULT);

        if (!$needsHash) {
            return array('ok' => true, 'upgraded' => false);
        }

        $hash = self::hash($password);
        $sql = $pdo->prepare(
            'UPDATE gs_Administrador
             SET senhaAdmin = :hash
             WHERE idAdmin = :id AND senhaAdmin = :old'
        );
        $sql->bindValue(':hash', $hash);
        $sql->bindValue(':id', $userId, PDO::PARAM_INT);
        $sql->bindValue(':old', $stored);
        $sql->execute();

        return array('ok' => true, 'upgraded' => $sql->rowCount() > 0);
    }

    /**
     * Token de sessão (coluna token). 32 hex cabem no VARCHAR(32) atual;
     * após o ALTER para VARCHAR(128) pode subir para random_bytes(32).
     */
    public static function newSessionToken()
    {
        return bin2hex(random_bytes(16));
    }
}
