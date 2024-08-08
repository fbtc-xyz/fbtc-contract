.PHONY:

# Usage:
# make deploy chain=seth tag=dev xtn=true
# make add_minter chain=seth tag=dev  minter=dev
# make add_merchant chain=seth tag=dev merchant=dev1

all:
	@echo "Nothing to do"

include .env

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

set_fee:
ifeq ($(chain), seth)
	@forge script script/Config.s.sol \
	-s `cast calldata "setupFee(string,string)" $(chain) $(tag)` \
	--broadcast
else ifeq ($(chain), smnt)
	@forge script script/Config.s.sol \
	-s `cast calldata "setupFee(string,string)" $(chain) $(tag)` \
	--gas-estimate-multiplier 100000000 \
	--broadcast \
	--slow
else
	$(error Usage: make set_fee chain=seth tag=dev)
endif
