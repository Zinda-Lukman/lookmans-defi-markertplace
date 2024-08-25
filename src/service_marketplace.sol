// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Service_marketplace is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    error AlreadyClaimed(uint index);
    error Invalid_Order(uint orderId);
    error Insufficient_Funds(uint requiredValue);
    error YouAreNotBuyer();
    error YouAreNotSeller();
    error YouAreNotBuyerOrSeller();
    error OrderAlreadyCompletedorCancelled(uint OrderId);
    error YouCannotReceiveTheOrderNow(uint orderId);
    error TooMuchFees();
    error YouDonotOwnThisService();
    error AlreadyListed(uint _service);
    error NotListed(uint _service);
    error ZeroAddress(address zero);
    error YouCannotCancelTheOrderAtThisStage(uint32 status);
    error YouCannotDispute(uint32 status);
    error TrackerRunning(uint order);
    error TrackerNotRunning(uint order);
    error HoursNotPaid();
    error ExceededEstimatedHours(uint order);
    error YouCannotCompleteTheOrderAtThisStage(uint orderId);
    error NoTimeElapsed();

    // Our Structure Types
    // @notice Structure for listed items
    enum Completion_status {
        unknown,
        created,
        cancelled,
        buyerImplemented,
        completed,
        buyerAccepted
    }

    struct Listing {
        uint256 service;
        uint256 startingTime;
    }
    struct HourlyOrder {
        uint payPerhour;
        uint initialAmount;
        uint desiredHours;
        uint estimatedBudget;
        uint movingBudget;
        uint hoursWorked;
        bool allowExceed;
        Tracker tracker;
    }

    //@notice order struct
    struct Order {
        address buyer;
        address seller;
        Listing service;
        uint256 price;
        Completion_status orderStatus;
        uint256 allowedTime;
        uint256 endTime;
    }
    //hours tracker
    struct Tracker {
        uint paidhours;
        int remaining;
        uint tracking;
        uint untrackedSeconds;
        uint untrackedAmout;
    }
    //Hourly order sessions
    struct Session {
        uint startTime;
        uint endTime;
        uint workedHours;
        bool claimAllowed;
        bool claimed;
    }

    //@notice Events for the contract

    event ItemListed(
        address indexed owner,
        uint256 serviceId,
        uint256 startingTime
    );

    event payIncreased(uint order, uint amount);
    event ItemUpdated(address indexed owner, uint256 serviceId);

    event ListingCanceled(uint256 serviceId, address indexed seller);

    event service_created(uint256 serviceId, address seller);
    event orderCreatedBySeller(uint256 orderId, address Buyer);
    event orderImplementedByBuyer(
        uint256 orderId,
        address buyer,
        uint256 allowedTime,
        bool hourly
    );
    event orderCancelled(uint256 indexed orderId);
    event orderCompleted(uint256 indexed orderId);
    event orderReceivedBySeller(uint orderId);
    event BuyerDisputed(uint indexed order);
    event refundedBuyer(uint indexed orderId);
    event orderReceived(uint orderId);
    event UpdatePlatformFee(uint16 platformFee);
    event UpdatePlatformFeeRecipient(address platformFeeRecipient);
    event TrackerStarted(uint currentTime, uint order);
    event TrackerStopped(uint hourWorked, uint order);
    event Claimed(uint amount, uint order, uint[] sessionIndices);
    event AllowedToClaim(uint order, uint[] sessionIndices);

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
    //Time to wait before buyer can withdraw his fees
    uint waitPeriod = 3 * 1 days;
    //hour in second
    uint anHour = 60 * 60;

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

    ///@notice Is an order hourly
    mapping(uint order => bool ishourly) public isOrderHourly;

    ///@notice hourlyOrder to struct
    mapping(uint order => HourlyOrder hourlyStruct) public hourOrderToItsStruct;

    //nulltracker for assgnments
    Tracker private nulltracker = Tracker(0, 0, 0, 0, 0);
    //Hourly Order sessions
    mapping(uint hourlyOrder => Session[] sessions) public orderToSessions;

    /////modifiers////

    modifier isListed(uint256 _service) {
        if (listings[_service].startingTime == 0) {
            revert NotListed(_service);
        }
        _;
    }

    modifier isHourly(uint orderId) {
        require(isOrderHourly[orderId], "This is not an hourly order");

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
        if (orderId <= 0 || orderId > orders_count) {
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

    /**
    modifier validService(uint serviceId) {
        if (serviceId <= 0 && serviceId > services_count) {
            revert Invalid_Service(serviceId);
        }
        _;
    }
 */
    /// @notice Contract initializer
    function initialize(
        address _feeRecipient,
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
        service_to_owner[services_count] = (msg.sender);
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
        address buyer,
        bool hourly,
        uint payPerHour,
        uint agreedBudget
    ) external nonReentrant NonZeroAddress(buyer) {
        _validOwner(serviceId, msg.sender);
        orders_count = orders_count + 1;
        if (!hourly) {
            require(
                payPerHour == 0 && agreedBudget == 0 && price > 0,
                "Invalid Fixed Pay Params"
            );
        } else {
            require(
                price == 0 && payPerHour > 0 && agreedBudget > 0,
                "Hourly orders don't have a fixed price."
            );
            _assignHourlyOrder(orders_count, payPerHour, agreedBudget);
        }

        orderIdToOrder[orders_count] = Order(
            (buyer),
            (msg.sender),
            listings[serviceId],
            price,
            Completion_status.created,
            0,
            0
        );
        emit orderCreatedBySeller(orders_count, buyer);
    }

    /**
     *
     * @param orderId - hourlyOrder to assign
     * @param payPerhour - payment per hour
     */
    function _assignHourlyOrder(
        uint orderId,
        uint payPerhour,
        uint estimatedBudget
    ) internal {
        isOrderHourly[orderId] = true;
        hourOrderToItsStruct[orderId] = HourlyOrder(
            payPerhour,
            0,
            0,
            estimatedBudget,
            0,
            0,
            false,
            nulltracker
        );
    }

    /** @notice function to allow buyer to complete order creation. 
   //Reverts:-
   //   -When message sender is not buyer
   //   -When value is not the set price
   //   - When order does not exist */

    function completeOrderCreation(
        uint256 orderId,
        uint256 allowedTime,
        uint agreedPrice,
        uint estimatedBudget,
        uint estimatedHours,
        uint initialPay,
        bool allowExceed
    ) external nonReentrant validOrder(orderId) {
        Order memory order = orderIdToOrder[orderId];

        if (msg.sender != order.buyer) {
            revert YouAreNotBuyer();
        }
        if (order.orderStatus != Completion_status.buyerImplemented) {
            revert YouCannotCompleteTheOrderAtThisStage(orderId);
        }

        if (isOrderHourly[orderId]) {
            require(allowedTime == 0 && agreedPrice == 0, "Not fixed Order");
            require(
                estimatedHours > 0 && initialPay > 0 && estimatedBudget > 0,
                "Invalid Hourly params"
            );
            _completeHourlyCreation(
                orderId,
                estimatedHours,
                estimatedBudget,
                initialPay,
                allowExceed
            );
        } else {
            require(
                estimatedHours == 0 && estimatedBudget == 0,
                "Not hourly Order"
            );
            require(
                allowedTime >= 1 days && agreedPrice > 0,
                "Invalid AllowedTime"
            );
            if (agreedPrice < order.price) {
                revert Insufficient_Funds(order.price);
            }
            uint256 duration = allowedTime * 1 days;
            //subtrcting the share for the platform for maintainance
            orderIdToOrder[orderId].price =
                order.price -
                calc_fees(order.price);
            orderIdToOrder[orderId].allowedTime = duration;
            orderIdToOrder[orderId].endTime = block.timestamp + duration;
            _safeTransferFrom(
                address(payToken),
                (order.buyer),
                address(this),
                order.price
            );
        }

        orderIdToOrder[orderId].orderStatus = Completion_status
            .buyerImplemented;
        emit orderImplementedByBuyer(
            orderId,
            msg.sender,
            allowedTime,
            isOrderHourly[orderId]
        );
    }

    function _completeHourlyCreation(
        uint orderId,
        uint estimatedHours,
        uint estimatedBudget,
        uint initialPay,
        bool allowExceed
    ) internal {
        HourlyOrder memory hourly = hourOrderToItsStruct[orderId];
        require(
            estimatedBudget >= hourly.estimatedBudget,
            "Inconsistent Buyer/seller Budgets"
        );
        uint payPerHour = estimatedBudget / estimatedHours;
        require(
            payPerHour >= hourly.payPerhour,
            "Limited funds based on sellers set"
        );
        //initialipay be equal to 33% + dusts
        uint topay = _calc_initialPay(estimatedBudget) + (estimatedBudget % 3);
        require(
            initialPay >= topay,
            "Provided Initial pay less than calculated"
        );
        _safeTransferFrom(
            address(payToken),
            (msg.sender),
            address(this),
            topay
        );
        hourOrderToItsStruct[orderId].initialAmount = topay;
        hourOrderToItsStruct[orderId].desiredHours = estimatedHours;
        hourOrderToItsStruct[orderId].estimatedBudget = estimatedBudget;
        hourOrderToItsStruct[orderId].estimatedBudget += topay;
        hourOrderToItsStruct[orderId].allowExceed = allowExceed;
        _assignHours(orderId, hourOrderToItsStruct[orderId]);
    }

    function _assignHours(uint order, HourlyOrder memory hourly) internal {
        uint hoursPaid = hourly.initialAmount / hourly.payPerhour;
        uint dustPay = hourly.initialAmount % hourly.payPerhour;
        Tracker memory orderTracker = Tracker(
            hoursPaid, //uint paidhours
            int(hoursPaid), //uint remaining
            0, // uint tracking
            0, //uint second
            dustPay //int untrackedAmout
        );
        hourOrderToItsStruct[order].tracker = orderTracker;
    }

    function startTracker(
        uint order,
        bool noPay
    ) external isHourly(order) validOrder(order) {
        HourlyOrder memory hourlyOrder = hourOrderToItsStruct[order];

        if (hourlyOrder.tracker.tracking != 0) {
            revert TrackerRunning(order);
        }
        if (orderIdToOrder[order].seller != msg.sender) {
            revert YouAreNotSeller();
        }
        if (
            hourlyOrder.desiredHours <= hourlyOrder.hoursWorked &&
            !(hourlyOrder.allowExceed)
        ) {
            revert ExceededEstimatedHours(order);
        }
        if (hourlyOrder.tracker.remaining <= 0 && !noPay) {
            revert HoursNotPaid();
        }
        hourOrderToItsStruct[order].tracker.tracking = block.timestamp;
        emit TrackerStarted(block.timestamp, order);
    }

    function stopTracker(
        uint order
    ) external validOrder(order) isHourly(order) {
        uint stopTime = block.timestamp;
        HourlyOrder memory hourlyOrder = hourOrderToItsStruct[order];

        if (hourlyOrder.tracker.tracking == 0) {
            revert TrackerNotRunning(order);
        }
        if (orderIdToOrder[order].seller != msg.sender) {
            revert YouAreNotSeller();
        }
        if (stopTime == hourlyOrder.tracker.tracking) {
            revert NoTimeElapsed();
        }

        uint timeWorked = stopTime - hourlyOrder.tracker.tracking;
        uint hoursWorked = (timeWorked + hourlyOrder.tracker.untrackedSeconds) /
            anHour;
        uint untrackedSeconds = (timeWorked +
            hourlyOrder.tracker.untrackedSeconds) % anHour;

        hourOrderToItsStruct[order].tracker.remaining -= int(hoursWorked);
        hourOrderToItsStruct[order].tracker.untrackedSeconds = untrackedSeconds;
        hourOrderToItsStruct[order].hoursWorked += hoursWorked;
        orderToSessions[order].push(
            Session({
                startTime: hourlyOrder.tracker.tracking,
                workedHours: hoursWorked,
                endTime: stopTime,
                claimAllowed: false,
                claimed: false
            })
        );
        hourOrderToItsStruct[order].tracker.tracking = 0;

        emit TrackerStopped(hoursWorked, order);
    }

    function allowClaim(
        uint order,
        uint[] calldata indices
    ) external validOrder(order) isHourly(order) {
        if (indices.length == 0) {
            revert("No indices to allow.");
        }
        if (msg.sender != orderIdToOrder[order].buyer) {
            revert YouAreNotBuyer();
        }
        Session[] memory sessions = orderToSessions[order];
        if (indices.length > sessions.length)
            revert("Provided Too Many Indices");
        for (uint i = 0; i < indices.length; i++) {
            if (indices[i] >= sessions.length || indices[i] < 0)
                revert("Invalid Index");
            if (sessions[indices[i]].claimed) revert AlreadyClaimed(order);
            orderToSessions[order][indices[i]].claimAllowed = true;
        }
        emit AllowedToClaim(order, indices);
    }

    function claim(
        uint order,
        uint[] calldata indices
    ) external nonReentrant validOrder(order) isHourly(order) {
        if (indices.length == 0) {
            revert("No indices to allow.");
        }
        if (msg.sender != orderIdToOrder[order].seller) {
            revert YouAreNotBuyer();
        }
        Session[] memory sessions = orderToSessions[order];
        uint payPerHour = hourOrderToItsStruct[order].payPerhour;

        if (indices.length > sessions.length)
            revert("Provided Too Many Indices");
        uint toSend;
        for (uint i = 0; i < indices.length; i++) {
            if (indices[i] >= sessions.length || indices[i] < 0)
                revert("Invalid Index");
            if (sessions[indices[i]].claimed) revert AlreadyClaimed(order);
            if (!sessions[indices[i]].claimAllowed)
                revert("Claim Not Alllowed.");
            toSend += (payPerHour * sessions[indices[i]].workedHours);
            orderToSessions[order][indices[i]].claimed = true;
        }
        if (hourOrderToItsStruct[order].movingBudget < toSend)
            revert("Insufficient Allowed Amount");
        hourOrderToItsStruct[order].movingBudget -= toSend;

        _sendPayment(toSend, msg.sender);
        emit Claimed(toSend, order, indices);
    }

    function increasePay(
        uint order,
        uint amount
    ) external nonReentrant validOrder(order) isHourly(order) {
        HourlyOrder memory hourlyOrder = hourOrderToItsStruct[order];
        uint availableAmount = amount + hourlyOrder.tracker.untrackedAmout;
        if (orderIdToOrder[order].buyer != msg.sender) {
            revert YouAreNotBuyer();
        }
        if (availableAmount < hourlyOrder.payPerhour) {
            revert Insufficient_Funds(hourlyOrder.payPerhour);
        }
        uint paidhours = availableAmount / hourlyOrder.payPerhour;
        _safeTransferFrom(address(payToken), msg.sender, address(this), amount);
        hourOrderToItsStruct[order].movingBudget += amount;
        hourOrderToItsStruct[order].tracker.paidhours += paidhours;
        hourOrderToItsStruct[order].tracker.remaining += int(paidhours);
        hourOrderToItsStruct[order].tracker.untrackedAmout =
            availableAmount %
            hourlyOrder.payPerhour;

        emit payIncreased(order, amount);
    }

    function _completeHourlyOrder(uint order) internal {
        HourlyOrder memory hourlyOrder = hourOrderToItsStruct[order];
        uint totalPrice = hourlyOrder.payPerhour * hourlyOrder.hoursWorked;
        if (hourlyOrder.payPerhour > anHour) {
            uint payPerSecond = hourlyOrder.payPerhour / anHour;
            uint leftOver = hourlyOrder.tracker.untrackedSeconds * payPerSecond;
            totalPrice += leftOver;
        }
        if (hourlyOrder.movingBudget > totalPrice) {
            _sendPayment(
                (hourlyOrder.movingBudget - totalPrice),
                (orderIdToOrder[order].buyer)
            );
        }
        orderIdToOrder[order].price = totalPrice;
    }

    function _calc_initialPay(uint myBudget) public pure returns (uint) {
        return myBudget / 3;
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
        bool alreadyImplememnted = order.orderStatus !=
            Completion_status.created;

        if (!validSender) {
            revert YouAreNotBuyerOrSeller();
        }

        if (alreadyImplememnted) {
            revert OrderAlreadyCompletedorCancelled(orderId);
        }

        orderIdToOrder[orderId].orderStatus = Completion_status.cancelled;

        emit orderCancelled(orderId);
    }

    //Allows a seller to mark an order as completed
    function completeOrder(uint orderId) external validOrder(orderId) {
        Order memory order = orderIdToOrder[orderId];
        if (msg.sender != order.seller) {
            revert YouAreNotSeller();
        }
        if (order.orderStatus != Completion_status.buyerImplemented)
            revert OrderAlreadyCompletedorCancelled(orderId);
        if (isOrderHourly[orderId]) _completeHourlyOrder(orderId);
        orderIdToOrder[orderId].orderStatus = Completion_status.completed;
        orderIdToOrder[orderId].endTime = block.timestamp + waitPeriod;
        emit orderCompleted(orderId);
    }

    /**Allows a buyer to confirm that order has been received
   
    */
    function receiveOrder(
        uint256 orderId
    ) external nonReentrant validOrder(orderId) {
        Order memory order = orderIdToOrder[orderId];
        if (msg.sender != order.buyer) {
            revert YouAreNotBuyer();
        }
        if (order.orderStatus != Completion_status.completed)
            revert YouCannotReceiveTheOrderNow(orderId);

        orderIdToOrder[orderId].orderStatus = Completion_status.buyerAccepted;
        if (dispute[orderId]) dispute[orderId] = false;
        if (!(isOrderHourly[orderId])) {
            _sendPayment(order.price, (order.seller));
        }
        emit orderReceived(orderId);
    }

    function hasAllowedTimeElapsed(
        uint orderId
    ) external nonReentrant validOrder(orderId) {
        Order memory order = orderIdToOrder[orderId];

        if (!(order.seller == msg.sender || order.buyer == msg.sender)) {
            revert YouAreNotBuyerOrSeller();
        }

        uint expirely = order.endTime + 1 days;

        if (
            msg.sender == order.seller &&
            order.orderStatus == Completion_status.completed &&
            expirely <= block.timestamp &&
            dispute[orderId] == false
        ) {
            orderIdToOrder[orderId].orderStatus = Completion_status
                .buyerAccepted;
            _sendPayment(order.price, (order.seller));
            emit orderReceivedBySeller(orderId);
        } else if (
            msg.sender == order.buyer &&
            order.orderStatus == Completion_status.buyerImplemented &&
            expirely <= block.timestamp
        ) {
            orderIdToOrder[orderId].orderStatus = Completion_status.cancelled;
            _sendPayment(reverse_price(order.price), (order.buyer));
            emit refundedBuyer(orderId);
        }
    }

    function disputeCompletedOrder(uint orderId) external validOrder(orderId) {
        Order memory order = orderIdToOrder[orderId];

        if (msg.sender != order.buyer) {
            revert YouAreNotBuyer();
        }
        if (order.orderStatus != Completion_status.completed) {
            revert YouCannotDispute(uint32(order.orderStatus));
        }
        dispute[orderId] = true;
        emit BuyerDisputed(orderId);
    }

    // #######################################################################
    // #              TOD FUNCTIONS                                    #
    // #######################################################################
    //To-Do functions:- SolveDispute, onlyGorvernor
    //- function hourly basis logic

    //send a payment to a receiver
    function _sendPayment(uint256 price, address receiver) internal {
        _safeTransfer(address(payToken), receiver, price);
    }

    /**@notice Method for updating platform fee
     @dev Only admin
     @param _platformFee uint16 the platform fee to set
     */
    function updatePlatformFee(uint16 _platformFee) external onlyOwner {
        if (_platformFee > 5e16) revert TooMuchFees();
        platformMaintanenceFee = _platformFee;
        emit UpdatePlatformFee(_platformFee);
    }

    /**
     * Function to calculate platform fees
     *
     */
    function calc_fees(uint256 price) public view returns (uint) {
        return (price * platformMaintanenceFee) / 1e18;
    }

    /**Get the price before subtract the fees.
     *@param  price -a price when fees have been removed
     *@return - the amount before sutraction of fees
     */
    function reverse_price(uint256 price) public view returns (uint) {
        uint percent_we_have = 1e18 - platformMaintanenceFee;
        return (price * 1e18) / percent_we_have;
    }

    /**@notice Method for updating platform fee address
     @dev Only admin
     @param _platformFeeRecipient   address the address to sends the funds to */
    function updatePlatformFeeRecipient(
        address _platformFeeRecipient
    ) external onlyOwner NonZeroAddress(_platformFeeRecipient) {
        feeReceipient = _platformFeeRecipient;
        emit UpdatePlatformFeeRecipient(_platformFeeRecipient);
    }

    ////////////////////////////////
    ///Internal and Private/////////
    ////////////////////////////////

    //Get the current Block timestamp
    function getNow() public view virtual returns (uint256) {
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

    /////SAfe transfer functions////
    function _safeTransfer(address token, address to, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                from,
                to,
                value
            )
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    //User details struct: IsBuyer, IsSeller, Orders, Services, completedOrders,
    //Gorvner: dispute function, solve dispute, nfts and chars like
    //levels:
    // Glassless: just ordinary vote counts once
    //glassed: Vote counts twice
    //binoculars: vote counts three silves disputes if without microscope
    //microscope: vote three, solves disputes
}
