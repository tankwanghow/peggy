#!/bin/bash

IMAGE_NAME=$1
IMAGE_TAG="latest"
DOCKER_HUB_USERNAME=$2
DOCKER_CONTAINER_NAME=$3
EXPECTED_IMAGE_ID=$4
GIT_SHA=$5
APP_COMPOSE="/home/$IMAGE_NAME/docker-compose-$IMAGE_NAME.yml"
FULL_IMAGE="$DOCKER_HUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG"

CURRENT_TAG_ID=$(docker image inspect $FULL_IMAGE --format='{{.ID}}' 2>/dev/null || echo "none")
if [ -n "$EXPECTED_IMAGE_ID" ] && [ "$CURRENT_TAG_ID" != "$EXPECTED_IMAGE_ID" ]; then
    echo "Tag '$FULL_IMAGE' points to $CURRENT_TAG_ID, expected $EXPECTED_IMAGE_ID. Re-tagging..."
    docker tag $EXPECTED_IMAGE_ID $FULL_IMAGE
fi

if [ -n "$GIT_SHA" ] && [ -n "$EXPECTED_IMAGE_ID" ]; then
    SHA_IMAGE="$DOCKER_HUB_USERNAME/$IMAGE_NAME:$GIT_SHA"
    docker tag $EXPECTED_IMAGE_ID $SHA_IMAGE
    echo "Tagged as: $SHA_IMAGE"
fi

FINAL_ID=$(docker image inspect $FULL_IMAGE --format='{{.ID}}')
echo "Deploying image: $FULL_IMAGE ($FINAL_ID)"

echo "Updating container on Linode..."
docker compose -f $APP_COMPOSE down
docker compose -f $APP_COMPOSE up -d --force-recreate
echo "Running migration for $DOCKER_CONTAINER_NAME...."
docker exec $DOCKER_CONTAINER_NAME ./bin/migrate

docker image prune -f
