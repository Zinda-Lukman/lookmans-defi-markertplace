//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Lookmans} from "../../src/Erc20/LookmansToken.sol";
import {Service_marketplace} from "../../src/service_marketplace.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/service_marketplace.sol";
import {setups} from "./Tests_setups.sol";

contract TestService_marketplace is setups {
    function test_initialize() public {
        address fee_address = market.feeReceipient();
        uint main = market.platformMaintanenceFee();
        address payt = address(market.payToken());
        assertEq(fee_address, admin);
        assertEq(main, _platformFee);
        assertEq(payt, address(payToken));
        assertEq(market.owner(), admin);
    }

    // #######################################################################
    // #              Service Creation Tests                                 #
    // #######################################################################
    function test_createService() public {
        create_service();
        assertEq(market.services_count(), 1);
        assertEq(market.service_to_owner(1), payable(seller));
        assertEq(market.seller_to_services(seller, 0), 1);
    }

    function test_createServiceEmit() public {
        vm.expectEmit(address(market));
        emit service_created(1, address(seller));
        create_service();
    }

    // #######################################################################
    // #              List Service Tests                                     #
    // #######################################################################
    function test_listService() public {
        uint service_id = 1;
        uint startTime = create_service();
        list_service(service_id, 1 days);
        (uint256 service, uint startingTime) = market.listings(1);
        assertEq(startingTime, startTime);
        assertEq(service, service);
    }

    function test_listServiceEmit() public {
        uint service_id = 1;
        create_service();
        vm.expectEmit(address(market));
        uint startTime = block.timestamp + 1 days;
        emit ItemListed(address(seller), service_id, startTime - 1);
        vm.startPrank(seller);
        list_service(service_id, 1 days);
    }

    function test_listServiceFakeOwner() public {
        create_service();
        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(YouDonotOwnThisService.selector)
        );
        market.listService(1, 1 days);
    }

    function test_listServiceFakeId() public {
        create_service();
        vm.expectRevert(
            abi.encodeWithSelector(YouDonotOwnThisService.selector)
        );
        vm.startPrank(seller);
        list_service(2, 1 days);
    }

    function test_listServiceAlreadyListed() public {
        create_service();
        list_service(1, 1 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                Service_marketplace.AlreadyListed.selector,
                1
            )
        );
        market.listService(1, 1 days);
    }

    // #######################################################################
    // #              Cancel Service Listing Tests                           #
    // #######################################################################
    function test_cancel_listingEmitions() public {
        uint our_real_service = 1;
        uint startTime = block.timestamp + 2 days;
        create_service();
        vm.startPrank(seller);
        list_service(our_real_service, startTime);
        vm.expectEmit(address(market));
        emit ListingCanceled(our_real_service, seller);
        cancel_listing(seller, our_real_service);
    }

    function test_cancel_listing_InvalidService() public {
        uint our_invalid_service = 2;
        uint realListing = 1;
        uint startTime = block.timestamp + 2 days;
        create_service();
        vm.startPrank(seller);
        list_service(realListing, startTime);
        vm.expectRevert(
            abi.encodeWithSelector(NotListed.selector, our_invalid_service)
        );
        cancel_listing(seller, our_invalid_service);
    }

    function test_cancel_listing_FakeOwner() public {
        uint our_real_service = 1;
        address fakeOwner = makeAddr("fakeOwner");
        uint startTime = block.timestamp + 2 days;
        create_service();
        vm.startPrank(seller);
        list_service(our_real_service, startTime);
        vm.expectRevert(
            abi.encodeWithSelector(YouDonotOwnThisService.selector)
        );
        cancel_listing(fakeOwner, our_real_service);
    }

    function test_cancel_listing_TrulyDeleted() public {
        uint our_real_service = 1;
        uint startTime = block.timestamp + 2 days;
        create_service();
        vm.startPrank(seller);
        list_service(our_real_service, startTime);
        cancel_listing(seller, our_real_service);
        (, uint cancelledStartTime) = market.listings(our_real_service);
        assertEq(cancelledStartTime, 0);
    }

    // #######################################################################
    // #              create order Tests                                     #
    // #######################################################################

    function test_addCreateOrder() public {
        uint price = 500_000e18;
        uint our_service = 1;
        createOrderTestSetup();
        vm.startPrank(seller);
        market.addOrderPrice(our_service, price, buyer);
        (address the_buyer, address the_seller, , uint the_price, , , ) = market
            .orderIdToOrder(1);
        assertEq(market.orders_count(), 1);
        assertEq(the_buyer, buyer);
        assertEq(the_seller, seller);
        assertEq(the_price, price);
    }

    function test_addCreateOrder_FakeOwner() public {
        uint price = 500_000e18;
        uint our_service = 1;
        address fakeOwner = makeAddr("FakeOwner");
        createOrderTestSetup();
        vm.startPrank(fakeOwner);
        vm.expectRevert(
            abi.encodeWithSelector(YouDonotOwnThisService.selector)
        );
        market.addOrderPrice(our_service, price, buyer);
    }

    function test_addCreateOrder_Emittions() public {
        uint price = 500_000e18;
        uint our_service = 1;
        createOrderTestSetup();
        vm.startPrank(seller);
        vm.expectEmit(address(market));
        emit orderCreatedBySeller(market.orders_count() + 1, buyer);
        market.addOrderPrice(our_service, price, buyer);
    }

    // #######################################################################
    // #              Complete creation order Tests                          #
    // #######################################################################

    function test_completeOrderCreation() public {
        uint price = 500_000e18;
        Service_marketplace.Completion_status the_required = Service_marketplace
            .Completion_status
            .buyerImplemented;
        uint fees = market.calc_fees(price);
        uint expected_fees = 15e21;
        uint allowed_days = 10;
        uint our_order = 1;
        CompleteOrderCreationSetUp();
        vm.startPrank(buyer);
        market.completeOrderCreation(our_order, allowed_days, price);
        vm.stopPrank();
        (
            ,
            ,
            ,
            uint the_price,
            Service_marketplace.Completion_status status,
            uint allowedTime,

        ) = market.orderIdToOrder(1);

        assertEq(uint(the_required), uint(status));
        assertEq((the_price), (price - fees));
        assertEq(fees, expected_fees);
        assertEq(allowedTime + 1, (allowed_days * 1 days) + 1);
    }

    function test_completeOrderCreation_InvalidId() public {
        uint price = 500_000e18;
        uint allowed_days = 10;
        uint our_order = 2;
        CompleteOrderCreationSetUp();
        vm.expectRevert(
            abi.encodeWithSelector(
                Service_marketplace.Invalid_Order.selector,
                our_order
            )
        );
        vm.startPrank(buyer);
        market.completeOrderCreation(our_order, allowed_days, price);
        vm.stopPrank();
    }

    function test_completeOrderCreation_FakeOwner() public {
        uint price = 500_000e18;
        uint allowed_days = 10;
        uint our_order = 1;
        address fakeBuyer = makeAddr("FakeBuyer");
        CompleteOrderCreationSetUp();
        vm.expectRevert(abi.encodeWithSelector(YouAreNotBuyer.selector));
        vm.startPrank(fakeBuyer);
        market.completeOrderCreation(our_order, allowed_days, price);
        vm.stopPrank();
    }

    function test_completeOrderCreation_LowPrice() public {
        uint agreed_price = 500_000e18;
        uint low_price = 400_000e18;
        uint allowed_days = 10;
        uint our_order = 1;
        CompleteOrderCreationSetUp();
        vm.expectRevert(
            abi.encodeWithSelector(Insufficient_Funds.selector, agreed_price)
        );
        vm.startPrank(buyer);
        market.completeOrderCreation(our_order, allowed_days, low_price);
        vm.stopPrank();
    }

    function test_completeOrderCreation_Emitions() public {
        uint price = 500_000e18;
        uint allowed_days = 10;
        uint our_order = 1;
        CompleteOrderCreationSetUp();
        vm.expectEmit(address(market));
        emit orderImplementedByBuyer(our_order, buyer, allowed_days);
        vm.startPrank(buyer);
        market.completeOrderCreation(our_order, allowed_days, price);
        vm.stopPrank();
    }

    function test_completeOrderCreation_BalanceChanges() public {
        uint price = 500_000e18;
        uint allowed_days = 10;
        uint our_order = 1;
        CompleteOrderCreationSetUp();
        assertEq(payToken.balanceOf(address(buyer)), price);
        vm.startPrank(buyer);
        market.completeOrderCreation(our_order, allowed_days, price);
        vm.stopPrank();
        assertEq(payToken.balanceOf(address(market)), price);
        assertEq(payToken.balanceOf(buyer), 0);
    }

    // #######################################################################
    // #              Cancel order Tests                                     #
    // #######################################################################

    function test_cancelOrder_seller() public {
        Service_marketplace.Completion_status cancelled = Service_marketplace
            .Completion_status
            .cancelled;
        uint our_order = 1;
        CompleteOrderCreationSetUp();
        vm.startPrank(seller);
        market.cancelOrder(our_order);
        vm.stopPrank();
        (, , , , Service_marketplace.Completion_status status, , ) = market
            .orderIdToOrder(our_order);
        assertEq(uint(status), uint(cancelled));
    }

    function test_cancelOrder_buyer() public {
        Service_marketplace.Completion_status cancelled = Service_marketplace
            .Completion_status
            .cancelled;
        uint our_order = 1;
        CompleteOrderCreationSetUp();
        vm.startPrank(buyer);
        market.cancelOrder(our_order);
        vm.stopPrank();
        (, , , , Service_marketplace.Completion_status status, , ) = market
            .orderIdToOrder(our_order);
        assertEq(uint(status), uint(cancelled));
    }

    function test_cancelOrder_fakeOrder() public {
        uint our_order = 2;
        CompleteOrderCreationSetUp();
        vm.expectRevert(
            abi.encodeWithSelector(
                Service_marketplace.Invalid_Order.selector,
                our_order
            )
        );
        vm.startPrank(seller);
        market.cancelOrder(our_order);
        vm.stopPrank();
    }

    function test_cancelOrder_fakeOwner() public {
        address fakeOwner = makeAddr("FakeOwner");
        uint our_order = 1;
        CompleteOrderCreationSetUp();
        vm.expectRevert(
            abi.encodeWithSelector(
                Service_marketplace.YouAreNotBuyerOrSeller.selector
            )
        );
        vm.startPrank(fakeOwner);
        market.cancelOrder(our_order);
        vm.stopPrank();
    }

    function test_cancelOrder_WhenBuyerImplemented() public {
        uint our_order = 1;
        uint price = 500_000e18;
        uint allowed_days = 10;
        CompleteOrderCreationSetUp();

        vm.startPrank(buyer);
        market.completeOrderCreation(our_order, allowed_days, price);
        vm.expectRevert(
            abi.encodeWithSelector(
                OrderAlreadyCompletedorCancelled.selector,
                our_order
            )
        );
        market.cancelOrder(our_order);
        vm.stopPrank();
    }

    function test_cancelOrder_WhenAlreadyCancelled() public {
        uint our_order = 1;
        CompleteOrderCreationSetUp();
        vm.startPrank(buyer);
        market.cancelOrder(our_order);
        vm.stopPrank();
        vm.startPrank(seller);
        vm.expectRevert(
            abi.encodeWithSelector(
                OrderAlreadyCompletedorCancelled.selector,
                our_order
            )
        );

        market.cancelOrder(our_order);
        vm.stopPrank();
    }

    function test_cancelOrder_Emitions() public {
        uint our_order = 1;
        CompleteOrderCreationSetUp();
        vm.expectEmit(address(market));
        emit orderCancelled(our_order);
        vm.startPrank(buyer);
        market.cancelOrder(our_order);
    }

    // #######################################################################
    // #              Complete order Tests                                   #
    // #######################################################################
    function test_completeOrderSeller_changes() public {
        Service_marketplace.Completion_status complete = Service_marketplace
            .Completion_status
            .completed;
        uint our_order = 1;
        uint knownEndTime = block.timestamp + ((10 * 1 days));
        completeOrderSetUp();
        vm.startPrank(seller);
        market.completeOrder(our_order);
        vm.stopPrank();
        (
            ,
            ,
            ,
            ,
            Service_marketplace.Completion_status completed,
            ,
            uint endTime
        ) = market.orderIdToOrder(our_order);
        assertEq(endTime, knownEndTime);
        assertEq(uint(completed), uint(completed));
    }

    function test_completeOrderSeller_NonSeller() public {
        uint our_order = 1;
        completeOrderSetUp();
        vm.expectRevert(abi.encodeWithSelector(YouAreNotSeller.selector));
        vm.startPrank(buyer);
        market.completeOrder(our_order);
        vm.stopPrank();
    }

    function test_completeOrderSeller_Emitions() public {
        uint our_order = 1;
        completeOrderSetUp();
        vm.expectEmit(address(market));
        emit orderCompleted(our_order);
        vm.startPrank(seller);
        market.completeOrder(our_order);
        vm.stopPrank();
    }

    function test_completeOrderSeller_NotBuyerImplemented() public {
        uint our_order = 1;
        completeOrderSetUp();
        vm.startPrank(seller);
        market.completeOrder(our_order);
        vm.expectRevert(
            abi.encodeWithSelector(
                OrderAlreadyCompletedorCancelled.selector,
                our_order
            )
        );
        market.completeOrder(our_order);
    }

    // #######################################################################
    // #              Receive order Tests                                    #
    // #######################################################################
    function test_receiveOrder_changes() public {
        uint our_order = 1;
        Service_marketplace.Completion_status buyerAcceptance = Service_marketplace
                .Completion_status
                .buyerAccepted;
        receiveOrderSetUp();
        vm.startPrank(buyer);
        market.receiveOrder(our_order);
        vm.stopPrank();
        (
            ,
            ,
            ,
            uint price,
            Service_marketplace.Completion_status the_acceptance,
            ,

        ) = market.orderIdToOrder(our_order);
        uint paid_price = payToken.balanceOf(seller);
        assertEq(price, paid_price);
        assertEq(uint(the_acceptance), uint(buyerAcceptance));
    }

    function test_receiveOrder_NonBuyer() public {
        uint our_order = 1;
        receiveOrderSetUp();
        vm.startPrank(seller);
        vm.expectRevert(abi.encodeWithSelector(YouAreNotBuyer.selector));
        market.receiveOrder(our_order);
        vm.stopPrank();
    }

    function test_receiveOrder_NotCompleteStaus() public {
        uint our_order = 1;
        receiveOrderSetUp();
        vm.startPrank(buyer);
        market.receiveOrder(our_order);
        vm.expectRevert(
            abi.encodeWithSelector(
                YouCannotReceiveTheOrderNow.selector,
                our_order
            )
        );
        market.receiveOrder(our_order);
        vm.stopPrank();
    }

    function test_receiveOrder_Emitions() public {
        uint our_order = 1;
        receiveOrderSetUp();
        vm.startPrank(buyer);
        vm.expectEmit(address(market));
        emit orderReceived(our_order);
        market.receiveOrder(our_order);
        vm.stopPrank();
    }

    // #####################################################################
    // #              Has time Elapsed Buyer Tests                         #
    // #####################################################################

    function test_hasTimeElapsedBuyer_fakeOwner() public {
        address fakeBuyer = makeAddr("fakeBuyer");
        uint our_order = 1;
        hasTimeElapsedBuyerTest();
        vm.expectRevert(
            abi.encodeWithSelector(YouAreNotBuyerOrSeller.selector)
        );
        vm.startPrank(fakeBuyer);
        market.hasAllowedTimeElapsed(our_order);
    }

    function test_hasTimeElapsedBuyer_sets() public {
        uint our_order = 1;
        Service_marketplace.Completion_status needed = Service_marketplace
            .Completion_status
            .cancelled;
        hasTimeElapsedBuyerTest();
        vm.startPrank(buyer);
        market.hasAllowedTimeElapsed(our_order);
        (, , , , Service_marketplace.Completion_status got, , ) = market
            .orderIdToOrder(our_order);
        assertEq(uint(needed), uint(got));
    }

    function test_hasTimeElapsedBuyer_emitions() public {
        uint our_order = 1;
        hasTimeElapsedBuyerTest();
        vm.expectEmit(address(market));
        emit refundedBuyer(our_order);
        vm.startPrank(buyer);
        market.hasAllowedTimeElapsed(our_order);
    }

    function test_hasTimeElapsedBuyer_notYet() public {
        uint our_order = 1;
        Service_marketplace.Completion_status needed = Service_marketplace
            .Completion_status
            .buyerImplemented;
        completeOrderSetUp();
        vm.warp(7 days);
        vm.startPrank(buyer);
        market.hasAllowedTimeElapsed(our_order);
        (, , , , Service_marketplace.Completion_status got, , ) = market
            .orderIdToOrder(our_order);
        assertEq(uint(needed), uint(got));
    }

    function test_hasTimeElapsedBuyer_balances() public {
        uint our_order = 1;
        uint expected_balance = 500_000e18;
        hasTimeElapsedBuyerTest();
        uint balance_buyer = payToken.balanceOf(buyer);
        uint market_balance = payToken.balanceOf(address(market));
        console.log("Our balances are:", balance_buyer, market_balance);
        assertEq(0, balance_buyer);
        assertEq(expected_balance, market_balance);
        vm.startPrank(buyer);
        market.hasAllowedTimeElapsed(our_order);
        vm.stopPrank();
        balance_buyer = payToken.balanceOf(buyer);
        market_balance = payToken.balanceOf(address(market));
        console.log("Our balances are second:", balance_buyer, market_balance);
        assertEq(expected_balance, balance_buyer);
        assertEq(0, market_balance);
    }

    // #####################################################################
    // #              Has time Elapsed seller Tests                        #
    // #####################################################################

    function test_hasTimeElapsedSeller_sets() public {
        uint our_order = 1;
        Service_marketplace.Completion_status needed = Service_marketplace
            .Completion_status
            .buyerAccepted;
        hasTimeElapsedSellerTest();
        vm.startPrank(seller);
        market.hasAllowedTimeElapsed(our_order);
        (, , , , Service_marketplace.Completion_status got, , ) = market
            .orderIdToOrder(our_order);
        assertEq(uint(needed), uint(got));
    }

    function test_hasTimeElapsedSeller_emitions() public {
        uint our_order = 1;
        hasTimeElapsedSellerTest();
        vm.expectEmit(address(market));
        emit orderReceivedBySeller(our_order);
        vm.startPrank(seller);
        market.hasAllowedTimeElapsed(our_order);
    }

    function test_hasTimeElapsedSeller_notYet() public {
        uint our_order = 1;
        Service_marketplace.Completion_status needed = Service_marketplace
            .Completion_status
            .completed;
        receiveOrderSetUp();
        vm.warp(7 days);
        vm.startPrank(seller);
        market.hasAllowedTimeElapsed(our_order);
        (, , , , Service_marketplace.Completion_status got, , ) = market
            .orderIdToOrder(our_order);
        assertEq(uint(needed), uint(got));
    }

    function test_hasTimeElapsedSeller_balances() public {
        uint our_order = 1;
        hasTimeElapsedSellerTest();
        uint expected_balance = 500_000e18;
        uint balance_seller = payToken.balanceOf(seller);
        uint market_balance = payToken.balanceOf(address(market));
        console.log("Our balances First:", balance_seller, market_balance);
        assertEq(0, balance_seller);
        assertEq(expected_balance, market_balance);
        vm.startPrank(seller);
        market.hasAllowedTimeElapsed(our_order);
        vm.stopPrank();
        uint expected_balance_market = market.calc_fees(expected_balance);
        uint expected_balance_seller = expected_balance -
            expected_balance_market;
        balance_seller = payToken.balanceOf(seller);
        market_balance = payToken.balanceOf(address(market));
        console.log("Our balances are second:", balance_seller, market_balance);
        assertEq(expected_balance_seller, balance_seller);
        assertEq(expected_balance_market, market_balance);
    }

    // #####################################################################
    // #              Dispute Order Tests                                  #
    // #####################################################################

    function test_disputeOrder_sets() public {
        uint our_order = 1;
        receiveOrderSetUp();
        vm.startPrank(buyer);
        market.disputeCompletedOrder(our_order);
        vm.stopPrank();
        bool disputed = market.dispute(our_order);
        assert(disputed);
    }

    function test_disputeOrder_NonBuyer() public {
        uint our_order = 1;
        receiveOrderSetUp();
        vm.startPrank(seller);
        vm.expectRevert(abi.encodeWithSelector(YouAreNotBuyer.selector));
        market.disputeCompletedOrder(our_order);
    }

    function test_disputeOrder_NotCompletedStatus() public {
        uint our_order = 1;
        uint32 status = uint32(
            Service_marketplace.Completion_status.buyerAccepted
        );
        receiveOrderSetUp();
        vm.startPrank(buyer);
        market.receiveOrder(our_order);
        vm.expectRevert(
            abi.encodeWithSelector(YouCannotDispute.selector, status)
        );
        market.disputeCompletedOrder(our_order);
    }

     function test_disputeOrder_Emitions() public {
        uint our_order = 1;
        uint32 status = uint32(
            Service_marketplace.Completion_status.buyerAccepted
        );
        receiveOrderSetUp();
        vm.startPrank(buyer);
        vm.expectEmit(address(market));
        emit BuyerDisputed(our_order);
        market.disputeCompletedOrder(our_order);
    }
}
