.PHONY: deploy setup loadenv test check-chain

all:
	@echo "Nothing to do"

include .env

check-chain:
ifeq ($(CHAIN),)
	@echo "CHAIN not set: seth, smnt"
endif

deploy: check-chain
ifeq ($(CHAIN), seth)
	@forge script script/Deploy.s.sol \
	--tc DeployScript \
	--fork-url "$(SEPOLIA_RPC_URL)" \
	--private-key $(PRIVATE_KEY) \
	--verify \
	--broadcast
endif

ifeq ($(CHAIN), smnt)
	@forge script script/Deploy.s.sol \
	--tc DeployScript \
	--skip test \
	--fork-url $(MANTLE_SEPOLIA_RPC_URL) \
	--gas-estimate-multiplier 10000000 \
	--private-key $(PRIVATE_KEY) \
	--verify \
	--verifier blockscout \
	--verifier-url https://explorer.sepolia.mantle.xyz/api? \
	--broadcast \
	--slow
endif


setup: check-chain
ifeq ($(CHAIN), seth)
	@forge script script/Setup.s.sol \
	--private-key $(PRIVATE_KEY) \
	--broadcast
endif

ifeq ($(CHAIN), smnt)
	@forge script script/Setup.s.sol \
	--gas-estimate-multiplier 100000000 \
	--private-key $(PRIVATE_KEY) \
	--broadcast \
	--slow
endif
