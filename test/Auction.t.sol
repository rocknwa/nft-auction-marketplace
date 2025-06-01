// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {NFTAuctionMarketplace} from "../src/Auction.sol";
import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

// Mock ERC721 contract for testing
contract MockNFT is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

/// @title NFTAuctionMarketplaceTest
/// @notice Test suite for the NFTAuctionMarketplace contract
/// @dev Uses Forge's Test framework to simulate and test auction functionalities
contract NFTAuctionMarketplaceTest is Test {
    // State variables
    NFTAuctionMarketplace auctionMarketplace;
    MockNFT mockNFT;

    // Test addresses
    address seller = address(0x1);
    address bidder1 = address(0x2);
    address bidder2 = address(0x3);
    address bidder3 = address(0x4);
    uint256 nftId = 1;
    uint256 startingBid = 1 ether;
    uint256 auctionDuration = 2 hours;

    // Event declarations for testing
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

    function setUp() public {
        auctionMarketplace = new NFTAuctionMarketplace();
        mockNFT = new MockNFT();

        seller = address(0x1234);
        vm.deal(seller, 10 ether);

        vm.prank(seller);
        mockNFT.mint(seller, nftId);

        vm.deal(bidder1, 10 ether);
        vm.deal(bidder2, 10 ether);
        vm.deal(bidder3, 10 ether);
    }

    function testCreateAuction() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        uint256 expectedEndAt = block.timestamp + auctionDuration;

        vm.expectEmit(true, true, true, false);
        emit AuctionCreated(0, seller, address(mockNFT), nftId, startingBid, expectedEndAt);

        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);

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

    function test_RevertCreateAuctionNotOwner() public {
        vm.prank(bidder1);
        vm.expectRevert(NFTAuctionMarketplace.NotNFTOwner.selector);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
    }

    function test_RevertCreateAuctionShortDuration() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        vm.expectRevert(NFTAuctionMarketplace.DurationTooShort.selector);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, 30 minutes);
        vm.stopPrank();
    }

    function test_RevertCreateAuctionZeroStartingBid() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        vm.expectRevert(NFTAuctionMarketplace.InvalidStartingBid.selector);
        auctionMarketplace.createAuction(address(mockNFT), nftId, 0, auctionDuration);
        vm.stopPrank();
    }

    function test_RevertCreateAuctionNotApproved() public {
        vm.startPrank(seller);
        vm.expectRevert(NFTAuctionMarketplace.ContractNotApproved.selector);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();
    }

    function testPlaceBid() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();

        vm.startPrank(bidder1);
        vm.expectEmit(true, true, false, true);
        emit BidPlaced(0, bidder1, 2 ether);
        auctionMarketplace.bid{value: 2 ether}(0);
        vm.stopPrank();

        assertEq(auctionMarketplace.getBid(0, bidder1), 2 ether, "Incorrect bid amount");
        (,,,, uint256 highestBid, address highestBidder,,,) = auctionMarketplace.getAuction(0);
        assertEq(highestBid, 2 ether, "Incorrect highest bid");
        assertEq(highestBidder, bidder1, "Incorrect highest bidder");
    }

    function test_RevertBidTooLow() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();

        vm.prank(bidder1);
        vm.expectRevert(NFTAuctionMarketplace.BidTooLow.selector);
        auctionMarketplace.bid{value: 0.5 ether}(0);
    }

    function test_RevertSellerCannotBid() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();

        vm.prank(seller);
        vm.expectRevert(NFTAuctionMarketplace.SellerCannotBid.selector);
        auctionMarketplace.bid{value: 2 ether}(0);
    }

    function testBidExtension() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        uint256 startTime = block.timestamp;
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();

        uint256 warpTime = startTime + auctionDuration - 10 minutes;
        vm.warp(warpTime);

        vm.prank(bidder1);
        auctionMarketplace.bid{value: 2 ether}(0);

        (,,,,,, uint256 endAt,,) = auctionMarketplace.getAuction(0);
        assertEq(endAt, warpTime + 15 minutes, "Auction not extended correctly");
    }

    function test_RevertBidAfterEnd() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        uint256 startTime = block.timestamp;
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();

        vm.warp(startTime + auctionDuration);
        vm.prank(bidder1);
        vm.expectRevert(NFTAuctionMarketplace.AuctionTimeExpired.selector);
        auctionMarketplace.bid{value: 2 ether}(0);
    }

    function testWithdrawBid() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();

        vm.prank(bidder1);
        auctionMarketplace.bid{value: 2 ether}(0);
        vm.prank(bidder2);
        auctionMarketplace.bid{value: 3 ether}(0);

        uint256 before = bidder1.balance;
        vm.prank(bidder1);
        vm.expectEmit(true, true, false, true);
        emit BidWithdrawn(0, bidder1, 2 ether);
        auctionMarketplace.withdrawBid(0);

        assertEq(auctionMarketplace.getBid(0, bidder1), 0, "Bid not withdrawn");
        assertEq(bidder1.balance, before + 2 ether, "Bidder not refunded");
    }

    function test_RevertWithdrawNoBid() public {
        vm.prank(bidder1);
        vm.expectRevert(NFTAuctionMarketplace.AuctionDoesNotExist.selector);
        auctionMarketplace.withdrawBid(0);
    }

    function test_RevertWithdrawHighestBidder() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();

        vm.prank(bidder1);
        auctionMarketplace.bid{value: 2 ether}(0);
        vm.prank(bidder1);
        vm.expectRevert(NFTAuctionMarketplace.HighestBidderCannotWithdraw.selector);
        auctionMarketplace.withdrawBid(0);
    }

    function testEndAuctionWithWinner() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();

        vm.prank(bidder1);
        auctionMarketplace.bid{value: 2 ether}(0);

        vm.warp(block.timestamp + auctionDuration + 1);
        uint256 bal = seller.balance;
        vm.expectEmit(true, true, false, true);
        emit AuctionEnded(0, bidder1, 2 ether);
        auctionMarketplace.endAuction(0);

        assertEq(mockNFT.ownerOf(nftId), bidder1, "NFT not transferred to winner");
        assertEq(seller.balance, bal + 2 ether, "Seller not paid");
        (,,,,,,,, bool ended) = auctionMarketplace.getAuction(0);
        assertTrue(ended, "Auction not marked as ended");
    }

    function test_RevertEndAuctionBeforeTime() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();

        vm.expectRevert(NFTAuctionMarketplace.AuctionNotYetEnded.selector);
        auctionMarketplace.endAuction(0);
    }

    function test_RevertEndAuctionAlreadyEnded() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();

        vm.warp(block.timestamp + auctionDuration + 1);
        auctionMarketplace.endAuction(0);
        vm.expectRevert(NFTAuctionMarketplace.AuctionHasEnded.selector);
        auctionMarketplace.endAuction(0);
    }

    function testEndAuctionNoBids() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();

        vm.warp(block.timestamp + auctionDuration + 1);
        vm.expectEmit(true, true, false, true);
        emit AuctionEnded(0, address(0), 0);
        auctionMarketplace.endAuction(0);
        assertEq(mockNFT.ownerOf(nftId), seller, "NFT not returned to seller");
    }

    function testCancelAuctionNoBids() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);

        vm.expectEmit(true, false, false, true);
        emit AuctionCancelled(0);
        auctionMarketplace.cancelAuction(0);
        assertEq(mockNFT.ownerOf(nftId), seller, "NFT not returned to seller");
        (,,,,,,,, bool ended) = auctionMarketplace.getAuction(0);
        assertTrue(ended, "Auction not marked as ended");
        vm.stopPrank();
    }

    function test_RevertCancelAuctionWithBids() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();

        vm.prank(bidder1);
        auctionMarketplace.bid{value: 2 ether}(0);

        vm.prank(seller);
        vm.expectRevert(NFTAuctionMarketplace.BidsAlreadyPlaced.selector);
        auctionMarketplace.cancelAuction(0);
    }

    function test_RevertCancelNotSeller() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();

        vm.prank(bidder1);
        vm.expectRevert(NFTAuctionMarketplace.OnlySellerCanCancel.selector);
        auctionMarketplace.cancelAuction(0);
    }

    function test_RevertGetAuctionDoesNotExist() public {
        vm.expectRevert(NFTAuctionMarketplace.AuctionDoesNotExist.selector);
        auctionMarketplace.getAuction(5);
    }

    function test_RevertGetBidDoesNotExist() public {
        vm.expectRevert(NFTAuctionMarketplace.AuctionDoesNotExist.selector);
        auctionMarketplace.getBid(5, bidder1);
    }

    function test_RevertReentrancyBid() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();

        MaliciousBidder mal = new MaliciousBidder(auctionMarketplace, 0);
        vm.deal(address(mal), 10 ether);

        vm.prank(address(mal));
        auctionMarketplace.bid{value: 2 ether}(0);

        vm.prank(bidder1);
        vm.expectRevert(NFTAuctionMarketplace.RefundFailed.selector);
        auctionMarketplace.bid{value: 3 ether}(0);
    }

    /// @notice Tests that cancelling an already ended auction is rejected
    /// @dev Expects a revert when attempting to cancel an ended auction
    function test_RevertCancelAuctionAlreadyEnded() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();

        vm.warp(block.timestamp + auctionDuration + 1);
        auctionMarketplace.endAuction(0); // End auction

        vm.prank(seller);
        vm.expectRevert(NFTAuctionMarketplace.AuctionNotActive.selector);
        auctionMarketplace.cancelAuction(0); // Attempt to cancel
    }

    /// @notice Tests that bidding with exact highest bid is rejected
    /// @dev Expects a revert when bid equals the current highest bid
    function test_RevertBidEqualHighest() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();

        vm.prank(bidder1);
        auctionMarketplace.bid{value: 2 ether}(0); // Place initial bid

        vm.prank(bidder2);
        vm.expectRevert(NFTAuctionMarketplace.BidTooLow.selector);
        auctionMarketplace.bid{value: 2 ether}(0); // Attempt to bid same amount
    }

    /// @notice Tests multiple bidders with refunds
    /// @dev Verifies correct refund amounts and final auction state
    function testMultipleBiddersWithRefunds() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();

        // Place multiple bids
        uint256 bidder1BalanceBefore = bidder1.balance;
        uint256 bidder2BalanceBefore = bidder2.balance;
        uint256 bidder3BalanceBefore = bidder3.balance;

        vm.prank(bidder1);
        auctionMarketplace.bid{value: 2 ether}(0); // Bidder1 bids 2 ETH
        vm.prank(bidder2);
        auctionMarketplace.bid{value: 3 ether}(0); // Bidder2 outbids with 3 ETH
        vm.prank(bidder3);
        auctionMarketplace.bid{value: 4 ether}(0); // Bidder3 outbids with 4 ETH

        // Verify refunds
        assertEq(bidder1.balance, bidder1BalanceBefore - 2 ether + 2 ether, "Bidder1 not refunded correctly");
        assertEq(bidder2.balance, bidder2BalanceBefore - 3 ether + 3 ether, "Bidder2 not refunded correctly");

        // Verify auction state
        (,,,, uint256 highestBid, address highestBidder,,,) = auctionMarketplace.getAuction(0);
        assertEq(highestBid, 4 ether, "Incorrect highest bid");
        assertEq(highestBidder, bidder3, "Incorrect highest bidder");
        assertEq(auctionMarketplace.getBid(0, bidder3), 4 ether, "Incorrect bid amount for bidder3");

        // End auction and verify final state
        vm.warp(block.timestamp + auctionDuration + 1);
        uint256 sellerBalanceBefore = seller.balance;
        vm.expectEmit(true, true, false, true);
        emit AuctionEnded(0, bidder3, 4 ether);
        auctionMarketplace.endAuction(0);

        assertEq(mockNFT.ownerOf(nftId), bidder3, "NFT not transferred to winner");
        assertEq(seller.balance, sellerBalanceBefore + 4 ether, "Seller not paid");
        assertEq(bidder3.balance, bidder3BalanceBefore - 4 ether, "Bidder3 balance incorrect after win");
    }

    /// @notice Tests querying bid for a non-bidder
    /// @dev Verifies that getBid returns 0 for an address that hasn't bid
    function testGetBidNonBidder() public {
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, auctionDuration);
        vm.stopPrank();

        vm.prank(bidder1);
        auctionMarketplace.bid{value: 2 ether}(0); // Bidder1 places bid

        uint256 bid = auctionMarketplace.getBid(0, bidder2); // Bidder2 never bid
        assertEq(bid, 0, "Non-bidder should have zero bid amount");
    }

    /// @notice Tests auction creation with maximum duration
    /// @dev Verifies that an auction can be created with a large but valid duration
    function testCreateAuctionMaxDuration() public {
        uint256 maxDuration = 365 days; // Maximum reasonable duration (1 year)
        vm.startPrank(seller);
        mockNFT.approve(address(auctionMarketplace), nftId);
        uint256 expectedEndAt = block.timestamp + maxDuration;

        vm.expectEmit(true, true, true, false);
        emit AuctionCreated(0, seller, address(mockNFT), nftId, startingBid, expectedEndAt);

        auctionMarketplace.createAuction(address(mockNFT), nftId, startingBid, maxDuration);

        (,,,,,, uint256 endAt,,) = auctionMarketplace.getAuction(0);
        assertEq(endAt, expectedEndAt, "Incorrect end time for max duration auction");
        vm.stopPrank();
    }
}

/// @title MaliciousBidder
/// @notice Contract to simulate a reentrancy attack on the auction marketplace
/// @dev Attempts to reenter the bid function during ETH transfer
contract MaliciousBidder {
    NFTAuctionMarketplace auctionMarketplace;
    uint256 auctionId;

    constructor(NFTAuctionMarketplace _auctionMarketplace, uint256 _auctionId) {
        auctionMarketplace = _auctionMarketplace;
        auctionId = _auctionId;
    }

    receive() external payable {
        auctionMarketplace.bid{value: msg.value}(auctionId);
    }

    function attack() external payable {
        auctionMarketplace.bid{value: msg.value}(auctionId);
    }
}
