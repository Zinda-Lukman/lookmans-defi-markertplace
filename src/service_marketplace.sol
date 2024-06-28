//SPDX-lincence-Identifintier: MIT
/**
 *  - create a service with price
 *  - list it
 *  -unlist it
     - negotiate with price
*/

pragma solidity ^0.8.20;
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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

contract Service_marketplace is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    // Our Structure Types
    // @notice Structure for listed items
    enum Completion_status {
        created,
        buyerImplemented,
        cancelled,
        completed,
        buyerAccepted
    }

    struct Listing {
        uint256 service;
        uint256 startingTime;
    }

    //@notice order struct
    struct Order {
        address buyer;
        address seller;
        Listing service;
        uint256 price;
        Completion_status orderStatus;
        uint256 allowedTime;
    }

    //@notice Events for the contract

    event ItemListed(
        address indexed owner,
        uint256 serviceId,
        uint256 startingTime
    );

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

    //contract Variables
    /// @notice Allows a buyer to dispute a completed order
    mapping(uint256 => bool) public dispute;
    /// @notice default paytoken address
    IERC20 public payToken;
    /// @notice Platform fee
    uint256 public platformMaintanenceFee;
    //@notice service start
    uint256 public services_count = 0;
    //@notice orders start
    uint256 public orders_count = 0;
    //@notice platformFeeRecepient
    address public feeReceipient;

    //Mappings
    /// @notice service -> seller
    mapping(uint256 => address) public seller;

    /// @notice serviceid => Listing
    mapping(uint256 => Listing) public listings;

    //@notice buyer => orders
    mapping(address => uint256[]) public buyer_to_orders;

    ///@notice service => owner
    mapping(uint256 => address) public service_to_owner;

    ///@notice seller => service
    mapping(address => uint256[]) public seller_to_services;
    //@notice order => agreed price
    mapping(uint256 => Order) public orderIdToOrder;
    //@notice order to buyer
    mapping(uint256 => address) public orderToBuyer;

    /////modifiers////

    modifier isListed(uint256 _service) {
        if (listings[_service].startingTime == 0) {
            revert NotListed(_service);
        }
        _;
    }

    modifier notListed(uint256 _service, address _owner) {
        if (listings[_service].startingTime != 0) {
            revert AlreadyListed(_service);
        }
        if (_owner != service_to_owner[_service]) {
            revert YouDonotOwnThisService();
        }
        _;
    }

    modifier validOrder(uint orderId) {
        if (orderId <= 0) {
            revert Invalid_Order(orderId);
        }
        _;
    }
    modifier NonZeroAddress(address zero) {
        if (zero == address(0)) {
            revert ZeroAddress(zero);
        }
        _;
    }

    /// @notice Contract initializer
    function initialize(
        address payable _feeRecipient,
        uint _platformFee,
        address _payToken
    )
        public
        initializer
        NonZeroAddress(_feeRecipient)
        NonZeroAddress(_payToken)
    {
        payToken = IERC20(_payToken);
        platformMaintanenceFee = _platformFee;
        feeReceipient = _feeRecipient;

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
    }

    //@notice method for creating a new service
    function createService() external nonReentrant {
        services_count = services_count + 1;
        service_to_owner[services_count] = payable(msg.sender);
        seller_to_services[msg.sender].push(services_count);

        emit service_created(services_count, msg.sender);
    }

    /// @notice Method for listing a service
    /// @param _serviceId of the service
    /// @param _startingTime scheduling for a future sale
    function listService(
        uint256 _serviceId,
        uint256 _startingTime
    ) external notListed(_serviceId, msg.sender) {
        listings[_serviceId] = Listing(
            _serviceId,
            block.timestamp + _startingTime
        );
        emit ItemListed(msg.sender, _serviceId, _startingTime);
    }

    /// @notice Method for canceling listed NFT
    function cancelListing(
        uint256 _serviceId
    ) external nonReentrant isListed(_serviceId) {
        _cancelListing(_serviceId, msg.sender);
    }

    /**  Allows Seller to add a price to an order created by a seller as have agreed
    @param serviceId - Id of the service in the order
    @param price - price that they have agreed upon with the seller
    @param buyer - the buyer of this order
    */
    function addOrderPrice(
        uint256 serviceId,
        uint256 price,
        address buyer
    ) external nonReentrant {
        _validOwner(serviceId, msg.sender);
        orders_count = orders_count + 1;
        orderIdToOrder[orders_count] = Order(
            payable(buyer),
            payable(msg.sender),
            listings[serviceId],
            price,
            Completion_status.created,
            0
        );
        emit orderCreatedBySeller(orders_count, buyer);
    }

    /** @notice function to allow buyer to complete order creation. 
   //Reverts:-
   //   -When message sender is not buyer
   //   -When value is not the set price
   //   - When order does not exist */

    function completeOrderCreation(
        uint256 orderId,
        uint256 allowedTime,
        uint agreedPrice
    ) external payable validOrder(orderId) {
        uint order_price = orderIdToOrder[orderId].price +
            platformMaintanenceFee;

        if (agreedPrice != order_price) {
            revert Insufficient_Funds(order_price);
        }

        if (msg.sender != orderIdToOrder[orderId].buyer) {
            revert YouAreNotBuyer();
        }
        orderIdToOrder[orderId].orderStatus = Completion_status
            .buyerImplemented;
        orderIdToOrder[orderId].allowedTime =
            block.timestamp +
            allowedTime *
            1 days;
        payToken.transfer(address(this), order_price);

        emit orderImplementedByBuyer(orderId, msg.sender, allowedTime);
    }

    /** Allows cancelling of an order by a buyer / seller
       Reverts if:-
        -Order already completed
        -Sender is neither buyer or seller
        @param orderId of the order
   
    */
    function cancelOrder(uint256 orderId) public validOrder(orderId) {
        Order memory order = orderIdToOrder[orderId];
        bool validSender = msg.sender == order.buyer ||
            msg.sender == order.seller;
        bool alreadyCompleted = order.orderStatus >=
            Completion_status.buyerImplemented;

        if (!validSender) {
            revert YouAreNotBuyerOrSeller();
        }

        if (alreadyCompleted) {
            revert OrderAlreadyCompletedorCancelled(orderId);
        }

        orderIdToOrder[orderId].orderStatus = Completion_status.cancelled;

        emit orderCancelled(orderId);
    }

    /**Allows a buyer to confirm that order has been received
   
    */
    function receiveOrder(uint256 orderId) external validOrder(orderId) {
        Order memory order = orderIdToOrder[orderId];
        if (msg.sender != order.buyer) {
            revert YouAreNotBuyer();
        }
        if (
            order.orderStatus == Completion_status.buyerAccepted ||
            order.orderStatus == Completion_status.cancelled
        ) {
            revert OrderAlreadyCompletedorCancelled(orderId);
        }
        _sendPayment(order.price, payable(order.seller));
        orderIdToOrder[orderId].orderStatus = Completion_status.buyerAccepted;

        emit orderReceived(orderId);
    }

    //Allows a seller to mark an order as completed
    function completeOrder(uint orderId) external validOrder(orderId) {
        if (msg.sender != orderIdToOrder[orderId].seller) {
            revert YouAreNotSeller();
        }
        orderIdToOrder[orderId].orderStatus = Completion_status.completed;
        orderIdToOrder[orderId].allowedTime =
            block.timestamp +
            orderIdToOrder[orderId].allowedTime;
        emit orderCompleted(orderId);
    }

    function hasAllowedTimeElapsed(uint orderId) external {
        Order memory order = orderIdToOrder[orderId];

        if (!(order.seller == msg.sender || order.buyer == msg.sender)) {
            revert YouAreNotBuyerOrSeller();
        }

        if (
            msg.sender == order.seller &&
            order.orderStatus == Completion_status.completed &&
            order.allowedTime < block.timestamp &&
            dispute[orderId] == false
        ) {
            _sendPayment(order.price, payable(order.seller));
            orderIdToOrder[orderId].orderStatus = Completion_status
                .buyerAccepted;
            emit orderReceivedBySeller(orderId);
        } else if (
            msg.sender == order.buyer &&
            order.orderStatus == Completion_status.buyerImplemented &&
            (order.allowedTime + 1 days) < block.timestamp
        ) {
            _sendPayment(order.price, payable(order.buyer));
            emit refundedBuyer(orderId);
        }
    }

    function disputeCompletedOrder(uint orderId) external {
        Order memory order = orderIdToOrder[orderId];

        if (msg.sender != order.buyer) {
            revert YouAreNotBuyer();
        }
        if (!(order.orderStatus == Completion_status.completed)) {
            revert YouCannotCancelTheOrderAtThisStage(
                uint32(order.orderStatus)
            );
        }
        dispute[orderId] = true;
        emit BuyerDisputed(orderId);
    }

    //send a payment to a receiver
    function _sendPayment(uint256 price, address payable receiver) internal {
        payToken.transfer(receiver, price);
    }

    /**@notice Method for updating platform fee
     @dev Only admin
     @param _platformFee uint16 the platform fee to set
     */
    function updatePlatformFee(uint16 _platformFee) external onlyOwner {
        platformMaintanenceFee = _platformFee;
        emit UpdatePlatformFee(_platformFee);
    }

    /**@notice Method for updating platform fee address
     @dev Only admin
     @param _platformFeeRecipient payable address the address to sends the funds to */
    function updatePlatformFeeRecipient(
        address payable _platformFeeRecipient
    ) external onlyOwner {
        feeReceipient = _platformFeeRecipient;
        emit UpdatePlatformFeeRecipient(_platformFeeRecipient);
    }

    ////////////////////////////////
    ///Internal and Private/////////
    ////////////////////////////////

    //Get the current Block timestamp
    function _getNow() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    /**@notice Know if address owner owns service _service
       @param _service whose owner to be checked
       @param _owner address to be checked if its the real owner of the service
       Reverts if:
            _Owner does not own the service  */
    function _validOwner(uint256 _service, address _owner) internal view {
        if (!(service_to_owner[_service] == _owner)) {
            revert YouDonotOwnThisService();
        }
    }

    function _cancelListing(uint256 _serviceId, address _owner) internal {
        _validOwner(_serviceId, _owner);
        delete (listings[_serviceId]);
        emit ListingCanceled(_serviceId, _owner);
    }
}
