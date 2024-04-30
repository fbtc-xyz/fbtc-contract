.PHONY:

# Usage:
# make deploy chain=seth tag=dev xtn=true
# make add_minter chain=seth tag=dev  minter=dev
# make add_merchant chain=seth tag=dev merchant=dev1

all:
	@echo "Nothing to do"

include .env

xtn ?= true
deploy:
ifeq ($(chain), seth)
	@forge script script/Deploy.s.sol \
	--tc DeployScript \
	-s `cast calldata "deploy(string,string,bool)" $(chain) $(tag) $(xtn)` \
	--private-key $(PRIVATE_KEY) \
	--verify \
	--broadcast
else ifeq ($(chain), smnt)
	@forge script script/Deploy.s.sol \
	--tc DeployScript \
	-s `cast calldata "deploy(string,string,bool)" $(chain) $(tag) $(xtn)` \
	--skip test \
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

add_minter:
ifeq ($(chain), seth)
	@forge script script/Config.s.sol \
	-s `cast calldata "addMinter(string,string,string)" $(chain) $(tag) $(minter)` \
	--broadcast
else ifeq ($(chain), smnt)
	@forge script script/Config.s.sol \
	-s `cast calldata "addMinter(string,string,string)" $(chain) $(tag) $(minter)` \
	--gas-estimate-multiplier 100000000 \
	--broadcast \
	--slow
else
	$(error Usage: make add_minter chain=seth tag=dev minter=dev)
endif

add_merchant:
ifeq ($(chain), seth)
	@forge script script/Config.s.sol \
	-s `cast calldata "addMerchaint(string,string,string)" $(chain) $(tag) $(merchant)` \
	--broadcast
else ifeq ($(chain), smnt)
	@forge script script/Config.s.sol \
	-s `cast calldata "addMerchaint(string,string,string)" $(chain) $(tag) $(merchant)` \
	--gas-estimate-multiplier 100000000 \
	--broadcast \
	--slow
else
	$(error Usage: make add_merchant chain=seth tag=dev merchant=dev1)
endif
