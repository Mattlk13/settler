#!/usr/bin/env bash
export DEBIAN_FRONTEND=noninteractive
SKIP_PHP=false
SKIP_MYSQL=false
SKIP_POSTGRESQL=false

echo "### Settler Build Configuration ###"
echo "SKIP_PHP         = ${SKIP_PHP}"
echo "SKIP_MYSQL       = ${SKIP_MYSQL}"
echo "SKIP_POSTGRESQL  = ${SKIP_POSTGRESQL}"
echo "### Settler Build Configuration ###"

# Update Package List
apt-get update

# Update System Packages
apt-get upgrade -y

# Force Locale
echo "LC_ALL=en_US.UTF-8" >> /etc/default/locale
locale-gen en_US.UTF-8

apt-get install -y software-properties-common curl gnupg debian-keyring debian-archive-keyring apt-transport-https

# Install Some PPAs
apt-add-repository ppa:ondrej/php -y
apt-add-repository ppa:chris-lea/redis-server -y

# NodeJS
curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -

# PostgreSQL
tee /etc/apt/sources.list.d/pgdg.list <<END
deb http://apt.postgresql.org/pub/repos/apt/ focal-pgdg main
END

wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

## Update Package Lists
apt-get update -y

# Install Some Basic Packages
apt-get install -y build-essential dos2unix gcc git git-lfs libmcrypt4 libpcre3-dev libpng-dev chrony unzip make \
python3-pip re2c supervisor unattended-upgrades whois vim libnotify-bin pv cifs-utils bash-completion zsh \
graphviz avahi-daemon tshark

# Set My Timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

if "$SKIP_PHP"; then
  echo "SKIP_PHP is being used, so we're not installing PHP"
else
  # Install Generic PHP packages
  apt-get install -y --allow-change-held-packages \
  php-imagick php-memcached php-redis php-xdebug php-dev php-swoole imagemagick mcrypt

  # PHP 8.0
  apt-get install -y --allow-change-held-packages \
  php8.0 php8.0-bcmath php8.0-bz2 php8.0-cgi php8.0-cli php8.0-common php8.0-curl php8.0-dba php8.0-dev \
  php8.0-enchant php8.0-fpm php8.0-gd php8.0-gmp php8.0-imap php8.0-interbase php8.0-intl php8.0-ldap \
  php8.0-mbstring php8.0-mysql php8.0-odbc php8.0-opcache php8.0-pgsql php8.0-phpdbg php8.0-pspell php8.0-readline \
  php8.0-snmp php8.0-soap php8.0-sqlite3 php8.0-sybase php8.0-tidy php8.0-xdebug php8.0-xml php8.0-xsl php8.0-zip \
  php8.0-memcached

  update-alternatives --set php /usr/bin/php8.0
  update-alternatives --set php-config /usr/bin/php-config8.0
  update-alternatives --set phpize /usr/bin/phpize8.0

  # Install Composer
  curl -sS https://getcomposer.org/installer | php
  mv composer.phar /usr/local/bin/composer
  chown -R vagrant:vagrant /home/vagrant/.config

  # Install Global Packages
  sudo su vagrant <<'EOF'
  /usr/local/bin/composer global require "laravel/envoy=^2.0"
  /usr/local/bin/composer global require "laravel/installer=^4.0.2"
  /usr/local/bin/composer global require "laravel/spark-installer=dev-master"
  /usr/local/bin/composer global require "slince/composer-registry-manager=^2.0"
EOF

  # Set Some PHP CLI Settings
  sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/8.0/cli/php.ini
  sed -i "s/display_errors = .*/display_errors = On/" /etc/php/8.0/cli/php.ini
  sed -i "s/memory_limit = .*/memory_limit = 512M/" /etc/php/8.0/cli/php.ini
  sed -i "s/;date.timezone.*/date.timezone = UTC/" /etc/php/8.0/cli/php.ini

  # Install Apache
  apt-get install -y apache2 libapache2-mod-fcgid
  sed -i "s/www-data/vagrant/" /etc/apache2/envvars

  # Enable FPM
  a2enconf php8.0-fpm

  # Assume user wants mode_rewrite support
  sudo a2enmod rewrite

  # Turn on HTTPS support
  sudo a2enmod ssl

  # Turn on proxy & fcgi
  sudo a2enmod proxy proxy_fcgi

  # Turn on headers support
  sudo a2enmod headers actions alias

  # Add Mutex to config to prevent auto restart issues
  if [ -z "$(grep '^Mutex posixsem$' /etc/apache2/apache2.conf)" ]
  then
      echo 'Mutex posixsem' | sudo tee -a /etc/apache2/apache2.conf
  fi

  a2dissite 000-default
  systemctl disable apache2

  # Install Nginx
  apt-get install -y --allow-downgrades --allow-remove-essential --allow-change-held-packages nginx

  rm /etc/nginx/sites-enabled/default
  rm /etc/nginx/sites-available/default

  # Create a configuration file for Nginx overrides.
  mkdir -p /home/vagrant/.config/nginx
  chown -R vagrant:vagrant /home/vagrant
  touch /home/vagrant/.config/nginx/nginx.conf
  ln -sf /home/vagrant/.config/nginx/nginx.conf /etc/nginx/conf.d/nginx.conf

  # Setup Some PHP-FPM Options
  sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/8.0/fpm/php.ini
  sed -i "s/display_errors = .*/display_errors = On/" /etc/php/8.0/fpm/php.ini
  sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php/8.0/fpm/php.ini
  sed -i "s/memory_limit = .*/memory_limit = 512M/" /etc/php/8.0/fpm/php.ini
  sed -i "s/upload_max_filesize = .*/upload_max_filesize = 100M/" /etc/php/8.0/fpm/php.ini
  sed -i "s/post_max_size = .*/post_max_size = 100M/" /etc/php/8.0/fpm/php.ini
  sed -i "s/;date.timezone.*/date.timezone = UTC/" /etc/php/8.0/fpm/php.ini

  printf "[openssl]\n" | tee -a /etc/php/8.0/fpm/php.ini
  printf "openssl.cainfo = /etc/ssl/certs/ca-certificates.crt\n" | tee -a /etc/php/8.0/fpm/php.ini

  printf "[curl]\n" | tee -a /etc/php/8.0/fpm/php.ini
  printf "curl.cainfo = /etc/ssl/certs/ca-certificates.crt\n" | tee -a /etc/php/8.0/fpm/php.ini

  # Disable XDebug On The CLI
  sudo phpdismod -s cli xdebug

  # Set The Nginx & PHP-FPM User
  sed -i "s/user www-data;/user vagrant;/" /etc/nginx/nginx.conf
  sed -i "s/# server_names_hash_bucket_size.*/server_names_hash_bucket_size 64;/" /etc/nginx/nginx.conf

  sed -i "s/user = www-data/user = vagrant/" /etc/php/8.0/fpm/pool.d/www.conf
  sed -i "s/group = www-data/group = vagrant/" /etc/php/8.0/fpm/pool.d/www.conf

  sed -i "s/listen\.owner.*/listen.owner = vagrant/" /etc/php/8.0/fpm/pool.d/www.conf
  sed -i "s/listen\.group.*/listen.group = vagrant/" /etc/php/8.0/fpm/pool.d/www.conf
  sed -i "s/;listen\.mode.*/listen.mode = 0666/" /etc/php/8.0/fpm/pool.d/www.conf

  service nginx restart
  service php8.0-fpm restart

  # Add Vagrant User To WWW-Data
  usermod -a -G www-data vagrant
  id vagrant
  groups vagrant

  # Install wp-cli
  curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  chmod +x wp-cli.phar
  mv wp-cli.phar /usr/local/bin/wp

  # Install Drush Launcher.
  curl --silent --location https://github.com/drush-ops/drush-launcher/releases/download/0.6.0/drush.phar --output drush.phar
  chmod +x drush.phar
  mv drush.phar /usr/local/bin/drush
  drush self-update

  # Install Drupal Console Launcher.
  curl --silent --location https://drupalconsole.com/installer --output drupal.phar
  chmod +x drupal.phar
  mv drupal.phar /usr/local/bin/drupal

  # Add Composer Global Bin To Path
  printf "\nPATH=\"$(sudo su - vagrant -c 'composer config -g home 2>/dev/null')/vendor/bin:\$PATH\"\n" | tee -a /home/vagrant/.profile
fi

# Install Node
apt-get install -y nodejs
/usr/bin/npm install -g npm
/usr/bin/npm install -g gulp-cli
/usr/bin/npm install -g bower
/usr/bin/npm install -g yarn
/usr/bin/npm install -g grunt-cli

# Install SQLite
apt-get install -y sqlite3 libsqlite3-dev

if "$SKIP_MYSQL"; then
  echo "SKIP_MYSQL is being used, so we're not installing MySQL"
else
  # Install MySQL
  echo "mysql-server mysql-server/root_password password secret" | debconf-set-selections
  echo "mysql-server mysql-server/root_password_again password secret" | debconf-set-selections
  apt-get install -y mysql-server

  # Configure MySQL 8 Remote Access and Native Pluggable Authentication
  cat > /etc/mysql/conf.d/mysqld.cnf << EOF
[mysqld]
bind-address = 0.0.0.0
default_authentication_plugin = mysql_native_password
EOF

  # Install LMM for database snapshots
  apt-get install -y thin-provisioning-tools bc
  git clone https://github.com/Lullabot/lmm.git /opt/lmm
  sed -e 's/mysql/homestead-vg/' -i /opt/lmm/config.sh
  ln -s /opt/lmm/lmm /usr/local/sbin/lmm

  # Create a thinly provisioned volume to move the database to. We use 64G as the
  # size leaving ~5GB free for other volumes.
  mkdir -p /homestead-vg/master
  sudo lvs
  lvcreate -L 64G -T homestead-vg/thinpool

  # Create a 64GB volume for the database. If needed, it can be expanded with
  # lvextend.
  lvcreate -V64G -T homestead-vg/thinpool -n mysql-master
  mkfs.ext4 /dev/homestead-vg/mysql-master
  echo "/dev/homestead-vg/mysql-master\t/homestead-vg/master\text4\terrors=remount-ro\t0\t1" >> /etc/fstab
  mount -a
  chown mysql:mysql /homestead-vg/master

  # Move the data directory and symlink it in.
  systemctl stop mysql
  mv /var/lib/mysql/* /homestead-vg/master
  rm -rf /var/lib/mysql
  ln -s /homestead-vg/master /var/lib/mysql

  # Allow mysqld to access the new data directories.
  echo '/homestead-vg/ r,' >> /etc/apparmor.d/local/usr.sbin.mysqld
  echo '/homestead-vg/** rwk,' >> /etc/apparmor.d/local/usr.sbin.mysqld
  systemctl restart apparmor
  systemctl start mysql

  # Configure MySQL Password Lifetime
  echo "default_password_lifetime = 0" >> /etc/mysql/mysql.conf.d/mysqld.cnf

  # Configure MySQL Remote Access
  sed -i '/^bind-address/s/bind-address.*=.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf
  service mysql restart

  export MYSQL_PWD=secret

  mysql --user="root" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'secret';"
  mysql --user="root" -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;"
  mysql --user="root" -e "CREATE USER 'homestead'@'0.0.0.0' IDENTIFIED BY 'secret';"
  mysql --user="root" -e "CREATE USER 'homestead'@'%' IDENTIFIED BY 'secret';"
  mysql --user="root" -e "GRANT ALL PRIVILEGES ON *.* TO 'homestead'@'0.0.0.0' WITH GRANT OPTION;"
  mysql --user="root" -e "GRANT ALL PRIVILEGES ON *.* TO 'homestead'@'%' WITH GRANT OPTION;"
  mysql --user="root" -e "FLUSH PRIVILEGES;"
  mysql --user="root" -e "CREATE DATABASE homestead character set UTF8mb4 collate utf8mb4_bin;"

  sudo tee /home/vagrant/.my.cnf <<EOL
[mysqld]
character-set-server=utf8mb4
collation-server=utf8mb4_bin
EOL

  # Add Timezone Support To MySQL
  mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql --user=root --password=secret mysql
  service mysql restart
fi

if "$SKIP_POSTGRESQL"; then
  echo "SKIP_POSTGRESQL is being used, so we're not installing PostgreSQL"
else
  # Install Postgres 13
  apt-get install -y postgresql-13 postgresql-server-dev-12 postgresql-13-postgis-3 postgresql-13-postgis-3-scripts

  # Configure Postgres Users
  sudo -u postgres psql -c "CREATE ROLE homestead LOGIN PASSWORD 'secret' SUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION;"

  # Configure Postgres Remote Access
  sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /etc/postgresql/13/main/postgresql.conf
  echo "host    all             all             10.0.2.2/32               md5" | tee -a /etc/postgresql/13/main/pg_hba.conf

  sudo -u postgres /usr/bin/createdb --echo --owner=homestead homestead
  service postgresql restart
  # Disable to lower initial overhead
  systemctl disable postgresql
fi

# Install Redis, Memcached, & Beanstalk
apt-get install -y redis-server memcached beanstalkd
systemctl enable redis-server
service redis-server start

# Configure Beanstalkd
sed -i "s/#START=yes/START=yes/" /etc/default/beanstalkd

# Install & Configure MailHog
wget --quiet -O /usr/local/bin/mailhog https://github.com/mailhog/MailHog/releases/download/v0.2.1/MailHog_linux_amd64
chmod +x /usr/local/bin/mailhog

sudo tee /etc/systemd/system/mailhog.service <<EOL
[Unit]
Description=Mailhog
After=network.target

[Service]
User=vagrant
ExecStart=/usr/bin/env /usr/local/bin/mailhog > /dev/null 2>&1 &

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable mailhog

# Configure Supervisor
systemctl enable supervisor.service
service supervisor start

# Install ngrok
wget https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.zip
unzip ngrok-stable-linux-amd64.zip -d /usr/local/bin
rm -rf ngrok-stable-linux-amd64.zip

# Install & Configure Postfix
echo "postfix postfix/mailname string homestead.test" | debconf-set-selections
echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections
apt-get install -y postfix
sed -i "s/relayhost =/relayhost = [localhost]:1025/g" /etc/postfix/main.cf
/etc/init.d/postfix reload

# Update / Override motd
echo "export ENABLED=1"| tee -a /etc/default/motd-news
sed -i "s/motd.ubuntu.com/homestead.joeferguson.me/g" /etc/update-motd.d/50-motd-news
rm -rf /etc/update-motd.d/10-help-text
rm -rf /etc/update-motd.d/50-landscape-sysinfo
rm -rf /etc/update-motd.d/99-bento
service motd-news restart
bash /etc/update-motd.d/50-motd-news --force

# One last upgrade check
apt-get upgrade -y

# Clean Up
apt -y autoremove
apt -y clean
chown -R vagrant:vagrant /home/vagrant
chown -R vagrant:vagrant /usr/local/bin

# Perform some cleanup from chef/bento packer_templates/ubuntu/scripts/cleanup.sh
# Delete Linux source
dpkg --list \
    | awk '{ print $2 }' \
    | grep linux-source \
    | xargs apt-get -y purge;

# delete docs packages
dpkg --list \
    | awk '{ print $2 }' \
    | grep -- '-doc$' \
    | xargs apt-get -y purge;

# Delete obsolete networking
apt-get -y purge ppp pppconfig pppoeconf

# Configure chronyd to fix clock-drift when VM-host sleeps/hibernates.
sed -i "s/^makestep.*/makestep 1 -1/" /etc/chrony/chrony.conf

# Delete oddities
apt-get -y purge popularity-contest installation-report command-not-found friendly-recovery laptop-detect

# Exlude the files we don't need w/o uninstalling linux-firmware
echo "==> Setup dpkg excludes for linux-firmware"
cat <<_EOF_ | cat >> /etc/dpkg/dpkg.cfg.d/excludes
#BENTO-BEGIN
path-exclude=/lib/firmware/*
path-exclude=/usr/share/doc/linux-firmware/*
#BENTO-END
_EOF_

# Delete the massive firmware packages
rm -rf /lib/firmware/*
rm -rf /usr/share/doc/linux-firmware/*

apt-get -y autoremove;
apt-get -y clean;

# Remove docs
rm -rf /usr/share/doc/*

# Remove caches
find /var/cache -type f -exec rm -rf {} \;

# delete any logs that have built up during the install
find /var/log/ -name *.log -exec rm -f {} \;

# Disable sleep https://github.com/laravel/homestead/issues/1624
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# What are you doing Ubuntu?
# https://askubuntu.com/questions/1250974/user-root-cant-write-to-file-in-tmp-owned-by-someone-else-in-20-04-but-can-in
sysctl fs.protected_regular=0

# Blank netplan machine-id (DUID) so machines get unique ID generated on boot.
truncate -s 0 /etc/machine-id

# Enable Swap Memory
/bin/dd if=/dev/zero of=/var/swap.1 bs=1M count=1024
/sbin/mkswap /var/swap.1
/sbin/swapon /var/swap.1
