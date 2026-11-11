.PHONY: build up down logs shell web clean
build:
	docker compose build
up:
	docker compose up -d
down:
	docker compose down
logs:
	docker compose logs -f
shell:
	docker compose exec alma bash
web:
	@echo "http://127.0.0.1:23011"
clean:
	docker compose down -v
