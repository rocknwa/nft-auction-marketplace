# NFT Auction Marketplace

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Solidity Version](https://img.shields.io/badge/Solidity-%5E0.8.3-blue)

A decentralized marketplace for auctioning ERC721 NFTs, built with Solidity and powered by the Ethereum blockchain. This smart contract enables users to create auctions, place bids, withdraw bids, end auctions, and cancel auctions securely, with features like auction time extension and reentrancy protection.

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Deployment](#deployment)
- [Testing](#testing)
- [Usage](#usage)
- [Smart Contract Details](#smart-contract-details)
- [Security Considerations](#security-considerations)
- [Contributing](#contributing)
- [License](#license)
- [Contact](#contact)

---

## Overview

The **NFTAuctionMarketplace** is a robust, secure, and gas-efficient smart contract for conducting NFT auctions on Ethereum. It leverages OpenZeppelin's ERC721 and `ReentrancyGuard` standards to ensure compatibility and security. The contract supports key auction functionalities while incorporating protections against common vulnerabilities like reentrancy attacks.

---

## Features

- **Create Auctions:** Sellers can list ERC721 NFTs for auction with a starting bid and duration.
- **Place Bids:** Bidders can place bids exceeding the current highest bid, with automatic refunds for outbid participants.
- **Withdraw Bids:** Non-highest bidders can withdraw their bids securely.
- **End Auctions:** Auctions finalize automatically after the duration, transferring the NFT to the highest bidder and funds to the seller.
- **Cancel Auctions:** Sellers can cancel auctions without bids, reclaiming their NFT.
- **Time Extension:** Bids placed in the last 15 minutes extend the auction to prevent sniping.
- **Reentrancy Protection:** Uses OpenZeppelin's `ReentrancyGuard` to mitigate reentrancy attacks.
- **Comprehensive Testing:** Extensive test suite using Foundry to verify contract behavior.

---

## Prerequisites

To work with this project, ensure you have the following installed:

- [Foundry](https://book.getfoundry.sh/) (for compilation, testing, and deployment)
- [Git](https://git-scm.com/) (for version control)
- An Ethereum wallet with testnet/mainnet ETH (e.g., MetaMask)
- Access to an Ethereum node or provider (e.g., Infura, Alchemy)

---

## Installation

**Clone the Repository:**
```bash
git clone https://github.com/rocknwa/nft-auction-marketplace.git
cd nft-auction-marketplace
```

**Install Foundry (if not already installed):**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

**Install Dependencies:**

This project uses OpenZeppelin contracts. Install them via Forge:
```bash
forge install openzeppelin/openzeppelin-contracts --no-commit
```

**Compile the Contracts:**
```bash
forge build
```

---

## Deployment

To deploy the `NFTAuctionMarketplace` contract to an Ethereum network (e.g., Sepolia testnet or mainnet), use the `forge create` command. Ensure you have an Ethereum provider URL and a private key for deployment.

**Set Environment Variables:**

Create a `.env` file in the project root with the following:
```bash
PRIVATE_KEY=your_private_key
RPC_URL=your_ethereum_node_url  # e.g., https://sepolia.infura.io/v3/your_project_id
```

**Source the Environment Variables:**
```bash
source .env
```

**Deploy the Contract:**
```bash
forge create src/Auction.sol:NFTAuctionMarketplace \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --etherscan-api-key your_etherscan_api_key \
  --verify
```
- Replace `your_etherscan_api_key` with your Etherscan API key for contract verification.
- The `--verify` flag verifies the contract on Etherscan (if deploying to a supported network).

**Output:**

After deployment, Forge will provide the contract address and transaction hash. Save these for interaction.

---

## Testing

The project includes a comprehensive test suite written with Foundry to ensure contract reliability.

**Run Tests:**
```bash
forge test
```

**Verbose Output (for detailed test results):**
```bash
forge test -vvv
```

**Test Coverage:**
Generate a coverage report to verify tested code:
```bash
forge coverage
```

The test suite (`test/Auction.t.sol`) covers:

- Auction creation and validation
- Bid placement and withdrawal
- Auction ending with/without bids
- Auction cancellation
- Reentrancy protection
- Edge cases (e.g., invalid durations, non-owner actions)

---

## Usage

- **Create an Auction:**  
  Approve the NFTAuctionMarketplace contract to manage your NFT.  
  Call:  
  `createAuction(address _nft, uint256 _nftId, uint256 _startingBid, uint256 _duration)`

- **Place a Bid:**  
  Call:  
  `bid(uint256 _auctionId)`  
  (with a value exceeding the current highest bid)

- **Withdraw a Bid:**  
  Call:  
  `withdrawBid(uint256 _auctionId)`  
  (if not the highest bidder)

- **End an Auction:**  
  After the auction duration, call:  
  `endAuction(uint256 _auctionId)`

- **Cancel an Auction:**  
  If no bids are placed, the seller can call:  
  `cancelAuction(uint256 _auctionId)`

- **Query Auction Details:**  
  - `getAuction(uint256 _auctionId)` — retrieve auction details  
  - `getBid(uint256 _auctionId, address _bidder)` — check a bidder's bid amount

---

## Smart Contract Details

- **Contract:** `NFTAuctionMarketplace` (`src/Auction.sol`)
- **Standard:** ERC721 (via OpenZeppelin)
- **Security:** Uses `ReentrancyGuard` for protection against reentrancy attacks.

**Modifiers:**
- `auctionExists`: Ensures the auction ID is valid.
- `auctionNotEnded`: Ensures the auction is active and within its time limit.

**Constants:**
- `MINIMUM_AUCTION_DURATION`: 1 hour (minimum auction duration)
- `EXTEND_DURATION`: 15 minutes (extends auction if bid placed near end)

**Events:**  
Emitted for auction creation, bid placement, bid withdrawal, auction ending, and cancellation.

---

## Security Considerations

- **Reentrancy Protection:** The `nonReentrant` modifier prevents reentrancy attacks during bid placement, withdrawal, and auction finalization.
- **Input Validation:** Strict checks ensure valid NFT ownership, approvals, bid amounts, and auction durations.
- **Safe Transfers:** Uses `safeTransferFrom` for ERC721 NFTs to ensure compatibility with non-standard implementations.
- **Testing:** Comprehensive test suite verifies edge cases and attack vectors (e.g., reentrancy, invalid inputs).
- **Gas Optimization:** Efficient storage (using mappings and structs) and minimal external calls.

---

## Contributing

Contributions are welcome! To contribute:

1. Fork the repository.
2. Create a feature branch:  
   `git checkout -b feature/your-feature`
3. Commit changes:  
   `git commit -m "Add your feature"`
4. Push to the branch:  
   `git push origin feature/your-feature`
5. Open a pull request with a detailed description.

Please ensure all tests pass and adhere to the Solidity Style Guide.

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

## Contact

For inquiries, feedback, or collaboration opportunities:

Email:  [anitherock44@gmail.com](anitherock44@gmail.com)