//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Lookmans} from "../../src/Erc20/LookmansToken.sol";
import {Service_marketplace} from "../../src/service_marketplace.sol";

import {Upgrades} from "@openzeppelin-upgrades/Upgrades.sol";

contract TestService_marketplace is Test {
    Service_marketplace public market;
    Lookmans public payToken;
    address buyer = makeAddr("buyer");
    address admin = makeAddr("admin");
    address seller = makeAddr("seller");
    uint256 _platformFee = 2e18;
    uint buyerFunds = 10000e18;

    function setUp() public {
        market = Upgrades.deployTransparentProxy(
            "Service_marketplace.sol",
            admin,
            abi.encodeCall(
                market.initialize,
                payable(admin),
                _platformFee,
                address(payToken)
            )
        );

        payToken = Upgrades.deployTransparentProxy(
            "Service_marketplace.sol",
            admin,
            abi.encodeCall(payToken.initialize, admin, admin, admin)
        );
        //payToken.initialize(admin, admin, admin);
        //market.initialize(payable(admin), _platformFee, address(payToken));

        payToken.mint(buyer, buyerFunds);

        console.log(seller);
    }

    function test_createService() public {
        setUp();
    }
}
