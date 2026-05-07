#!/bin/bash

DB_NAME=$1
DB_USER=$2
DB_PWD=$3
PORT=$4
DOMAIN_NAME=$5
IMAGE_NAME=$6
DOCKER_HUB_USERNAME=$7
DOCKER_CONTAINER_NAME=$8
SECRET_KEY_BASE=$9
MAIL_HOST=${10}
MAIL_PORT=${11}
MAIL_USERNAME=${12}
MAIL_PASSWORD=${13}
MAIL_FROM=${14}
APP_COMPOSE="/home/$IMAGE_NAME/docker-compose-$IMAGE_NAME.yml"
NGINX_CONF="${IMAGE_NAME}-nginx.conf"

echo "Creating ${APP_COMPOSE} file..."
cat << EOF > $APP_COMPOSE
services:
  web:
    image: ${DOCKER_HUB_USERNAME}/${IMAGE_NAME}:latest
    container_name: ${DOCKER_CONTAINER_NAME}
    volumes:
      - /home/${IMAGE_NAME}/uploads:/uploads
    environment:
      - DATABASE_URL=postgres://${DB_USER}:${DB_PWD}@localhost:5432/${DB_NAME}
      - SECRET_KEY_BASE=${SECRET_KEY_BASE}
      - PHX_HOST=${DOMAIN_NAME}
      - MIX_ENV=prod
      - PORT=${PORT}
      - MAIL_HOST=${MAIL_HOST}
      - MAIL_PORT=${MAIL_PORT}
      - MAIL_USERNAME=${MAIL_USERNAME}
      - MAIL_PASSWORD=${MAIL_PASSWORD}
      - MAIL_FROM=${MAIL_FROM}
    network_mode: host
EOF
chmod 600 $APP_COMPOSE

echo "Creating Nginx conf file for ${DOMAIN_NAME}..."
cat << EOF > /etc/nginx/sites-available/${NGINX_CONF}
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN_NAME} www.${DOMAIN_NAME};

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN_NAME} www.${DOMAIN_NAME};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_pass http://localhost:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
ln -sf /etc/nginx/sites-available/${NGINX_CONF} /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
