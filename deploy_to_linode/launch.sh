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

stty -echo
echo -n "Please enter password of the server: "
read LINODE_PWD
stty echo
echo

stty -echo
echo -n "Please enter password for '$DB_USER': "
read DB_PWD
stty echo
echo

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

sshpass -p $LINODE_PWD ssh root@$LINODE_IP "bash /home/${IMAGE_NAME}/setup_db_at_server.sh $DB_NAME $DB_USER $DB_PWD"

sshpass -p $LINODE_PWD ssh root@$LINODE_IP "bash /home/${IMAGE_NAME}/setup_certbot_at_server.sh $DOMAIN_NAME"

sshpass -p $LINODE_PWD ssh root@$LINODE_IP "bash /home/${IMAGE_NAME}/generate_files_at_server.sh $DB_NAME $DB_USER $DB_PWD $PORT $DOMAIN_NAME $IMAGE_NAME $DOCKER_HUB_USERNAME $DOCKER_CONTAINER_NAME $SECRET_KEY_BASE"

IMAGE_TAG="latest"
GIT_SHA=$(git -C "$script_path/.." rev-parse --short HEAD)
FULL_IMAGE="$DOCKER_HUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
SHA_IMAGE="$DOCKER_HUB_USERNAME/$IMAGE_NAME:$GIT_SHA"

echo "Building Docker image..."
docker build --builder default -t $FULL_IMAGE -t $SHA_IMAGE -f $script_path/../Dockerfile $script_path/..

NEW_IMAGE_ID=$(docker image inspect $FULL_IMAGE --format='{{.ID}}')
echo "Built image ID: $NEW_IMAGE_ID"

IMAGE_SIZE=$(docker image inspect $FULL_IMAGE --format='{{.Size}}')
echo "Transferring image to server (~$(( IMAGE_SIZE / 1024 / 1024 )) MB uncompressed)..."
docker save $FULL_IMAGE $SHA_IMAGE | gzip | pv | sshpass -p $LINODE_PWD ssh -o StrictHostKeyChecking=no root@$LINODE_IP "gunzip | docker load"

sshpass -p $LINODE_PWD ssh root@$LINODE_IP "bash /home/${IMAGE_NAME}/deploy_at_server.sh $IMAGE_NAME $DOCKER_HUB_USERNAME $DOCKER_CONTAINER_NAME $NEW_IMAGE_ID $GIT_SHA"
