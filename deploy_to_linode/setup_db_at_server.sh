#!/bin/bash

DB_NAME=$1
DB_USER=$2
DB_PWD=$3

check_db_exists() {
    if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$1"; then
        echo "Database $1 already exists."
        return 0
    else
        echo "Database $1 does not exist."
        return 1
    fi
}

check_user_exists() {
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$1'" | grep -q 1; then
        echo "User $1 already exists."
        return 0
    else
        echo "User $1 does not exist."
        return 1
    fi
}

create_db() {
    echo "Creating database $1..."
    sudo -u postgres psql -c "CREATE DATABASE $1;"
}

create_superuser() {
    echo "Creating superuser $1..."
    sudo -u postgres psql -c "CREATE USER $1 WITH PASSWORD '$2' SUPERUSER;"
}

if ! check_db_exists "${DB_NAME}"; then
    create_db "${DB_NAME}"
    sudo -u postgres psql -d "${DB_NAME}" -c "CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;"
    sudo -u postgres psql -d "${DB_NAME}" -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
    sudo -u postgres psql -d "${DB_NAME}" -c "CREATE EXTENSION IF NOT EXISTS citext;"
fi

if ! check_user_exists "${DB_USER}"; then
    create_superuser "${DB_USER}" "$DB_PWD"
fi

echo "PostgreSQL setup completed."
