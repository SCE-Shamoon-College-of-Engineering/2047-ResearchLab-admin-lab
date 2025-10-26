# --- 2047 admin-lab Makefile (final production) ---
SHELL       := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:
.DEFAULT_GOAL := help

# Main project variables
BRANCH   ?= main
REPO_DIR ?= /opt/2047-admin-lab
SRC_DIR  ?= $(CURDIR)
REPO_HTTPS := https://github.com/SCE-Shamoon-College-of-Engineering/2047-ResearchLab-admin-lab.git

# PXE / HTTP server IP
PXE_HTTP_IP ?= 192.168.1.250

.PHONY: help env-check q install move run bootstrap \
        minimal converge logs verify lint pull deploy \
        enable-units restart-units status-units \
        pxe-http pxe-verify pxe-logs pxe-restart

# ---------------------------------------------------------
# General project management
# ---------------------------------------------------------

help: ## Show available make targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?##' $(MAKEFILE_LIST) | \
	awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

env-check: ## Check environment prerequisites
	@command -v rsync >/dev/null || { echo "rsync not found. Run: make install"; exit 1; }
	@command -v ansible >/dev/null || echo "⚠️  ansible not found — it will be installed by bootstrap"
	@echo "BRANCH=$(BRANCH)  REPO_DIR=$(REPO_DIR)"

q: install move run ## Install dependencies → copy to /opt → run bootstrap

install: ## Install required packages
	sudo apt-get update -y
	sudo apt-get install -y git ansible curl rsync

move: env-check ## Copy current project to /opt directory
	sudo mkdir -p "$(REPO_DIR)"
	sudo rsync -a --delete --exclude '.git' "$(SRC_DIR)/" "$(REPO_DIR)/"
	sudo chown -R root:root "$(REPO_DIR)"

run: ## Execute bootstrap script from /opt
	sudo BRANCH="$(BRANCH)" REPO_DIR="$(REPO_DIR)" bash "$(REPO_DIR)/bootstrap/bootstrap.sh"

bootstrap: q ## Alias for make q

# ---------------------------------------------------------
# Git and deployment
# ---------------------------------------------------------

pull: ## Safe git pull (fetch + hard reset using token or default credentials)
	@if [ ! -d .git ]; then echo "✗ not a git repository: $(PWD)"; exit 1; fi
	@if [ -n "$$GIT_AUTH_TOKEN" ]; then \
		echo "• Pulling using token from \$GIT_AUTH_TOKEN"; \
		REMOTE="https://$$GIT_AUTH_TOKEN@github.com/SCE-Shamoon-College-of-Engineering/2047-ResearchLab-admin-lab.git"; \
	else \
		echo "• Pulling using $(REPO_HTTPS)"; \
		REMOTE="$(REPO_HTTPS)"; \
	fi; \
	git remote set-url origin "$$REMOTE" || true; \
	git fetch --prune origin; \
	git reset --hard "origin/$(BRANCH)"; \
	git rev-parse --short HEAD | xargs -I{} echo "✓ now on commit {}"

deploy: ## Update code from GitHub and re-run setup (pull → q)
	$(MAKE) pull BRANCH=$(BRANCH)
	sudo $(MAKE) q BRANCH=$(BRANCH)

# ---------------------------------------------------------
# Ansible runs and system logs
# ---------------------------------------------------------

minimal: ## Run minimal.yml playbook
	ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/minimal.yml

converge: ## Run converge.yml playbook
	ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/converge.yml

logs: ## View Ansible or systemd logs
	-@sudo journalctl -u 2047-firstboot.service -e || true
	-@sudo journalctl -u 2047-converge.service  -e || true
	-@sudo tail -n 200 /var/log/2047-ansible-pull.log || true

verify: ## Check presence of systemd units and project files
	@echo ">>> systemd units"; sudo systemctl list-unit-files | grep -E '2047-(firstboot|converge)' || true
	@echo ">>> repository in /opt"; ls -lah "$(REPO_DIR)/ansible" || true
	@echo ">>> state directory"; ls -lah /etc/2047 || true

enable-units: ## Enable services at boot
	sudo systemctl enable 2047-firstboot.service 2047-converge.service 2047-converge.timer || true

restart-units: ## Restart systemd units
	sudo systemctl daemon-reload
	sudo systemctl restart 2047-firstboot.service || true
	sudo systemctl restart 2047-converge.service  || true

status-units: ## Display unit status
	sudo systemctl status --no-pager -l 2047-firstboot.service || true
	sudo systemctl status --no-pager -l 2047-converge.service  || true

lint: ## Run ansible-lint if available
	ansible-lint ansible/ || true

# ---------------------------------------------------------
# PXE / HTTPBoot setup and verification
# ---------------------------------------------------------

pxe-http: ## Configure dnsmasq + HTTP boot and deploy GRUB/autoinstall structure
	@echo "[*] Running PXE HTTP setup on $(PXE_HTTP_IP)..."
	sudo HTTP_IP=$(PXE_HTTP_IP) bash scripts/02-quick-pxe-setup.sh

pxe-verify: ## Verify HTTP endpoints and display log hints
	@echo "[*] Verifying HTTP endpoints on $(PXE_HTTP_IP)..."
	@curl -I http://$(PXE_HTTP_IP)/EFI/BOOT/bootx64.efi || true
	@curl -I http://$(PXE_HTTP_IP)/ubuntu/vmlinuz || true
	@curl -I http://$(PXE_HTTP_IP)/autoinstall/user-data || true
	@echo "Now monitor logs using:"
	@echo "  sudo journalctl -u dnsmasq -f"
	@echo "  sudo tail -f /var/log/apache2/access.log"

pxe-logs: ## Follow dnsmasq and apache2 logs (press Ctrl+C to stop)
	@echo ">>> dnsmasq (journalctl -f)"; \
	sudo journalctl -u dnsmasq -f & \
	PID=$$!; \
	echo ">>> apache2 (tail -f access.log)"; \
	sudo tail -f /var/log/apache2/access.log; \
	trap 'kill $$PID 2>/dev/null || true' EXIT

pxe-restart: ## Restart dnsmasq and apache2 services
	sudo systemctl restart dnsmasq apache2
	@echo "✓ Restarted dnsmasq & apache2 successfully"
render-seed:
	ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/render-seed.yml --ask-vault-pass

