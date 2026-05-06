#!/bin/bash
set -eo pipefail

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
    declare "$key=$value"
done < "$SETUP_FILE"

stty -echo
echo -n "Please enter password of the server: "
read LINODE_PWD
stty echo
echo

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
echo "Image tagged as: $IMAGE_TAG and $GIT_SHA"
docker save $FULL_IMAGE $SHA_IMAGE | gzip | pv | sshpass -p $LINODE_PWD ssh -o StrictHostKeyChecking=no root@$LINODE_IP "gunzip | docker load"

sshpass -p $LINODE_PWD ssh root@$LINODE_IP "bash /home/$IMAGE_NAME/deploy_at_server.sh $IMAGE_NAME $DOCKER_HUB_USERNAME $DOCKER_CONTAINER_NAME $NEW_IMAGE_ID $GIT_SHA"
