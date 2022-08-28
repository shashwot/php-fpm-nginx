FROM ubuntu:18.04
MAINTAINER Shashwot Risal <shashwot@gmail.com>

ENV PHP_VERSION 7.4
ENV TIMEZONE Asia/Kathmandu

# Surpress Upstart errors/warning
RUN dpkg-divert --local --rename --add /sbin/initctl && \
ln -sf /bin/true /sbin/initctl

# Let the conatiner know that there is no tty
ENV DEBIAN_FRONTEND noninteractive

# required by $PHP_VERSION
RUN apt-get update && \
    apt-get install -y language-pack-en-base &&\
    export LC_ALL=en_US.UTF-8 && \
    export LANG=en_US.UTF-8

# Set DateTime Region
RUN ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime && \
apt-get install -y tzdata && \
dpkg-reconfigure --frontend noninteractive tzdata

RUN apt-get update && apt-get install -y software-properties-common
RUN LC_ALL=en_US.UTF-8 add-apt-repository -y ppa:ondrej/php

# Update base image
# Add sources for latest nginx
# Install software requirements
RUN LC_ALL=en_US.UTF-8 && \
apt-get update && \
apt-get install -y software-properties-common && \
nginx=stable && \
add-apt-repository ppa:nginx/$nginx && \
add-apt-repository ppa:ondrej/php && \
apt-get update && \
apt-get upgrade -y && \
BUILD_PACKAGES="unzip curl supervisor nginx php${PHP_VERSION}-fpm php${PHP_VERSION}-common php${PHP_VERSION}-mysql php${PHP_VERSION}-xml php${PHP_VERSION}-xmlrpc php${PHP_VERSION}-curl php${PHP_VERSION}-gd php${PHP_VERSION}-imagick php${PHP_VERSION}-cli php${PHP_VERSION}-dev php${PHP_VERSION}-imap php${PHP_VERSION}-mbstring php${PHP_VERSION}-opcache" && \
apt-get -y install $BUILD_PACKAGES && \
apt-get remove --purge -y software-properties-common && \
apt-get autoremove -y && \
apt-get clean && \
apt-get autoclean && \
echo -n > /var/lib/apt/extended_states && \
rm -rf /var/lib/apt/lists/* && \
rm -rf /usr/share/man/?? && \
rm -rf /usr/share/man/??_*

# tweak nginx config
RUN sed -i -e"s/worker_processes  1/worker_processes 5/" /etc/nginx/nginx.conf && \
sed -i -e"s/keepalive_timeout\s*65/keepalive_timeout 2/" /etc/nginx/nginx.conf && \
sed -i -e"s/keepalive_timeout 2/keepalive_timeout 2;\n\tclient_max_body_size 100m/" /etc/nginx/nginx.conf && \
sed -i 's/sendfile on/sendfile off/g' /etc/nginx/nginx.conf && \
echo "daemon off;" >> /etc/nginx/nginx.conf

# tweak php-fpm config
RUN sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php/${PHP_VERSION}/fpm/php.ini && \
sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 100M/g" /etc/php/${PHP_VERSION}/fpm/php.ini && \
sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 100M/g" /etc/php/${PHP_VERSION}/fpm/php.ini && \
sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" /etc/php/${PHP_VERSION}/fpm/php-fpm.conf && \
sed -i -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf && \
sed -i -e "s/pm.max_children = 5/pm.max_children = 9/g" /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf && \
sed -i -e "s/pm.start_servers = 2/pm.start_servers = 3/g" /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf && \
sed -i -e "s/pm.min_spare_servers = 1/pm.min_spare_servers = 2/g" /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf && \
sed -i -e "s/pm.max_spare_servers = 3/pm.max_spare_servers = 4/g" /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf && \
sed -i -e "s/pm.max_requests = 500/pm.max_requests = 200/g" /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf

# fix ownership of sock file for php-fpm
RUN sed -i -e "s/;listen.mode = 0660/listen.mode = 0750/g" /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf && \
#sed -i -e "s|listen = /run/php/php${PHP_VERSION}-fpm.sock|listen = 127.0.0.1:9000|g" /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf && \
find /etc/php/${PHP_VERSION}/cli/conf.d/ -name "*.ini" -exec sed -i -re 's/^(\s*)#(.*)/\1;\2/g' {} \;

# nginx site conf
RUN rm -Rf /etc/nginx/conf.d/* && \
rm -Rf /etc/nginx/sites-available/default && \
mkdir -p /etc/nginx/ssl/
ADD conf/nginx-site.conf /etc/nginx/sites-available/default.conf
RUN ln -s /etc/nginx/sites-available/default.conf /etc/nginx/sites-enabled/default.conf

RUN rm -Rf /etc/nginx/sites-available/default && \
rm -Rf /etc/nginx/sites-enabled/default

# Install composer
RUN curl -sS https://getcomposer.org/installer | php && \
    mv composer.phar /usr/local/bin/composer
    
# Add git commands to allow container updating
ADD scripts/pull /usr/bin/pull
ADD scripts/push /usr/bin/push
RUN chmod 755 /usr/bin/pull && chmod 755 /usr/bin/push

# Supervisor Config
ADD conf/supervisord.conf /etc/supervisord.conf

# Start Supervisord
ADD scripts/start.sh /start.sh
RUN chmod 755 /start.sh

# Start php-fpm
RUN service php${PHP_VERSION}-fpm start

# Setup Volume
VOLUME ["/var/www", "/etc/nginx/sites-enabled"]

# add test PHP file
RUN rm -rf /var/www/html/*
ADD src/* /var/www/html/
RUN chown -Rf www-data.www-data /var/www/

WORKDIR /var/www/html

# Expose Ports
EXPOSE 80 9000

CMD ["/bin/bash", "/start.sh"]