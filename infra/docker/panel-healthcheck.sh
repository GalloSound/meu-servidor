#!/bin/sh
set -eu

php -r '
$fp = @fsockopen("127.0.0.1", 80, $errno, $errstr, 3);
if (!$fp) {
    fwrite(STDERR, "panel-healthcheck: $errstr\n");
    exit(1);
}
fwrite($fp, "GET / HTTP/1.0\r\nHost: localhost\r\n\r\n");
$line = fgets($fp);
fclose($fp);
if (!is_string($line) || !preg_match("#HTTP/\\S+\\s+(200|301|302|401)#", $line)) {
    fwrite(STDERR, "panel-healthcheck: resposta inesperada\n");
    exit(1);
}
'
