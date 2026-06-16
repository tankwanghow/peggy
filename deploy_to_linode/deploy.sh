#!/bin/bash
set -eo pipefail

SETUP_FILE=$1
script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_path/.." && pwd)"
monorepo_root="$(cd "$project_root/.." && pwd)"
global_assets="$monorepo_root/.global_assets"
shared_config="$monorepo_root/shared_config"

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

ensure_global_assets() {
    if [ ! -f "$shared_config/workspace_assets.ex" ]; then
        echo "Error: shared_config not found at $shared_config"
        echo "Deploy expects the elixir monorepo layout (peggy + shared_config + .global_assets)."
        exit 1
    fi

    if [ ! -x "$global_assets/bin/esbuild" ] || \
       [ ! -x "$global_assets/bin/tailwindcss" ] || \
       [ ! -d "$global_assets/heroicons/optimized" ]; then
        echo "Global assets missing — running $global_assets/setup.sh"
        bash "$global_assets/setup.sh"
    fi

    echo "Using local workspace assets from $global_assets"
}

stage_dockerignore() {
    monorepo_dockerignore="$monorepo_root/.dockerignore"

    if [ -f "$monorepo_dockerignore" ]; then
        DOCKERIGNORE_BACKUP="$(mktemp)"
        cp "$monorepo_dockerignore" "$DOCKERIGNORE_BACKUP"
    else
        DOCKERIGNORE_BACKUP=""
    fi

    cp "$project_root/.dockerignore" "$monorepo_dockerignore"

    restore_dockerignore() {
        if [ -n "$DOCKERIGNORE_BACKUP" ]; then
            cp "$DOCKERIGNORE_BACKUP" "$monorepo_dockerignore"
            rm -f "$DOCKERIGNORE_BACKUP"
        else
            rm -f "$monorepo_dockerignore"
        fi
    }

    trap restore_dockerignore EXIT
}

stty -echo
echo -n "Please enter password of the server: "
read LINODE_PWD
stty echo
echo

ensure_global_assets
stage_dockerignore

IMAGE_TAG="latest"
GIT_SHA=$(git -C "$project_root" rev-parse --short HEAD)
FULL_IMAGE="$DOCKER_HUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
SHA_IMAGE="$DOCKER_HUB_USERNAME/$IMAGE_NAME:$GIT_SHA"

echo "Building Docker image (monorepo context: $monorepo_root)..."
docker build --builder default \
    -t $FULL_IMAGE -t $SHA_IMAGE \
    -f "$project_root/Dockerfile" \
    "$monorepo_root"

NEW_IMAGE_ID=$(docker image inspect $FULL_IMAGE --format='{{.ID}}')
echo "Built image ID: $NEW_IMAGE_ID"

IMAGE_SIZE=$(docker image inspect $FULL_IMAGE --format='{{.Size}}')
echo "Transferring image to server (~$(( IMAGE_SIZE / 1024 / 1024 )) MB uncompressed)..."
echo "Image tagged as: $IMAGE_TAG and $GIT_SHA"
docker save $FULL_IMAGE $SHA_IMAGE | gzip | pv | sshpass -p $LINODE_PWD ssh -o StrictHostKeyChecking=no root@$LINODE_IP "gunzip | docker load"

sshpass -p $LINODE_PWD ssh root@$LINODE_IP "bash /home/$IMAGE_NAME/deploy_at_server.sh $IMAGE_NAME $DOCKER_HUB_USERNAME $DOCKER_CONTAINER_NAME $NEW_IMAGE_ID $GIT_SHA"