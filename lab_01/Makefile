# Lab 01 - WordPress on AWS with ELB, RDS, EFS and two EC2 web servers.
# Every step is an AWS CLI script in scripts/ that only creates (it assumes the
# resources do not exist yet). If a step fails: make destroy, then make up.
# Override settings on the command line, e.g.
#   make up AWS_REGION=us-east-1 PROJECT=lab01-demo

SHELL := /bin/bash
S     := scripts
N     ?= 1

.DEFAULT_GOAL := help
.PHONY: help check network security-groups efs rds keypair ec2 elb install \
        up verify seed db-check status ssh logs destroy clean cleanup

help: ## Show this help
	@echo "Usage: make <target>"
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

up: ## Create everything and install WordPress (~15 min)
	@$(S)/check.sh
	@$(S)/00-network.sh
	@$(S)/01-security-groups.sh
	@$(S)/02-efs.sh
	@$(S)/03-rds.sh
	@$(S)/04-keypair.sh
	@$(S)/05-ec2.sh
	@$(S)/06-elb.sh
	@$(S)/07-wordpress-install.sh
	@$(S)/verify.sh

check: ## Check local tools and AWS credentials
	@$(S)/check.sh

network: ## Pick the VPC and two subnets in different AZs
	@$(S)/00-network.sh

security-groups: ## Create and attach firewall rules (security groups)
	@$(S)/01-security-groups.sh

efs: ## Create the network filesystem (EFS) + mount targets
	@$(S)/02-efs.sh

rds: ## Create the MySQL database (RDS)
	@$(S)/03-rds.sh

keypair: ## Create the SSH key pair
	@$(S)/04-keypair.sh

ec2: ## Create the two web-server VMs (EC2)
	@$(S)/05-ec2.sh

elb: ## Create the load balancer (ALB) and register the VMs
	@$(S)/06-elb.sh

install: ## Install WordPress through the load balancer
	@$(S)/07-wordpress-install.sh

verify: ## Access WordPress via the ALB and show which VM answered
	@$(S)/verify.sh

seed: ## Insert sample posts into RDS through WordPress (FORCE=1 to add again)
	@$(S)/seed.sh

db-check: ## Prove WordPress uses RDS: read seed posts from each VM + RDS metrics
	@$(S)/db-check.sh

status: ## Show the state of all resources
	@$(S)/status.sh

ssh: ## SSH into web server N (default N=1)
	@$(S)/ssh.sh $(N)

logs: ## Show the bootstrap log of web server N (default N=1)
	@$(S)/ssh.sh $(N) sudo cat /var/log/wordpress-bootstrap.log

destroy: ## Delete every AWS resource of this lab (YES=1 skips the prompt)
	@$(S)/destroy.sh

clean: ## Remove local state (.state/: keys, secrets, generated user-data)
	rm -rf .state

cleanup: ## Delete ALL AWS resources AND local state (YES=1 skips the prompt)
	@CLEAN_STATE=1 $(S)/destroy.sh
