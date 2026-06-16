#!/bin/bash
set -e

SETUP_FILE=$1
script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$SETUP_FILE" ]; then
    echo "Error: Setup file $SETUP_FILE not found."
    exit 1
fi

while IFS='=' read -r key value
do
    [[ "$key" =~ ^#.*$ ]] && continue
    [[ "$key" =~ ^[[:space:]]*$ ]] && continue
    key=$(echo $key | tr -d '[:space:]')
    value=$(echo $value | tr -d '[:space:]')
    echo "$key -> $value"
    declare "$key=$value"
done < "$SETUP_FILE"

read_secret() {
    local var=$1 prompt=$2
    while true; do
        stty -echo
        echo -n "$prompt"
        read "$var"
        stty echo
        echo
        if [ -z "${!var}" ]; then
            echo "Empty input — try again."
        else
            break
        fi
    done
}

for v in LINODE_IP DOMAIN_NAME MAIL_HOST MAIL_PORT MAIL_USERNAME MAIL_FROM; do
    if [ -z "${!v}" ]; then
        echo "Error: $v is not set in $SETUP_FILE"
        exit 1
    fi
done

read_secret LINODE_PWD "Please enter password of the server: "
read_secret DB_PWD     "Please enter password for '$DB_USER': "

echo
echo "=== Mail (SMTP) ==="
echo "Sending as $MAIL_USERNAME via $MAIL_HOST:$MAIL_PORT"
echo "For Gmail: use an App Password (not your account password)."
echo "  https://myaccount.google.com/apppasswords"
echo
read_secret MAIL_PASSWORD "SMTP password for $MAIL_USERNAME: "

SECRET_KEY_BASE=$(mix phx.gen.secret)
echo "Generated SECRET_KEY_BASE."

sshpass -p $LINODE_PWD ssh root@$LINODE_IP << EOF
mkdir -p /home/${IMAGE_NAME}/uploads
EOF

sshpass -p $LINODE_PWD scp \
    $script_path/setup_barebone_debian_at_server.sh \
    $script_path/setup_db_at_server.sh \
    $script_path/setup_certbot_at_server.sh \
    $script_path/generate_files_at_server.sh \
    $script_path/deploy_at_server.sh \
    root@$LINODE_IP:/home/${IMAGE_NAME}/

sshpass -p $LINODE_PWD ssh root@$LINODE_IP "bash /home/${IMAGE_NAME}/setup_barebone_debian_at_server.sh"

sshpass -p "$LINODE_PWD" ssh root@"$LINODE_IP" \
    "bash /home/${IMAGE_NAME}/setup_db_at_server.sh '$DB_NAME' '$DB_USER' '$DB_PWD'"

sshpass -p "$LINODE_PWD" ssh root@"$LINODE_IP" \
    "bash /home/${IMAGE_NAME}/setup_certbot_at_server.sh '$DOMAIN_NAME'"

sshpass -p "$LINODE_PWD" ssh root@"$LINODE_IP" \
    "bash /home/${IMAGE_NAME}/generate_files_at_server.sh '$DB_NAME' '$DB_USER' '$DB_PWD' '$PORT' '$DOMAIN_NAME' '$IMAGE_NAME' '$DOCKER_HUB_USERNAME' '$DOCKER_CONTAINER_NAME' '$SECRET_KEY_BASE' '$MAIL_HOST' '$MAIL_PORT' '$MAIL_USERNAME' '$MAIL_PASSWORD' '$MAIL_FROM'"

# shellcheck source=../../shared_config/docker_deploy.sh
source "$(cd "$script_path/../.." && pwd)/shared_config/docker_deploy.sh"
docker_deploy_init "$script_path"
ensure_global_assets
stage_dockerignore

IMAGE_TAG="latest"
GIT_SHA=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD)
FULL_IMAGE="$DOCKER_HUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
SHA_IMAGE="$DOCKER_HUB_USERNAME/$IMAGE_NAME:$GIT_SHA"

echo "Building Docker image (monorepo context: $MONOREPO_ROOT)..."
docker build --builder default \
    -t $FULL_IMAGE -t $SHA_IMAGE \
    -f "$PROJECT_ROOT/Dockerfile" \
    "$MONOREPO_ROOT"

NEW_IMAGE_ID=$(docker image inspect $FULL_IMAGE --format='{{.ID}}')
echo "Built image ID: $NEW_IMAGE_ID"

IMAGE_SIZE=$(docker image inspect $FULL_IMAGE --format='{{.Size}}')
echo "Transferring image to server (~$(( IMAGE_SIZE / 1024 / 1024 )) MB uncompressed)..."
docker save $FULL_IMAGE $SHA_IMAGE | gzip | pv | sshpass -p $LINODE_PWD ssh -o StrictHostKeyChecking=no root@$LINODE_IP "gunzip | docker load"

sshpass -p $LINODE_PWD ssh root@$LINODE_IP "bash /home/${IMAGE_NAME}/deploy_at_server.sh $IMAGE_NAME $DOCKER_HUB_USERNAME $DOCKER_CONTAINER_NAME $NEW_IMAGE_ID $GIT_SHA"
