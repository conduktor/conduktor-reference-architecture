# Global Vars
#############
WORKING_DIR 	     = $(shell pwd)

# Main targets you should run
#############################
.DEFAULT_GOAL := help

.PHONY: help
help: ## Prints help for targets with comments
	@cat $(MAKEFILE_LIST) | grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: start-local-stack
start-local-stack: ## Setup k3d cluster
	$(CURDIR)/01-start.sh

.PHONY: stop-local-stack
stop-local-stack: ## Teardown k3d cluster
	$(CURDIR)/04-stop.sh

.PHONY: install-conduktor-platform
install-conduktor-platform: ## Install Conduktor platform
	$(CURDIR)/02-install-conduktor-platform.sh

.PHONY: init-conduktor-platform
init-conduktor-platform: ## Provision Conduktor platform
	$(CURDIR)/03-init-conduktor-platform.sh
