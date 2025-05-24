// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "forge-std/Test.sol";
import {NFTAuctionMarketplace} from "../src/Auction.sol";
import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

// Mock ERC721 contract for testing
contract MockNFT is ERC721 {
    /// @notice Constructor to initialize the MockNFT contract
    /// @dev Inherits from OpenZeppelin's ERC721 contract with name "MockNFT" and symbol "MNFT"
    constructor() ERC721("MockNFT", "MNFT") {}

    /// @notice Mints a new NFT to the specified address with the given token ID
    /// @param to The address to receive the minted NFT
    /// @param tokenId The unique ID of the NFT to mint
    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

/// @title NFTAuctionMarketplaceTest
/// @notice Test suite for the NFTAuctionMarketplace contract
/// @dev Uses Forge's Test framework to simulate and test auction functionalities
contract NFTAuctionMarketplaceTest is Test {
    // State variables
    NFTAuctionMarketplace auctionMarketplace; // Instance of the auction marketplace contract
    MockNFT mockNFT; // Instance of the mock NFT contract

    // Test addresses
    address seller = address(0x1); // Seller address for testing
    address bidder1 = address(0x2); // First bidder address
    address bidder2 = address(0x3); // Second bidder address
    uint256 nftId = 1; // NFT token ID used in tests
    uint256 startingBid = 1 ether; // Starting bid amount for auctions
    uint256 auctionDuration = 2 hours; // Default auction duration

    // Event declarations for testing
    /// @notice Emitted when a new auction is created
    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed nft,
        uint256 nftId,
        uint256 startingBid,
        uint256 endAt
    );
    /// @notice Emitted when a bid is placed on an auction
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 amount);
    /// @notice Emitted when a bid is withdrawn from an auction
    event BidWithdrawn(uint256 indexed auctionMode, address indexed bidder, uint256 amount);
    /// @notice Emitted when an auction ends with a winner and final bid amount
    event AuctionEnded(uint256 indexed auctionId, address indexed winner, uint256 amount);
    /// @notice Emitted when an auction is cancelled
    event AuctionCancelled(uint256 indexed auctionId);

    /// @notice Sets up the test environment before each test
    /// @dev Deploys contracts, mints an NFT, and funds test accounts
    function setUp() public {
        auctionMarketplace = new NFTAuctionMarketplace(); // Deploy the auction marketplace
        mockNFT = new MockNFT(); // Deploy the mock NFT contract

        seller = address(0x1234); // Update seller address
        vm.deal(seller, 10 ether); // Fund seller with 10 ETH

        vm.prank(seller); // Impersonate seller
        mockNFT.mint(seller, nftId); // Mint NFT to seller

        vm.deal(bidder1, 10 ether); // Fund bidder1 with 10 ETH
        vm.deal(bidder2, 10 ether); // Fund bidder2 with 10 ETH
    }

    /// @notice Tests successful creation of an auction
    /// @dev Verifies auction parameters, events, and NFT ownership transfer
    function testCreateAuction() public {
        vm.startPrank(seller); // Impersonate seller
        mockNFT.approve(address(auctionMarketplace), nftId); // Approve marketplace to transfer NFT
        uint256 expectedEndAt = block.timestamp + auctionDuration; // Calculate expected auction end time

        vm.expectEmit(true, true, true, false); // Expect AuctionCreated event
        emit AuctionCreated(0, seller, address(mockNFT), nftId, startingBid, expectedEndAt);

        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration); // Create auction

        // Retrieve auction details
        (
            address auctionSeller,
            address nft,
            uint256 auctionNftId,
            uint256 auctionStartingBid,
            uint256 highestBid,
            address highestBidder,
            uint256 endAt,
            bool started,
            bool ended
        ) = auctionMarketplace.getAuction(0);

        // Assert auction details
        assertEq(auctionSeller, seller, "Incorrect seller address");
        assertEq(nft, address(mockNFT), "Incorrect NFT address");
        assertEq(auctionNftId, nftId, "Incorrect NFT ID");
        assertEq(auctionStartingBid, startingBid, "Incorrect starting bid");
        assertEq(highestBid, startingBid, "Incorrect highest bid");
        assertEq(highestBidder, address(0), "Incorrect highest bidder");
        assertEq(endAt, expectedEndAt, "Incorrect end time");
        assertTrue(started, "Auction not started");
        assertFalse(ended, "Auction incorrectly marked as ended");
        assertEq(mockNFT.ownerOf(nftId), address(auctionMarketplace), "NFT not transferred to marketplace");
        vm.stopPrank();
    }

    /// @notice Tests that only the NFT owner can create an auction
    /// @dev Expects a revert when a non-owner tries to create an auction
    function test_RevertCreateAuctionNotOwner() public {
        vm.prank(bidder1); // Impersonate bidder1 (not the NFT owner)
        vm.expectRevert("Not NFT owner"); // Expect revert
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
    }

    /// @notice Tests that auctions with too short duration are rejected
    /// @dev Expects a revert for durations less than the minimum
    function test_RevertCreateAuctionShortDuration() public {
        vm.startPrank(seller); // Impersonate seller
        mockNFT.approve(address(auctionMarketplace), nftId); // Approve marketplace
        vm.expectRevert("Duration too short"); // Expect revert
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, 30 minutes);
        vm.stopPrank();
    }

    /// @notice Tests that auctions with zero starting bid are rejected
    /// @dev Expects a revert for zero starting bid
    function test_RevertCreateAuctionZeroStartingBid() public {
        vm.startPrank(seller); // Impersonate seller
        mockNFT.approve(address(auctionMarketplace), nftId); // Approve marketplace
        vm.expectRevert("Starting bid must be greater than 0"); // Expect revert
        auctionMarketplace.createAuction(address(mockNFT), nftId, 0, auctionDuration);
        vm.stopPrank();
    }

    /// @notice Tests that auctions require NFT approval
    /// @dev Expects a revert if the marketplace is not approved to transfer the NFT
    function test_RevertCreateAuctionNotApproved() public {
        vm.startPrank(seller); // Impersonate seller
        // No approval given
        vm.expectRevert(); // Expect revert due to lack of approval
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();
    }

    /// @notice Tests successful bid placement
    /// @dev Verifies bid amount, highest bidder, and event emission
    function testPlaceBid() public {
        vm.startPrank(seller); // Impersonate seller
        mockNFT.approve(address(auctionMarketplace), nftId); // Approve marketplace
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration); // Create auction
        vm.stopPrank();

        vm.startPrank(bidder1); // Impersonate bidder1
        vm.expectEmit(true, true, false, true); // Expect BidPlaced event
        emit BidPlaced(0, bidder1, 2 ether);
        auctionMarketplace.bid{value: 2 ether}(0); // Place bid
        vm.stopPrank();

        assertEq(auctionMarketplace.getBid(0, bidder1), 2 ether, "Incorrect bid amount");
        (,,,, uint256 highestBid, address highestBidder,,,) = auctionMarketplace.getAuction(0);
        assertEq(highestBid, 2 ether, "Incorrect highest bid");
        assertEq(highestBidder, bidder1, "Incorrect highest bidder");
    }

    /// @notice Tests that bids below the starting bid or highest bid are rejected
    /// @dev Expects a revert for low bid amount
    function test_RevertBidTooLow() public {
        vm.startPrank(seller); // Impersonate seller
        mockNFT.approve(address(auctionMarketplace), nftId); // Approve marketplace
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration); // Create auction
        vm.stopPrank();

        vm.prank(bidder1); // Impersonate bidder1
        vm.expectRevert("Bid too low"); // Expect revert
        auctionMarketplace.bid{value: 0.5 ether}(0); // Attempt low bid
    }

    /// @notice Tests that the seller cannot bid on their own auction
    /// @dev Expects a revert when the seller attempts to bid
    function test_RevertSellerCannotBid() public {
        vm.startPrank(seller); // Impersonate seller
        mockNFT.approve(address(auctionMarketplace), nftId); // Approve marketplace
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration); // Create auction
        vm.stopPrank();

        vm.prank(seller); // Impersonate seller
        vm.expectRevert("Seller cannot bid"); // Expect revert
        auctionMarketplace.bid{value: 2 ether}(0); // Attempt to bid
    }

    /// @notice Tests auction end time extension when bidding near the end
    /// @dev Verifies that a bid within the last 10 minutes extends the auction by 15 minutes
    function testBidExtension() public {
        vm.startPrank(seller); // Impersonate seller
        mockNFT.approve(address(auctionMarketplace), nftId); // Approve marketplace
        uint256 startTime = block.timestamp; // Record start time
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration); // Create auction
        vm.stopPrank();

        uint256 warpTime = startTime + auctionDuration - 10 minutes; // Move to near auction end
        vm.warp(warpTime);

        vm.prank(bidder1); // Impersonate bidder1
        auctionMarketplace.bid{value: 2 ether}(0); // Place bid

        (,,,,,, uint256 endAt,,) = auctionMarketplace.getAuction(0);
        assertEq(endAt, warpTime + 15 minutes, "Auction not extended correctly");
    }

    /// @notice Tests that bidding after the auction end is rejected
    /// @dev Expects a revert when attempting to bid after the auction expires
    function test_RevertBidAfterEnd() public {
        vm.startPrank(seller); // Impersonate seller
        mockNFT.approve(address(auctionMarketplace), nftId); // Approve marketplace
        uint256 startTime = block.timestamp; // Record start time
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration); // Create auction
        vm.stopPrank();

        vm.warp(startTime + auctionDuration); // Move past auction end
        vm.prank(bidder1); // Impersonate bidder1
        vm.expectRevert("Auction time expired"); // Expect revert
        auctionMarketplace.bid{value: 2 ether}(0); // Attempt to bid
    }

    /// @notice Tests successful withdrawal of a non-highest bid
    /// @dev Verifies bid removal, refund, and event emission
    function testWithdrawBid() public {
        vm.startPrank(seller); // Impersonate seller
        mockNFT.approve(address(auctionMarketplace), nftId); // Approve marketplace
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration); // Create auction
        vm.stopPrank();

        vm.prank(bidder1); // Impersonate bidder1
        auctionMarketplace.bid{value: 2 ether}(0); // Place bid
        vm.prank(bidder2); // Impersonate bidder2
        auctionMarketplace.bid{value: 3 ether}(0); // Place higher bid

        uint256 before = bidder1.balance; // Record bidder1 balance
        vm.prank(bidder1); // Impersonate bidder1
        vm.expectEmit(true, true, false, true); // Expect BidWithdrawn event
        emit BidWithdrawn(0, bidder1, 2 ether);
        auctionMarketplace.withdrawBid(0); // Withdraw bid

        assertEq(auctionMarketplace.getBid(0, bidder1), 0, "Bid not withdrawn");
        assertEq(bidder1.balance, before + 2 ether, "Bidder not refunded");
    }

    /// @notice Tests that withdrawing a bid from a non-existent auction is rejected
    /// @dev Expects a revert for invalid auction ID
    function test_RevertWithdrawNoBid() public {
        vm.prank(bidder1); // Impersonate bidder1
        vm.expectRevert("Auction does not exist"); // Expect revert
        auctionMarketplace.withdrawBid(0); // Attempt to withdraw from non-existent auction
    }

    /// @notice Tests that the highest bidder cannot withdraw their bid
    /// @dev Expects a revert when the highest bidder attempts to withdraw
    function test_RevertWithdrawHighestBidder() public {
        vm.startPrank(seller); // Impersonate seller
        mockNFT.approve(address(auctionMarketplace), nftId); // Approve marketplace
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration); // Create auction
        vm.stopPrank();

        vm.prank(bidder1); // Impersonate bidder1
        auctionMarketplace.bid{value: 2 ether}(0); // Place bid
        vm.prank(bidder1); // Impersonate bidder1
        vm.expectRevert("Highest bidder cannot withdraw"); // Expect revert
        auctionMarketplace.withdrawBid(0); // Attempt to withdraw
    }

    /// @notice Tests ending an auction with a winner
    /// @dev Verifies NFT transfer, seller payment, and event emission
    function testEndAuctionWithWinner() public {
        vm.startPrank(seller); // Impersonate seller
        mockNFT.approve(address(auctionMarketplace), nftId); // Approve marketplace
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration); // Create auction
        vm.stopPrank();

        vm.prank(bidder1); // Impersonate bidder1
        auctionMarketplace.bid{value: 2 ether}(0); // Place bid

        vm.warp(block.timestamp + auctionDuration + 1); // Move past auction end
        uint256 bal = seller.balance; // Record seller balance
        vm.expectEmit(true, true, false, true); // Expect AuctionEnded event
        emit AuctionEnded(0, bidder1, 2 ether);
        auctionMarketplace.endAuction(0); // End auction

        assertEq(mockNFT.ownerOf(nftId), bidder1, "NFT not transferred to winner");
        assertEq(seller.balance, bal + 2 ether, "Seller not paid");
        (,,,,,,,, bool ended) = auctionMarketplace.getAuction(0);
        assertTrue(ended, "Auction not marked as ended");
    }

    /// @notice Tests that ending an auction before its time is rejected
    /// @dev Expects a revert if the auction is not yet ended
    function test_RevertEndAuctionBeforeTime() public {
        vm.startPrank(seller); // Impersonate seller
        mockNFT.approve(address(auctionMarketplace), nftId); // Approve marketplace
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration); // Create auction
        vm.stopPrank();

        vm.expectRevert("Auction not yet ended"); // Expect revert
        auctionMarketplace.endAuction(0); // Attempt to end early
    }

    /// @notice Tests that ending an already ended auction is rejected
    /// @dev Expects a revert for a repeated end attempt
    function test_RevertEndAuctionAlreadyEnded() public {
        vm.startPrank(seller); // Impersonate seller
        mockNFT.approve(address(auctionMarketplace), nftId); // Approve marketplace
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration); // Create auction
        vm.stopPrank();

        vm.warp(block.timestamp + auctionDuration + 1); // Move past auction end
        auctionMarketplace.endAuction(0); // End auction
        vm.expectRevert("Auction already ended"); // Expect revert
        auctionMarketplace.endAuction(0); // Attempt to end again
    }

    /// @notice Tests ending an auction with no bids
    /// @dev Verifies NFT return to seller and event emission
    function testEndAuctionNoBids() public {
        vm.startPrank(seller); // Impersonate seller
        mockNFT.approve(address(auctionMarketplace), nftId); // Approve marketplace
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration); // Create auction
        vm.stopPrank();

        vm.warp(block.timestamp + auctionDuration + 1); // Move past auction end
        vm.expectEmit(true, true, false, true); // Expect AuctionEnded event
        emit AuctionEnded(0, address(0), 0);
        auctionMarketplace.endAuction(0); // End auction
        assertEq(mockNFT.ownerOf(nftId), seller, "NFT not returned to seller");
    }

    /// @notice Tests cancelling an auction with no bids
    /// @dev Verifies NFT return to seller, event emission, and auction state
    function testCancelAuctionNoBids() public {
        vm.startPrank(seller); // Impersonate seller
        mockNFT.approve(address(auctionMarketplace), nftId); // Approve marketplace
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration); // Create auction

        vm.expectEmit(true, false, false, true); // Expect AuctionCancelled event
        emit AuctionCancelled(0);
        auctionMarketplace.cancelAuction(0); // Cancel auction
        assertEq(mockNFT.ownerOf(nftId), seller, "NFT not returned to seller");
        (,,,,,,,, bool ended) = auctionMarketplace.getAuction(0);
        assertTrue(ended, "Auction not marked as ended");
        vm.stopPrank();
    }

    /// @notice Tests that cancelling an auction with bids is rejected
    /// @dev Expects a revert if bids have been placed
    function test_RevertCancelAuctionWithBids() public {
        vm.startPrank(seller); // Impersonate seller
        mockNFT.approve(address(auctionMarketplace), nftId); // Approve marketplace
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration); // Create auction
        vm.stopPrank();

        vm.prank(bidder1); // Impersonate bidder1
        auctionMarketplace.bid{value: 2 ether}(0); // Place bid

        vm.prank(seller); // Impersonate seller
        vm.expectRevert("Bids already placed"); // Expect revert
        auctionMarketplace.cancelAuction(0); // Attempt to cancel
    }

    /// @notice Tests that only the seller can cancel an auction
    /// @dev Expects a revert if a non-seller attempts to cancel
    function test_RevertCancelNotSeller() public {
        vm.startPrank(seller); // Impersonate seller
        mockNFT.approve(address(auctionMarketplace), nftId); // Approve marketplace
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration); // Create auction
        vm.stopPrank();

        vm.prank(bidder1); // Impersonate bidder1
        vm.expectRevert("Only seller can cancel"); // Expect revert
        auctionMarketplace.cancelAuction(0); // Attempt to cancel
    }

    /// @notice Tests that querying a non-existent auction reverts
    /// @dev Expects a revert for an invalid auction ID
    function test_RevertGetAuctionDoesNotExist() public {
        vm.expectRevert("Auction does not exist"); // Expect revert
        auctionMarketplace.getAuction(5); // Attempt to query non-existent auction
    }

    /// @notice Tests that querying a bid for a non-existent auction reverts
    /// @dev Expects a revert for an invalid auction ID
    function test_RevertGetBidDoesNotExist() public {
        vm.expectRevert("Auction does not exist"); // Expect revert
        auctionMarketplace.getBid(5, bidder1); // Attempt to query bid for non-existent auction
    }

    /// @notice Tests reentrancy protection in bid function
    /// @dev Simulates a reentrancy attack and expects a revert
    function test_RevertReentrancyBid() public {
        vm.startPrank(seller); // Impersonate seller
        mockNFT.approve(address(auctionMarketplace), nftId); // Approve marketplace
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration); // Create auction
        vm.stopPrank();

        MaliciousBidder mal = new MaliciousBidder(auctionMarketplace, 0); // Deploy malicious bidder
        vm.deal(address(mal), 10 ether); // Fund malicious bidder

        vm.prank(address(mal)); // Impersonate malicious bidder
        auctionMarketplace.bid{value: 2 ether}(0); // Place bid

        vm.prank(bidder1); // Impersonate bidder1
        vm.expectRevert("Refund failed"); // Expect revert due to reentrancy protection
        auctionMarketplace.bid{value: 3 ether}(0); // Attempt to bid
    }
}

/// @title MaliciousBidder
/// @notice Contract to simulate a reentrancy attack on the auction marketplace
/// @dev Attempts to reenter the bid function during ETH transfer
contract MaliciousBidder {
    NFTAuctionMarketplace auctionMarketplace; // Target auction marketplace
    uint256 auctionId; // Auction ID to target

    /// @notice Constructor to initialize the malicious bidder
    /// @param _auctionMarketplace The auction marketplace contract to attack
    /// @param _auctionId The ID of the auction to target
    constructor(NFTAuctionMarketplace _auctionMarketplace, uint256 _auctionId) {
        auctionMarketplace = _auctionMarketplace;
        auctionId = _auctionId;
    }

    /// @notice Receive function to attempt reentrancy
    /// @dev Calls bid function when receiving ETH to trigger reentrancy
    receive() external payable {
        auctionMarketplace.bid{value: msg.value}(auctionId);
    }

    /// @notice Function to initiate the attack
    /// @dev Calls bid function with provided value
    function attack() external payable {
        auctionMarketplace.bid{value: msg.value}(auctionId);
    }
}