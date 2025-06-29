// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/// @title NFTAuctionMarketplace
/// @notice A decentralized marketplace for creating, bidding on, and finalizing auctions for ERC721 NFTs
/// @dev Inherits from ReentrancyGuard for security against reentrancy attacks and IERC721Receiver to handle NFT transfers
contract NFTAuctionMarketplace is ReentrancyGuard, IERC721Receiver {
    // Custom Errors
    /// @notice Thrown when the specified auction ID does not exist
    error AuctionDoesNotExist();
    /// @notice Thrown when attempting to interact with an auction that has already ended
    error AuctionHasEnded();
    /// @notice Thrown when attempting to bid on an auction past its end time
    error AuctionTimeExpired();
    /// @notice Thrown when auction duration is less than the minimum allowed
    error DurationTooShort();
    /// @notice Thrown when the starting bid is zero
    error InvalidStartingBid();
    /// @notice Thrown when the caller is not the owner of the NFT
    error NotNFTOwner();
    /// @notice Thrown when the contract is not approved to transfer the NFT
    error ContractNotApproved();
    /// @notice Thrown when a bid is less than or equal to the current highest bid
    error BidTooLow();
    /// @notice Thrown when the seller attempts to bid on their own auction
    error SellerCannotBid();
    /// @notice Thrown when a refund to the previous highest bidder fails
    error RefundFailed();
    /// @notice Thrown when the highest bidder attempts to withdraw their bid
    error HighestBidderCannotWithdraw();
    /// @notice Thrown when attempting to end an auction that was never started
    error AuctionNotStarted();
    /// @notice Thrown when attempting to end an auction before its end time
    error AuctionNotYetEnded();
    /// @notice Thrown when a non-seller attempts to cancel an auction
    error OnlySellerCanCancel();
    /// @notice Thrown when attempting to cancel an inactive or ended auction
    error AuctionNotActive();
    /// @notice Thrown when attempting to cancel an auction with existing bids
    error BidsAlreadyPlaced();

    // Events for auction lifecycle
    /// @notice Emitted when a new auction is created
    /// @param auctionId The unique ID of the auction
    /// @param seller The address of the seller creating the auction
    /// @param nft The address of the NFT contract
    /// @param nftId The ID of the NFT being auctioned
    /// @param startingBid The minimum bid amount in wei
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
    /// @param amount The withdrawn bid amount in wei
    event BidWithdrawn(uint256 indexed auctionId, address indexed bidder, uint256 amount);
    /// @notice Emitted when an auction ends
    /// @param auctionId The ID of the auction
    /// @param winner The address of the winning bidder (or address(0) if no bids)
    /// @param amount The final bid amount in wei (or 0 if no bids)
    event AuctionEnded(uint256 indexed auctionId, address indexed winner, uint256 amount);
    /// @notice Emitted when an auction is cancelled
    /// @param auctionId The ID of the auction
    event AuctionCancelled(uint256 indexed auctionId);

    // Auction structure
    /// @notice Struct to store auction details
    struct Auction {
        address payable seller; // The address of the seller, payable for fund transfers
        address nft; // The address of the ERC721 NFT contract
        uint256 nftId; // The token ID of the NFT being auctioned
        uint256 startingBid; // The minimum bid amount in wei
        uint256 highestBid; // The current highest bid in wei
        address highestBidder; // The address of the current highest bidder
        uint256 endAt; // The timestamp when the auction ends
        bool started; // Flag indicating if the auction has started
        bool ended; // Flag indicating if the auction has ended
        mapping(address => uint256) bids; // Mapping of bidder addresses to their bid amounts
    }

    // State variables
    /// @notice Mapping of auction IDs to their respective Auction structs
    mapping(uint256 => Auction) public auctions;
    /// @notice Counter for the total number of auctions created
    uint256 public auctionCount;

    // Constants
    /// @notice Minimum duration for an auction (1 hour)
    uint256 public constant MINIMUM_AUCTION_DURATION = 1 hours;
    /// @notice Duration to extend an auction if a bid is placed near the end (15 minutes)
    uint256 public constant EXTEND_DURATION = 15 minutes;

    // Modifiers
    /// @notice Ensures the specified auction ID exists
    /// @param _auctionId The ID of the auction to check
    modifier auctionExists(uint256 _auctionId) {
        if (_auctionId >= auctionCount) revert AuctionDoesNotExist();
        _;
    }

    /// @notice Ensures the auction has not ended and is within its time limit
    /// @param _auctionId The ID of the auction to check
    modifier auctionNotEnded(uint256 _auctionId) {
        if (auctions[_auctionId].ended) revert AuctionHasEnded();
        if (block.timestamp >= auctions[_auctionId].endAt) {
            revert AuctionTimeExpired();
        }
        _;
    }

    /// @notice Implements IERC721Receiver to handle safe NFT transfers
    /// @dev Returns the function selector to confirm compatibility with ERC721
    /// @param operator The address which called the safeTransferFrom function
    /// @param from The address which previously owned the token
    /// @param tokenId The NFT identifier which is being transferred
    /// @param data Additional data with no specified format
    /// @return bytes4 The IERC721Receiver interface selector
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        pure
        override
        returns (bytes4)
    {
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
        // Validate auction duration
        if (_duration < MINIMUM_AUCTION_DURATION) revert DurationTooShort();
        // Validate starting bid
        if (_startingBid == 0) revert InvalidStartingBid();

        // Initialize NFT contract interface
        IERC721 nft = IERC721(_nft);
        // Verify NFT ownership
        if (nft.ownerOf(_nftId) != msg.sender) revert NotNFTOwner();
        // Verify contract approval for NFT transfer
        if (nft.getApproved(_nftId) != address(this) && !nft.isApprovedForAll(msg.sender, address(this))) {
            revert ContractNotApproved();
        }

        // Create new auction
        uint256 auctionId = auctionCount++;
        Auction storage auction = auctions[auctionId];
        auction.seller = payable(msg.sender); // Set seller as payable for fund transfers
        auction.nft = _nft; // Store NFT contract address
        auction.nftId = _nftId; // Store NFT token ID
        auction.startingBid = _startingBid; // Set minimum bid
        auction.highestBid = _startingBid; // Initialize highest bid to starting bid
        auction.endAt = block.timestamp + _duration; // Calculate auction end time
        auction.started = true; // Mark auction as started

        // Transfer NFT to contract for safekeeping during auction
        nft.safeTransferFrom(msg.sender, address(this), _nftId);

        // Emit auction creation event
        emit AuctionCreated(auctionId, msg.sender, _nft, _nftId, _startingBid, auction.endAt);
    }

    /// @notice Places a bid on an existing auction
    /// @dev Updates highest bid, refunds previous bidder, and extends auction if bid is placed near end
    /// @param _auctionId The ID of the auction to bid on
    function bid(uint256 _auctionId)
        external
        payable
        auctionExists(_auctionId)
        auctionNotEnded(_auctionId)
        nonReentrant
    {
        Auction storage auction = auctions[_auctionId];
        // Validate bid amount
        if (msg.value <= auction.highestBid) revert BidTooLow();
        // Prevent seller from bidding
        if (msg.sender == auction.seller) revert SellerCannotBid();

        uint256 amount = auction.bids[auction.highestBidder];
        auction.bids[auction.highestBidder] = 0;
        // Refund previous highest bidder, if any
        if (auction.highestBidder != address(0)) {
            (bool success,) = auction.highestBidder.call{value: amount}("");
            if (!success) revert RefundFailed();
        }

        // Record new bid
        auction.bids[msg.sender] = msg.value;
        auction.highestBid = msg.value;
        auction.highestBidder = msg.sender;

        // Extend auction if bid is placed in the last 15 minutes
        if (auction.endAt - block.timestamp < EXTEND_DURATION) {
            auction.endAt = block.timestamp + EXTEND_DURATION;
        }

        // Emit bid placement event
        emit BidPlaced(_auctionId, msg.sender, msg.value);
    }

    /// @notice Ends an auction and finalizes the outcome
    /// @dev Transfers NFT to winner (if any) and funds to seller, or returns NFT to seller if no bids
    /// @param _auctionId The ID of the auction to end
    function endAuction(uint256 _auctionId) external auctionExists(_auctionId) nonReentrant {
        Auction storage auction = auctions[_auctionId];
        // Ensure auction is started
        if (!auction.started) revert AuctionNotStarted();
        // Ensure auction is not already ended
        if (auction.ended) revert AuctionHasEnded();
        // Ensure auction time has expired
        if (block.timestamp < auction.endAt) revert AuctionNotYetEnded();

        // Mark auction as ended
        auction.ended = true;

        // Handle auction outcome based on bids
        if (auction.highestBidder != address(0)) {
            // Transfer NFT to winner and funds to seller
            IERC721(auction.nft).safeTransferFrom(address(this), auction.highestBidder, auction.nftId);
            auction.seller.transfer(auction.highestBid);
            emit AuctionEnded(_auctionId, auction.highestBidder, auction.highestBid);
        } else {
            // Return NFT to seller if no bids
            IERC721(auction.nft).safeTransferFrom(address(this), auction.seller, auction.nftId);
            emit AuctionEnded(_auctionId, address(0), 0);
        }
    }

    /// @notice Cancels an auction with no bids
    /// @dev Returns the NFT to the seller and marks the auction as ended
    /// @param _auctionId The ID of the auction to cancel
    function cancelAuction(uint256 _auctionId) external auctionExists(_auctionId) nonReentrant {
        Auction storage auction = auctions[_auctionId];
        // Ensure only the seller can cancel
        if (msg.sender != auction.seller) revert OnlySellerCanCancel();
        // Ensure auction is active
        if (!auction.started || auction.ended) revert AuctionNotActive();
        // Ensure no bids have been placed
        if (auction.highestBidder != address(0)) revert BidsAlreadyPlaced();

        // Mark auction as ended and return NFT to seller
        auction.ended = true;
        IERC721(auction.nft).safeTransferFrom(address(this), auction.seller, auction.nftId);

        // Emit cancellation event
        emit AuctionCancelled(_auctionId);
    }

    /// @notice Retrieves details of an auction
    /// @dev Returns all auction parameters
    /// @param _auctionId The ID of the auction to query
    /// @return seller The seller's address
    /// @return nft The NFT contract address
    /// @return nftId The NFT token ID
    /// @return startingBid The starting bid amount in wei
    /// @return highestBid The current highest bid in wei
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
    /// @dev Returns 0 if the bidder has not placed a bid
    /// @param _auctionId The ID of the auction
    /// @param _bidder The address of the bidder
    /// @return The bid amount in wei
    function getBid(uint256 _auctionId, address _bidder) external view auctionExists(_auctionId) returns (uint256) {
        return auctions[_auctionId].bids[_bidder];
    }
}
