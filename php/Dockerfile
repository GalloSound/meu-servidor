ARG PHP_VERSION=8.2

FROM php:${PHP_VERSION}-apache

ENV TZ=America/Sao_Paulo
ENV COMPOSER_ALLOW_SUPERUSER=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libzip-dev \
        unzip \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" \
        gd \
        intl \
        mysqli \
        pdo_mysql \
        zip \
    && a2enmod rewrite headers \
    && printf '%s\n' 'ServerName localhost' > /etc/apache2/conf-available/servername.conf \
    && a2enconf servername \
    && mkdir -p /tmp/php-sessions \
    && chown -R www-data:www-data /tmp/php-sessions \
    && printf '%s\n' \
        'session.save_path=/tmp/php-sessions' \
        'upload_max_filesize=128M' \
        'post_max_size=128M' \
        'memory_limit=512M' \
        'max_execution_time=300' \
        > /usr/local/etc/php/conf.d/meu-servidor.ini \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

COPY www/index.php www/.htaccess ./

RUN printf '%s\n' \
    '<VirtualHost *:80>' \
    '    ServerName localhost' \
    '    DocumentRoot /var/www/html' \
    '' \
    '    Alias /app /var/www/html/app' \
    '    Alias /app_nf /var/www/html/app_nf' \
    '    Alias /app_sistema /var/www/html/app_sistema' \
    '    Alias /gsfacilfront/public /var/www/html/gsfacilfront/public' \
    '    Alias /gsfacilFront/public /var/www/html/gsfacilfront/public' \
    '    Alias /googlecalendar /var/www/html/googlecalendar' \
    '    Alias /peoplecontacts /var/www/html/peoplecontacts' \
    '    Alias /gallosoundsite /var/www/html/gallosoundsite' \
    '    Alias /apicontacts /var/www/html/peoplecontacts/public_html/apicontacts' \
    '    RedirectMatch 403 ^/gallosoundsite/(\\.git|\\.cursor|\\.svn|\\.hg)(/|$)' \
    '' \
    '    DirectoryIndex index.php' \
    '' \
    '    <Directory /var/www/html>' \
    '        Options FollowSymLinks' \
    '        AllowOverride All' \
    '        Require all granted' \
    '    </Directory>' \
    '' \
    '    # Public site hardening: block infra/repo leaks under this alias.' \
    '    <Directory /var/www/html/gallosoundsite>' \
    '        Options FollowSymLinks' \
    '        AllowOverride All' \
    '        Require all granted' \
    '' \
    '        <FilesMatch "(^\\.|^Config(\\.php|_exemple\\.php)$|^sftp-config\\.json$|\\.sql$|\\.bak$|\\.env$|\\.ini$|\\.log$)">' \
    '            Require all denied' \
    '        </FilesMatch>' \
    '    </Directory>' \
    '' \
    '    ErrorLog ${APACHE_LOG_DIR}/error.log' \
    '    CustomLog ${APACHE_LOG_DIR}/access.log combined' \
    '</VirtualHost>' \
    > /etc/apache2/sites-available/000-default.conf

RUN printf '%s\n' \
    '#!/bin/sh' \
    'set -e' \
    '' \
    'mkdir -p /tmp/php-sessions' \
    'ln -sfn /var/www/html/app /var/www/app' \
    'ln -sfn /var/www/html/app_nf /var/www/app_nf' \
    'ln -sfn /var/www/html/gsfacilfront /var/www/gsfacilfront' \
    'ln -sfn /var/www/html/peoplecontacts /var/www/peoplecontacts' \
    'ln -sfn /var/www/html/gallosoundsite /var/www/gallosoundsite' \
    '' \
    'if [ -f /var/www/html/app/composer.json ] && [ ! -f /var/www/html/app/vendor/autoload.php ]; then' \
    '    composer install --working-dir=/var/www/html/app --no-dev --prefer-dist --no-interaction --no-progress --optimize-autoloader' \
    'fi' \
    '' \
    'if [ -f /var/www/html/app_nf/composer.json ] && [ ! -f /var/www/html/app_nf/vendor/autoload.php ]; then' \
    '    composer install --working-dir=/var/www/html/app_nf --no-dev --prefer-dist --no-interaction --no-progress --optimize-autoloader' \
    'fi' \
    '' \
    'if [ -f /var/www/html/app_sistema/composer.json ] && [ ! -f /var/www/html/app_sistema/vendor/autoload.php ]; then' \
    '    composer install --working-dir=/var/www/html/app_sistema --no-dev --prefer-dist --no-interaction --no-progress --optimize-autoloader' \
    'fi' \
    '' \
    'if [ -f /var/www/html/gsfacilfront/composer.json ] && [ ! -f /var/www/html/gsfacilfront/vendor/autoload.php ]; then' \
    '    composer install --working-dir=/var/www/html/gsfacilfront --no-dev --prefer-dist --no-interaction --no-progress --optimize-autoloader' \
    'fi' \
    '' \
    'if [ -f /var/www/html/peoplecontacts/composer.json ] && [ ! -f /var/www/html/peoplecontacts/vendor/autoload.php ]; then' \
    '    composer install --working-dir=/var/www/html/peoplecontacts --no-dev --prefer-dist --no-interaction --no-progress --optimize-autoloader' \
    'fi' \
    '' \
    'exec apache2-foreground' \
    > /usr/local/bin/meu-servidor-php-entrypoint \
    && chmod +x /usr/local/bin/meu-servidor-php-entrypoint

CMD ["meu-servidor-php-entrypoint"]
