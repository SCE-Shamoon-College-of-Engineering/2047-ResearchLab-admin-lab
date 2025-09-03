# --- 2047 admin-lab Makefile (final) ---
SHELL       := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:

BRANCH   ?= main
REPO_DIR ?= /opt/2047-admin-lab
SRC_DIR  ?= $(CURDIR)

REPO_HTTPS := https://github.com/SCE-Shamoon-College-of-Engineering/2047-ResearchLab-admin-lab.git

.PHONY: help env-check q install move run bootstrap minimal converge logs verify lint pull deploy

help: ## показать цели
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

env-check: ## проверки окружения (патчить не нужно)
	@command -v rsync >/dev/null || { echo "rsync не найден. Запусти: make install"; exit 1; }
	@command -v ansible >/dev/null || echo "⚠️ ansible не найден — bootstrap его поставит"
	@echo "BRANCH=$(BRANCH)  REPO_DIR=$(REPO_DIR)"

q: install move run ## deps → копия в /opt → запуск bootstrap

install: ## установить зависимости
	sudo apt-get update -y
	sudo apt-get install -y git ansible curl rsync

move: env-check ## перенести текущую копию проекта в /opt
	sudo mkdir -p "$(REPO_DIR)"
	sudo rsync -a --delete --exclude '.git' "$(SRC_DIR)/" "$(REPO_DIR)/"
	sudo chown -R root:root "$(REPO_DIR)"

run: ## запустить bootstrap из /opt
	sudo BRANCH="$(BRANCH)" REPO_DIR="$(REPO_DIR)" bash "$(REPO_DIR)/bootstrap/bootstrap.sh"

bootstrap: q ## синоним

# --- удобные задачи для сервера ---

pull: ## git pull из GitHub (HTTPS). Использует $GIT_AUTH_TOKEN или ~/.netrc
	@if [ -n "$$GIT_AUTH_TOKEN" ]; then \
		echo "• pull через токен из \$GIT_AUTH_TOKEN"; \
		git pull "https://$$GIT_AUTH_TOKEN@github.com/SCE-Shamoon-College-of-Engineering/2047-ResearchLab-admin-lab.git" "$(BRANCH)"; \
	else \
		echo "• pull через ~/.netrc или интерактивную авторизацию"; \
		git pull "$(REPO_HTTPS)" "$(BRANCH)"; \
	fi

deploy: ## обновить код из GitHub и прогнать установку (pull → q)
	$(MAKE) pull BRANCH=$(BRANCH)
	sudo $(MAKE) q BRANCH=$(BRANCH)

# --- утилиты/проверки ---

minimal: ## локальный прогон minimal.yml
	ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/minimal.yml

converge: ## локальный прогон converge.yml
	ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/converge.yml

logs: ## быстрый просмотр логов
	-@sudo journalctl -u 2047-firstboot.service -e || true
	-@sudo journalctl -u 2047-converge.service  -e || true
	-@sudo tail -n 200 /var/log/2047-ansible-pull.log || true

verify: ## проверить наличие systemd-юнитов и файлов
	@echo ">>> units"; sudo systemctl list-unit-files | grep -E '2047-(firstboot|converge)' || true
	@echo ">>> repo in /opt"; ls -lah "$(REPO_DIR)/ansible" || true
	@echo ">>> state dir"; ls -lah /etc/2047 || true

lint: ## линт ansible (если установлен ansible-lint)
	ansible-lint ansible/ || true
