.PHONY: build run stop clean push

# Docker image name and repository
IMAGE_NAME = swift-storage
CONTAINER_NAME = swift-storage-server
DOCKER_REPO = chillfraestrcuture
TAG = 1.0.0

# Build the Docker image
build:
	docker build -t $(IMAGE_NAME):$(TAG) .

# Tag the image for pushing
tag:
	docker tag $(IMAGE_NAME):$(TAG) $(DOCKER_REPO)/p2mstoragemanager:$(TAG)

# Push the image to registry
push: tag
	docker push $(DOCKER_REPO)/p2mstoragemanager:$(TAG)

# Run the container
run:
	docker run -d --name $(CONTAINER_NAME) \
		-p 8080:8080 \
		-v $(PWD)/data:/srv/node \
		$(IMAGE_NAME):$(TAG)

# Enter container shell
shell:
	docker exec -it $(CONTAINER_NAME) /bin/bash

# Show logs
logs:
	docker logs $(CONTAINER_NAME)

# Stop the container
stop:
	docker stop $(CONTAINER_NAME)

# Remove the container
rm:
	docker rm $(CONTAINER_NAME)

# Clean up (stop and remove container)
clean: stop rm

# Rebuild and restart
restart: clean build run

# Run tests
test:
	docker exec $(CONTAINER_NAME) python -m unittest discover test

# Display Swift status
status:
	docker exec $(CONTAINER_NAME) swift-init all status

# Reset Swift (useful for development)
reset:
	docker exec $(CONTAINER_NAME) swift-init all stop
	docker exec $(CONTAINER_NAME) swift-init all start