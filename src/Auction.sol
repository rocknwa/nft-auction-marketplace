// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/// @title NFTAuctionMarketplace
/// @notice A decentralized marketplace for creating, bidding on, and finalizing auctions for ERC721 NFTs
/// @dev Inherits from ReentrancyGuard for security and IERC721Receiver to handle NFT transfers
contract NFTAuctionMarketplace is ReentrancyGuard, IERC721Receiver {
    // Custom Errors
    error AuctionDoesNotExist();
    error AuctionHasEnded();
    error AuctionTimeExpired();
    error DurationTooShort();
    error InvalidStartingBid();
    error NotNFTOwner();
    error ContractNotApproved();
    error BidTooLow();
    error SellerCannotBid();
    error RefundFailed();
    error HighestBidderCannotWithdraw();
    error NoBidToWithdraw();
    error AuctionNotStarted();
    error AuctionNotYetEnded();
    error OnlySellerCanCancel();
    error AuctionNotActive();
    error BidsAlreadyPlaced();

    // Events for auction lifecycle
    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed nft,
        uint256 nftId,
        uint256 startingBid,
        uint256 endAt
    );
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 amount);
    event BidWithdrawn(uint256 indexed auctionId, address indexed bidder, uint256 amount);
    event AuctionEnded(uint256 indexed auctionId, address indexed winner, uint256 amount);
    event AuctionCancelled(uint256 indexed auctionId);

    // Auction structure
    struct Auction {
        address payable seller;
        address nft;
        uint256 nftId;
        uint256 startingBid;
        uint256 highestBid;
        address highestBidder;
        uint256 endAt;
        bool started;
        bool ended;
        mapping(address => uint256) bids;
    }

    // State variables
    mapping(uint256 => Auction) public auctions;
    uint256 public auctionCount;

    // Constants
    uint256 public constant MINIMUM_AUCTION_DURATION = 1 hours;
    uint256 public constant EXTEND_DURATION = 15 minutes;

    // Modifiers
    modifier auctionExists(uint256 _auctionId) {
        if (_auctionId >= auctionCount) revert AuctionDoesNotExist();
        _;
    }

    modifier auctionNotEnded(uint256 _auctionId) {
        if (auctions[_auctionId].ended) revert AuctionHasEnded();
        if (block.timestamp >= auctions[_auctionId].endAt) {
            revert AuctionTimeExpired();
        }
        _;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function createAuction(address _nft, uint256 _nftId, uint256 _startingBid, uint256 _duration)
        external
        nonReentrant
    {
        if (_duration < MINIMUM_AUCTION_DURATION) revert DurationTooShort();
        if (_startingBid == 0) revert InvalidStartingBid();

        IERC721 nft = IERC721(_nft);
        if (nft.ownerOf(_nftId) != msg.sender) revert NotNFTOwner();
        if (nft.getApproved(_nftId) != address(this) && !nft.isApprovedForAll(msg.sender, address(this))) {
            revert ContractNotApproved();
        }

        uint256 auctionId = auctionCount++;
        Auction storage auction = auctions[auctionId];
        auction.seller = payable(msg.sender);
        auction.nft = _nft;
        auction.nftId = _nftId;
        auction.startingBid = _startingBid;
        auction.highestBid = _startingBid;
        auction.endAt = block.timestamp + _duration;
        auction.started = true;

        nft.safeTransferFrom(msg.sender, address(this), _nftId);

        emit AuctionCreated(auctionId, msg.sender, _nft, _nftId, _startingBid, auction.endAt);
    }

    function bid(uint256 _auctionId)
        external
        payable
        auctionExists(_auctionId)
        auctionNotEnded(_auctionId)
        nonReentrant
    {
        Auction storage auction = auctions[_auctionId];
        if (msg.value <= auction.highestBid) revert BidTooLow();
        if (msg.sender == auction.seller) revert SellerCannotBid();

        if (auction.highestBidder != address(0)) {
            (bool success,) = auction.highestBidder.call{value: auction.bids[auction.highestBidder]}("");
            if (!success) revert RefundFailed();
        }

        auction.bids[msg.sender] = msg.value;
        auction.highestBid = msg.value;
        auction.highestBidder = msg.sender;

        if (auction.endAt - block.timestamp < EXTEND_DURATION) {
            auction.endAt = block.timestamp + EXTEND_DURATION;
        }

        emit BidPlaced(_auctionId, msg.sender, msg.value);
    }

    function withdrawBid(uint256 _auctionId) external auctionExists(_auctionId) nonReentrant {
        Auction storage auction = auctions[_auctionId];
        if (msg.sender == auction.highestBidder) {
            revert HighestBidderCannotWithdraw();
        }
        uint256 amount = auction.bids[msg.sender];
        if (amount == 0) revert NoBidToWithdraw();

        auction.bids[msg.sender] = 0;
        payable(msg.sender).transfer(amount);

        emit BidWithdrawn(_auctionId, msg.sender, amount);
    }

    function endAuction(uint256 _auctionId) external auctionExists(_auctionId) nonReentrant {
        Auction storage auction = auctions[_auctionId];
        if (!auction.started) revert AuctionNotStarted();
        if (auction.ended) revert AuctionHasEnded();
        if (block.timestamp < auction.endAt) revert AuctionNotYetEnded();

        auction.ended = true;

        if (auction.highestBidder != address(0)) {
            IERC721(auction.nft).safeTransferFrom(address(this), auction.highestBidder, auction.nftId);
            auction.seller.transfer(auction.highestBid);
            emit AuctionEnded(_auctionId, auction.highestBidder, auction.highestBid);
        } else {
            IERC721(auction.nft).safeTransferFrom(address(this), auction.seller, auction.nftId);
            emit AuctionEnded(_auctionId, address(0), 0);
        }
    }

    function cancelAuction(uint256 _auctionId) external auctionExists(_auctionId) nonReentrant {
        Auction storage auction = auctions[_auctionId];
        if (msg.sender != auction.seller) revert OnlySellerCanCancel();
        if (!auction.started || auction.ended) revert AuctionNotActive();
        if (auction.highestBidder != address(0)) revert BidsAlreadyPlaced();

        auction.ended = true;
        IERC721(auction.nft).safeTransferFrom(address(this), auction.seller, auction.nftId);

        emit AuctionCancelled(_auctionId);
    }

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

    function getBid(uint256 _auctionId, address _bidder) external view auctionExists(_auctionId) returns (uint256) {
        return auctions[_auctionId].bids[_bidder];
    }
}
