# Makefile for Nitpick Docker Development

.PHONY: dev build test down clean logs

# Start the full system in the background
dev:
	docker-compose -f docker-compose.dev.yml up -d

# Build/Rebuild the development image
build:
	docker-compose -f docker-compose.dev.yml build

# Run the integration tests using the dev environment
test:
	# Ensure the dev container is up. This might need tweaking based on how the test runner works.
	# Typically, we want to run tests inside the container or against the running service.
	docker-compose -f docker-compose.dev.yml up -d
	# Give it a second to start
	sleep 5
	# Run pytest against the exposed port 7000 (as mapped in docker-compose.dev.yml)
	pytest tests

# Stop and remove containers
down:
	docker-compose -f docker-compose.dev.yml down

# Clean up docker resources
clean:
	docker-compose -f docker-compose.dev.yml down -v --remove-orphans

# View logs
logs:
	docker-compose -f docker-compose.dev.yml logs -f
