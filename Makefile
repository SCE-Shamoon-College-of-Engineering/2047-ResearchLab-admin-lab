# --- 2047 admin-lab Makefile (final+) ---
SHELL       := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:

BRANCH   ?= main
REPO_DIR ?= /opt/2047-admin-lab
SRC_DIR  ?= $(CURDIR)

REPO_HTTPS := https://github.com/SCE-Shamoon-College-of-Engineering/2047-ResearchLab-admin-lab.git

.PHONY: help env-check q install move run bootstrap \
        minimal converge logs verify lint pull deploy \
        enable-units restart-units status-units

help: ## показать цели
	@grep -E '^[a-zA-Z0-9_-]+:.*?##' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

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

# --- обновление кода на сервере ---

pull: ## безопасный pull: fetch + hard reset (исп. $GIT_AUTH_TOKEN или ~/.netrc)
	@if [ ! -d .git ]; then echo "✗ не git-репозиторий: $(PWD)"; exit 1; fi
	@if [ -n "$$GIT_AUTH_TOKEN" ]; then \
		echo "• pull через токен из \$GIT_AUTH_TOKEN"; \
		REMOTE="https://$$GIT_AUTH_TOKEN@github.com/SCE-Shamoon-College-of-Engineering/2047-ResearchLab-admin-lab.git"; \
	else \
		echo "• pull через $(REPO_HTTPS)"; \
		REMOTE="$(REPO_HTTPS)"; \
	fi; \
	git remote set-url origin "$$REMOTE" || true; \
	git fetch --prune origin; \
	git reset --hard "origin/$(BRANCH)"; \
	git rev-parse --short HEAD | xargs -I{} echo "✓ на коммите {}"

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

enable-units: ## включить юниты в автозагрузку
	sudo systemctl enable 2047-firstboot.service 2047-converge.service 2047-converge.timer || true

restart-units: ## перезапустить юниты
	sudo systemctl daemon-reload
	sudo systemctl restart 2047-firstboot.service || true
	sudo systemctl restart 2047-converge.service  || true

status-units: ## статус юнитов
	sudo systemctl status --no-pager -l 2047-firstboot.service || true
	sudo systemctl status --no-pager -l 2047-converge.service  || true

lint: ## линт ansible (если установлен ansible-lint)
	ansible-lint ansible/ || true
