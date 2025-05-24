// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/// @title NFTAuctionMarketplace
/// @notice A decentralized marketplace for creating, bidding on, and finalizing auctions for ERC721 NFTs
/// @dev Inherits from ReentrancyGuard for security and IERC721Receiver to handle NFT transfers
contract NFTAuctionMarketplace is ReentrancyGuard, IERC721Receiver {
    // Events for auction lifecycle
    /// @notice Emitted when a new auction is created
    /// @param auctionId The unique ID of the auction
    /// @param seller The address of the seller creating the auction
    /// @param nft The address of the NFT contract
    /// @param nftId The ID of the NFT being auctioned
    /// @param startingBid The minimum bid amount
    /// @param endAt The timestamp when the auction ends
    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed nft,
        uint256 nftId,
        uint256 startingBid,
        uint256 endAt
    );
    /// @notice Emitted when a bid is placed on an auction
    /// @param auctionId The ID of the auction
    /// @param bidder The address of the bidder
    /// @param amount The bid amount in wei
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 amount);
    /// @notice Emitted when a bid is withdrawn from an auction
    /// @param auctionId The ID of the auction
    /// @param bidder The address of the bidder withdrawing their bid
    /// @param amount The withdrawn bid amount
    event BidWithdrawn(uint256 indexed auctionId, address indexed bidder, uint256 amount);
    /// @notice Emitted when an auction ends
    /// @param auctionId The ID of the auction
    /// @param winner The address of the winning bidder (or address(0) if no bids)
    /// @param amount The final bid amount (or 0 if no bids)
    event AuctionEnded(uint256 indexed auctionId, address indexed winner, uint256 amount);
    /// @notice Emitted when an auction is cancelled
    /// @param auctionId The ID of the auction
    event AuctionCancelled(uint256 indexed auctionId);

    // Auction structure
    /// @notice Struct to store auction details
    struct Auction {
        address payable seller; // Seller of the NFT
        address nft; // NFT contract address
        uint256 nftId; // NFT token ID
        uint256 startingBid; // Minimum bid amount
        uint256 highestBid; // Current highest bid
        address highestBidder; // Address of the highest bidder
        uint256 endAt; // Auction end timestamp
        bool started; // Whether the auction has started
        bool ended; // Whether the auction has ended
        mapping(address => uint256) bids; // Tracks bids per bidder
    }

    // State variables
    mapping(uint256 => Auction) public auctions; // Mapping of auction ID to auction details
    uint256 public auctionCount; // Tracks total number of auctions created

    // Constants
    uint256 public constant MINIMUM_AUCTION_DURATION = 1 hours; // Minimum duration for an auction
    uint256 public constant EXTEND_DURATION = 15 minutes; // Duration to extend auction if bid placed near end

    // Modifiers
    /// @notice Ensures the specified auction ID exists
    /// @param _auctionId The ID of the auction to check
    modifier auctionExists(uint256 _auctionId) {
        require(_auctionId < auctionCount, "Auction does not exist");
        _;
    }

    /// @notice Ensures the auction has not ended and is still within its time limit
    /// @param _auctionId The ID of the auction to check
    modifier auctionNotEnded(uint256 _auctionId) {
        require(!auctions[_auctionId].ended, "Auction has ended");
        require(block.timestamp < auctions[_auctionId].endAt, "Auction time expired");
        _;
    }

    /// @notice Implements IERC721Receiver to handle safe NFT transfers
    /// @dev Returns the function selector to confirm compatibility with ERC721
    /// @return The IERC721Receiver interface selector
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector; // Confirm successful receipt of NFT
    }

    /// @notice Creates a new auction for an ERC721 NFT
    /// @dev Transfers the NFT to the contract and initializes auction parameters
    /// @param _nft The address of the ERC721 NFT contract
    /// @param _nftId The ID of the NFT to auction
    /// @param _startingBid The minimum bid amount in wei
    /// @param _duration The duration of the auction in seconds
    function createAuction(address _nft, uint256 _nftId, uint256 _startingBid, uint256 _duration)
        external
        nonReentrant
    {
        require(_duration >= MINIMUM_AUCTION_DURATION, "Duration too short"); // Ensure minimum duration
        require(_startingBid > 0, "Starting bid must be greater than 0"); // Ensure non-zero starting bid

        IERC721 nft = IERC721(_nft);
        require(nft.ownerOf(_nftId) == msg.sender, "Not NFT owner"); // Verify caller owns the NFT
        require(
            nft.getApproved(_nftId) == address(this) || nft.isApprovedForAll(msg.sender, address(this)),
            "Contract not approved"
        ); // Verify contract is approved to transfer NFT

        uint256 auctionId = auctionCount++; // Increment and assign new auction ID
        Auction storage auction = auctions[auctionId]; // Reference to new auction
        auction.seller = payable(msg.sender); // Set seller
        auction.nft = _nft; // Set NFT contract address
        auction.nftId = _nftId; // Set NFT ID
        auction.startingBid = _startingBid; // Set starting bid
        auction.highestBid = _startingBid; // Initialize highest bid
        auction.endAt = block.timestamp + _duration; // Set auction end time
        auction.started = true; // Mark auction as started

        // Transfer NFT to contract for safekeeping during auction
        nft.safeTransferFrom(msg.sender, address(this), _nftId);

        emit AuctionCreated(auctionId, msg.sender, _nft, _nftId, _startingBid, auction.endAt); // Emit event
    }

    /// @notice Places a bid on an existing auction
    /// @dev Updates highest bid, refunds previous bidder, and extends auction if necessary
    /// @param _auctionId The ID of the auction to bid on
    function bid(uint256 _auctionId)
        external
        payable
        auctionExists(_auctionId)
        auctionNotEnded(_auctionId)
        nonReentrant
    {
        Auction storage auction = auctions[_auctionId];
        require(msg.value > auction.highestBid, "Bid too low"); // Ensure bid exceeds current highest
        require(msg.sender != auction.seller, "Seller cannot bid"); // Prevent seller from bidding
        require(msg.value <= address(msg.sender).balance, "Insufficient balance"); // Ensure sufficient funds

        // Refund previous highest bidder, if any
        if (auction.highestBidder != address(0)) {
            (bool success,) = auction.highestBidder.call{value: auction.bids[auction.highestBidder]}("");
            require(success, "Refund failed"); // Revert if refund fails
        }

        auction.bids[msg.sender] = msg.value; // Record new bid
        auction.highestBid = msg.value; // Update highest bid
        auction.highestBidder = msg.sender; // Update highest bidder

        // Extend auction if bid is placed in the last 15 minutes
        if (auction.endAt - block.timestamp < EXTEND_DURATION) {
            auction.endAt = block.timestamp + EXTEND_DURATION; // Extend auction end time
        }

        emit BidPlaced(_auctionId, msg.sender, msg.value); // Emit event
    }

    /// @notice Withdraws a non-highest bid from an auction
    /// @dev Refunds the bidder and clears their bid
    /// @param _auctionId The ID of the auction
    function withdrawBid(uint256 _auctionId) external auctionExists(_auctionId) nonReentrant {
        Auction storage auction = auctions[_auctionId];
        require(msg.sender != auction.highestBidder, "Highest bidder cannot withdraw"); // Prevent highest bidder withdrawal
        uint256 amount = auction.bids[msg.sender]; // Get bidder's amount
        require(amount > 0, "No bid to withdraw"); // Ensure bidder has a bid

        auction.bids[msg.sender] = 0; // Clear bid
        payable(msg.sender).transfer(amount); // Refund bidder

        emit BidWithdrawn(_auctionId, msg.sender, amount); // Emit event
    }

    /// @notice Ends an auction and finalizes the outcome
    /// @dev Transfers NFT to winner (if any) and funds to seller, or returns NFT to seller if no bids
    /// @param _auctionId The ID of the auction to end
    function endAuction(uint256 _auctionId) external auctionExists(_auctionId) nonReentrant {
        Auction storage auction = auctions[_auctionId];
        require(auction.started, "Auction not started"); // Ensure auction is active
        require(!auction.ended, "Auction already ended"); // Ensure not already ended
        require(block.timestamp >= auction.endAt, "Auction not yet ended"); // Ensure auction time has passed

        auction.ended = true; // Mark auction as ended

        if (auction.highestBidder != address(0)) {
            // Transfer NFT to winner and funds to seller
            IERC721(auction.nft).safeTransferFrom(address(this), auction.highestBidder, auction.nftId);
            auction.seller.transfer(auction.highestBid);
            emit AuctionEnded(_auctionId, auction.highestBidder, auction.highestBid); // Emit event with winner
        } else {
            // Return NFT to seller if no bids
            IERC721(auction.nft).safeTransferFrom(address(this), auction.seller, auction.nftId);
            emit AuctionEnded(_auctionId, address(0), 0); // Emit event with no winner
        }
    }

    /// @notice Cancels an auction with no bids
    /// @dev Returns the NFT to the seller and marks the auction as ended
    /// @param _auctionId The ID of the auction to cancel
    function cancelAuction(uint256 _auctionId) external auctionExists(_auctionId) nonReentrant {
        Auction storage auction = auctions[_auctionId];
        require(msg.sender == auction.seller, "Only seller can cancel"); // Ensure caller is seller
        require(auction.started && !auction.ended, "Auction not active"); // Ensure auction is active
        require(auction.highestBidder == address(0), "Bids already placed"); // Ensure no bids exist

        auction.ended = true; // Mark auction as ended
        IERC721(auction.nft).safeTransferFrom(address(this), auction.seller, auction.nftId); // Return NFT to seller

        emit AuctionCancelled(_auctionId); // Emit event
    }

    /// @notice Retrieves details of an auction
    /// @dev Returns all auction parameters
    /// @param _auctionId The ID of the auction
    /// @return seller The seller's address
    /// @return nft The NFT contract address
    /// @return nftId The NFT token ID
    /// @return startingBid The starting bid amount
    /// @return highestBid The current highest bid
    /// @return highestBidder The address of the highest bidder
    /// @return endAt The auction end timestamp
    /// @return started Whether the auction has started
    /// @return ended Whether the auction has ended
    function getAuction(uint256 _auctionId)
        external
        view
        auctionExists(_auctionId)
        returns (
            address seller,
            address nft,
            uint256 nftId,
            uint256 startingBid,
            uint256 highestBid,
            address highestBidder,
            uint256 endAt,
            bool started,
            bool ended
        )
    {
        Auction storage auction = auctions[_auctionId];
        return (
            auction.seller,
            auction.nft,
            auction.nftId,
            auction.startingBid,
            auction.highestBid,
            auction.highestBidder,
            auction.endAt,
            auction.started,
            auction.ended
        );
    }

    /// @notice Retrieves the bid amount for a specific bidder in an auction
    /// @param _auctionId The ID of the auction
    /// @param _bidder The address of the bidder
    /// @return The bid amount in wei
    function getBid(uint256 _auctionId, address _bidder) external view auctionExists(_auctionId) returns (uint256) {
        return auctions[_auctionId].bids[_bidder];
    }
}