# --- 2047 admin-lab Makefile ---
SHELL       := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

BRANCH  ?= main
REPO_DIR?= /opt/2047-admin-lab
SRC_DIR ?= $(CURDIR)

.PHONY: help q install move run bootstrap minimal converge logs verify lint

help: ## показать цели
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

q: install move run ## самый короткий путь: deps → копия в /opt → запуск bootstrap

install: ## установить зависимости
	@sudo apt-get update -y
	@sudo apt-get install -y git ansible curl rsync

move: ## только перенести код в /opt
	@sudo mkdir -p "$(REPO_DIR)"
	@sudo rsync -a --delete --exclude '.git' "$(SRC_DIR)/" "$(REPO_DIR)/"
	@sudo chown -R root:root "$(REPO_DIR)"

run: ## только запустить bootstrap из /opt
	@sudo BRANCH="$(BRANCH)" REPO_DIR="$(REPO_DIR)" bash "$(REPO_DIR)/bootstrap/bootstrap.sh"

bootstrap: q ## синоним

minimal: ## локальный прогон minimal.yml
	ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/minimal.yml

converge: ## локальный прогон converge.yml
	ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/converge.yml

logs: ## быстрый просмотр логов
	-@sudo journalctl -u 2047-firstboot.service -e || true
	-@sudo journalctl -u 2047-converge.service  -e || true
	-@sudo tail -n 200 /var/log/2047-ansible-pull.log || true

verify: ## проверка: юниты и файлы на месте
	@echo ">>> units"; sudo systemctl list-unit-files | grep -E '2047-(firstboot|converge)' || true
	@echo ">>> repo in /opt"; ls -lah "$(REPO_DIR)/ansible" || true
	@echo ">>> state dir"; ls -lah /etc/2047 || true

lint: ## линт ansible (если установлен ansible-lint)
	ansible-lint ansible/ || true
