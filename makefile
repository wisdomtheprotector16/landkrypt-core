# Makefile for LandKrypt Project (Foundry)

# Variables
FOUNDRY_DIR = ~/.foundry
FOUNDRY_BIN = $(FOUNDRY_DIR)/bin
FORGE = $(FOUNDRY_BIN)/forge
CAST = $(FOUNDRY_BIN)/cast
SOLC_VERSION = 0.8.0

# Default target
all: install-deps compile test

# Install Foundry and dependencies
install-deps:
	@echo "Installing Foundry..."
	curl -L https://foundry.paradigm.xyz | bash
	$(FOUNDRY_DIR)/bin/foundryup
	@echo "Foundry installed."

	@echo "Installing Node.js dependencies..."
	npm install @openzeppelin/contracts @chainlink/contracts dotenv
	@echo "Node.js dependencies installed."

# Compile contracts
compile:
	@echo "Compiling contracts..."
	$(FORGE) build
	@echo "Contracts compiled."

# Run tests
test:
	@echo "Running tests..."
	$(FORGE) test
	@echo "Tests completed."

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	$(FORGE) clean
	@echo "Build artifacts cleaned."

# Deploy contracts to local Anvil node
deploy-local:
	@echo "Deploying contracts to local Anvil node..."
	$(FORGE) create --rpc-url http://localhost:8545 --private-key $(PRIVATE_KEY) src/LandKryptStablecoin.sol:LandKryptStablecoin
	@echo "Contracts deployed to local Anvil node."

# Deploy contracts to Goerli testnet
deploy-goerli:
	@echo "Deploying contracts to Goerli testnet..."
	$(FORGE) create --rpc-url $(GOERLI_RPC_URL) --private-key $(PRIVATE_KEY) src/LandKryptStablecoin.sol:LandKryptStablecoin
	@echo "Contracts deployed to Goerli testnet."

# Deploy contracts to Ethereum mainnet
deploy-mainnet:
	@echo "Deploying contracts to Ethereum mainnet..."
	$(FORGE) create --rpc-url $(MAINNET_RPC_URL) --private-key $(PRIVATE_KEY) src/LandKryptStablecoin.sol:LandKryptStablecoin
	@echo "Contracts deployed to Ethereum mainnet."

# Format Solidity code
format:
	@echo "Formatting Solidity code..."
	$(FORGE) fmt
	@echo "Solidity code formatted."

# Lint Solidity code
lint:
	@echo "Linting Solidity code..."
	npx solhint 'src/**/*.sol'
	@echo "Solidity code linted."

# Verify contracts on Etherscan
verify:
	@echo "Verifying contracts on Etherscan..."
	$(FORGE) verify-contract --chain-id 5 --etherscan-api-key $(ETHERSCAN_API_KEY) <CONTRACT_ADDRESS> src/LandKryptStablecoin.sol:LandKryptStablecoin
	@echo "Contracts verified on Etherscan."

# Start local Anvil node
start-anvil:
	@echo "Starting local Anvil node..."
	$(FOUNDRY_BIN)/anvil
	@echo "Local Anvil node started."

# Run coverage analysis
coverage:
	@echo "Running coverage analysis..."
	$(FORGE) coverage
	@echo "Coverage analysis completed."

# Run gas usage report
gas-report:
	@echo "Generating gas usage report..."
	$(FORGE) test --gas-report
	@echo "Gas usage report generated."

# Help command
help:
	@echo "Available commands:"
	@echo "  make install-deps    - Install Foundry and dependencies"
	@echo "  make compile         - Compile contracts"
	@echo "  make test            - Run tests"
	@echo "  make clean           - Clean build artifacts"
	@echo "  make deploy-local    - Deploy contracts to local Anvil node"
	@echo "  make deploy-goerli   - Deploy contracts to Goerli testnet"
	@echo "  make deploy-mainnet  - Deploy contracts to Ethereum mainnet"
	@echo "  make format          - Format Solidity code"
	@echo "  make lint            - Lint Solidity code"
	@echo "  make verify          - Verify contracts on Etherscan"
	@echo "  make start-anvil     - Start local Anvil node"
	@echo "  make coverage        - Run coverage analysis"
	@echo "  make gas-report      - Generate gas usage report"
	@echo "  make help            - Show this help message"

.PHONY: all install-deps compile test clean deploy-local deploy-goerli deploy-mainnet format lint verify start-anvil coverage gas-report help