// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Lookmans} from "../../src/Erc20/LookmansToken.sol";
import {Service_marketplace} from "../../src/service_marketplace.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/service_marketplace.sol";

contract setups is Test {
    Service_marketplace public market;
    Lookmans public payToken;
    address payable buyer = payable(makeAddr("buyer"));
    address payable admin = payable(makeAddr("admin"));
    address payable seller = payable(makeAddr("seller"));
    uint256 _platformFee = 3e16;
    uint buyerFunds = 10000e18;

    //@notice Events for the contract

    event ItemListed(
        address indexed owner,
        uint256 serviceId,
        uint256 startingTime
    );

    /**
     * ERRORS
     */
    error Invalid_Order(uint orderId);
    error Insufficient_Funds(uint requiredValue);
    error YouAreNotBuyer();
    error YouAreNotSeller();
    error YouAreNotBuyerOrSeller();
    error OrderAlreadyCompletedorCancelled(uint OrderId);
    error FailedToCompleteOrder(uint orderId);
    error YouDonotOwnThisService();
    error AlreadyListed(uint _service);
    error NotListed(uint _service);
    error ZeroAddress(address zero);
    error YouCannotCancelTheOrderAtThisStage(uint32 status);
    error Invalid_Service(uint serviceId);
    error YouCannotReceiveTheOrderNow(uint orderId);
    error YouCannotDispute(uint32 status);

    //EVENTS
    event ItemUpdated(address indexed owner, uint256 serviceId);

    event ListingCanceled(uint256 serviceId, address indexed seller);

    event service_created(uint256 serviceId, address seller);
    event orderCreatedBySeller(uint256 orderId, address Buyer);
    event orderImplementedByBuyer(
        uint256 orderId,
        address buyer,
        uint256 allowedTime
    );
    event orderCancelled(uint256 indexed orderId);
    event orderCompleted(uint256 indexed orderId);
    event orderReceivedBySeller(uint orderId);
    event BuyerDisputed(uint indexed order);
    event refundedBuyer(uint indexed orderId);
    event orderReceived(uint orderId);
    event UpdatePlatformFee(uint16 platformFee);
    event UpdatePlatformFeeRecipient(address payable platformFeeRecipient);

    function setUp() public {
        Lookmans lookman_implementation = new Lookmans();
        ERC1967Proxy lookman_proxy = new ERC1967Proxy(
            address(lookman_implementation),
            ""
        );
        payToken = Lookmans(address(lookman_proxy));

        Service_marketplace market_implementation = new Service_marketplace();
        ERC1967Proxy market_proxy = new ERC1967Proxy(
            address(market_implementation),
            ""
        );
        market = Service_marketplace(address(market_proxy));
        vm.startPrank(admin);
        market.initialize(admin, _platformFee, address(payToken));
        payToken.initialize(admin, admin, admin);
    }

    //Lets create our service
    function create_service() public returns (uint) {
        vm.startPrank(seller);
        market.createService();
        return block.timestamp + 1 days;
    }

    // Lets list our service
    function list_service(uint256 service, uint startTime) public {
        market.listService(service, startTime);
    }

    //Cancel listing tests
    function cancel_listing(address executor, uint service) public {
        uint startTime = block.timestamp + 2 days;
        uint realListing = 1;
        vm.startPrank(executor);
        market.cancelListing(service);
    }

    // Create service tests
    function createOrderTestSetup() public {
        uint buyer_tokens = 500_000e18;
        uint ourService = 1;
        uint startTime = block.timestamp + 2 days;
        create_service();
        vm.startPrank(seller);
        list_service(ourService, startTime);
        vm.startPrank(admin);
        payToken.mint(buyer, buyer_tokens);
    }

    //Complete order creation tests
    function CompleteOrderCreationSetUp() public {
        uint price = 500_000e18;
        uint our_service = 1;
        createOrderTestSetup();
        vm.startPrank(seller);
        market.addOrderPrice(our_service, price, buyer);
        vm.stopPrank();
        vm.startPrank(buyer);
        payToken.approve(address(market), 1_000_000e18);
        vm.stopPrank();
    }

    function completeOrderSetUp() public {
        uint our_order = 1;
        uint price = 500_000e18;
        uint allowed_days = 10;
        CompleteOrderCreationSetUp();
        vm.startPrank(buyer);
        market.completeOrderCreation(our_order, allowed_days, price);
        vm.stopPrank();
    }

    function receiveOrderSetUp() public {
        uint our_order = 1;
        completeOrderSetUp();
        vm.startPrank(seller);
        market.completeOrder(our_order);
        vm.stopPrank();
    }

    function hasTimeElapsedBuyerTest() public {
        uint our_order = 1;
        completeOrderSetUp();
        uint time = 10 days + 1 days;
        vm.warp(time + 1);
    }

    function hasTimeElapsedSellerTest() public {
        uint our_order = 1;
        receiveOrderSetUp();
        uint time = 10 days + 1 days;
        vm.warp(time + 1);
    }
}
