# Makefile for Nitpick Docker Development

.PHONY: dev build test down clean logs

# Start the full system in the background
dev:
	docker-compose -f docker-compose.dev.yml up -d

# Build/Rebuild the development image
build:
	docker-compose -f docker-compose.dev.yml build

# Run the integration tests using the dev environment (Headless by default)
test:
	# Ensure the dev container is up.
	docker-compose -f docker-compose.dev.yml up -d
	# Wait for the server to be reachable on port 7000
	@echo "Waiting for dev server to be reachable at http://localhost:7000..."
	@timeout=30; \
	while ! curl -s http://localhost:7000 > /dev/null; do \
		if [ $$timeout -le 0 ]; then \
			echo "Error: Dev server did not become reachable within 30 seconds."; \
			docker-compose -f docker-compose.dev.yml logs nitpick-dev; \
			exit 1; \
		fi; \
		printf "."; \
		sleep 1; \
		timeout=$$((timeout-1)); \
	done
	@echo "\nServer is UP. Running tests..."
	# Run pytest against the exposed port 7000 in headless mode
	pytest tests --headless

# Run integration tests with a visible browser window (Headed)
test-headed:
	docker-compose -f docker-compose.dev.yml up -d
	# Wait for the server to be reachable on port 7000
	@echo "Waiting for dev server to be reachable at http://localhost:7000..."
	@timeout=30; \
	while ! curl -s http://localhost:7000 > /dev/null; do \
		if [ $$timeout -le 0 ]; then \
			echo "Error: Dev server did not become reachable within 30 seconds."; \
			docker-compose -f docker-compose.dev.yml logs nitpick-dev; \
			exit 1; \
		fi; \
		printf "."; \
		sleep 1; \
		timeout=$$((timeout-1)); \
	done
	@echo "\nServer is UP. Running tests..."
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
