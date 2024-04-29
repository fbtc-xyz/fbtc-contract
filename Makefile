.PHONY:

# Usage:
# make deploy setup chain=seth tag=dev xtn=true

all:
	@echo "Nothing to do"

include .env

xtn ?= true
deploy:
ifeq ($(chain), seth)
	@forge script script/Deploy.s.sol \
	--tc DeployScript \
	-s `cast calldata "deploy(string,string,bool)" $(chain) $(tag) $(xtn)` \
	--fork-url "$(SEPOLIA_RPC_URL)" \
	--private-key $(PRIVATE_KEY) \
	--verify \
	--broadcast
else ifeq ($(chain), smnt)
	@forge script script/Deploy.s.sol \
	--tc DeployScript \
	-s `cast calldata "deploy(string,string,bool)" $(chain) $(tag) $(xtn)` \
	--skip test \
	--fork-url $(MANTLE_SEPOLIA_RPC_URL) \
	--gas-estimate-multiplier 10000000 \
	--private-key $(PRIVATE_KEY) \
	--verify \
	--verifier blockscout \
	--verifier-url https://explorer.sepolia.mantle.xyz/api? \
	--broadcast \
	--slow
else
	$(error Usage: make deploy chain=seth tag=dev xtn=true)
endif

setup:
ifeq ($(chain), seth)
	@forge script script/Setup.s.sol \
	-s `cast calldata "initConfig(string,string)" $(chain) $(tag) ` \
	--private-key $(PRIVATE_KEY) \
	--broadcast
else ifeq ($(chain), smnt)
	@forge script script/Setup.s.sol \
	-s `cast calldata "initConfig(string,string)" $(chain) $(tag) ` \
	--gas-estimate-multiplier 100000000 \
	--private-key $(PRIVATE_KEY) \
	--broadcast \
	--slow
else
	$(error Usage: make setup chain=seth tag=dev)
endif
