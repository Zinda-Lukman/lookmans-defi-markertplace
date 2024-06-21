//SPDX-lincence-Identifintier: MIT
/**
 *  - create a service with price
 *  - list it
 *  -unlist it
     - negotiate with price
*/

pragma solidity 0.8.19;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract service_markketplace is OwnableUpgradeable, ReentrancyGuardUpgradeable{
 // Our Structure Types
 // @notice Structure for listed items
  enum Completion_status{
      created,
       cancelled, 
      completed, 
      buyerImplemented
    }

    struct Listing {
        uint256 quantity;
        address payToken;
        uint256 service;
        uint256 startingTime;
    }

    //@notice order struct
    struct order {
      address buyer;
      address seller;
      Listing service;
      uint256 UsdPrice;
      Completion_status orderStatus;
      uint256 allowedTime;
    }
    
  //@notice Events for the contract

    event ItemListed(
        address indexed owner,
        uint256 serviceId,
        uint256 quantity,
        address payToken,
        uint256 startingTime
    );

    event ItemUpdated(
        address indexed owner,
        uint256 serviceId,
        address payToken,
        uint256 _newQuantity 
    );

    event ListingCanceled(
     uint256 serviceId, 
     Address indexed seller 
    );
    
    event service_created(
      uint256 serviceId;
      address seller;
      );
    event orderCreatedBySeller(
      uint256 orderId, 
      address Buyer
      );
    event orderImplementedByBuyer(
      uint256 orderId, 
      address buyer, 
      uint256 allowedTime
      );
    event order Cancelled (
      uint256 orderId
      );
    event orderCompleted (
      uint256 orderId
      );
    
   event UpdatePlatformFee(uint16 platformFee);
   event UpdatePlatformFeeRecipient(address payable platformFeeRecipient);
   
  //contract Variables 
  /// @notice Platform fee
  uint16 public platformMaintanenceFee;
  //@notice service start
  uint256 public services_count = 0;
  //@notice orders start
  uint256 public orders_count = 0;
  
   //Mappings
    /// @notice service -> seller
    mapping(uint256 => address)) public seller;

    /// @notice serviceid => Listing
    mapping(uint256  => Listing) public listings;

    //@notice buyer => orders
    mapping(address => uint256[]) public buyer_to_orders; 

    ///@notice service => owner
    mapping(uint256 => address)  public service_to_owner;

    ///@notice seller => service 
    mapping (address => uint256[]) public seller_to_services;
    //@notice order => agreed price
    mapping(uint256 => Order) public orderIdToOrder;
    //@notice order to buyer
    mapping(uint256 => address) public orderToBuyer;

modifier isListed(
        uint256 _service
    ) {
        Listing memory listing = listings[_service];
        require(listing.quantity > 0, "not listed item");
        _;
    }

    modifier notListed(
        uint256 _service,
        address _owner
    ) {
        Listing memory listing = listings[_service];
        require(listing.quantity == 0, "already listed");
        _;
    }

    modifier validListing(
        address seller,
        uint256 _service,
    ) {
        Listing memory listedItem = listings[seller][_service];

        _validOwner(seller , listedItem.quantity);

        require(_getNow() >= listedItem.startingTime, "item not buyable");
        _;
    }
    
    /// @notice Contract initializer
    function initialize(address payable _feeRecipient, uFint16 _platformFee)
        public
        initializer
    {
        platformFee = _platformFee;
        feeReceipient = payable _feeRecipient;

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
    }
    //@notice method for creating a new service 
    function createService() public external nonReentrant {
      services_count = services_count + 1;
      service_to_owner[services_count] = payable msg.sender;
      seller_to_services[msg.sender].push(services_count);
      
      emit service_created(
      uint256 services_count;
      address msg.sender;
      );
    } 
    
    /// @notice Method for listing a service
    /// @param _serviceId of the service
    /// @param _quantity amount to quantity of services a seller can handle 
    /// @param _payToken Paying token
    function listService(
    /// @param _startingTime scheduling for a future sale
        uint256 _serviceId,
        uint256 _quantity,
        address _payToken,
        uint256 _startingTime
    ) external notListed(_serviceId, msg.sender()) {
        
        _validPayToken(_payToken);
        _validOwner( _serviceId, msg. sender);
        listings[_serviceId] = Listing(
            _quantity,
            _payToken,
            _serviceId, 
            block.timestamp + _startingTime
        );
        emit ItemListed(
            msg.sender(),
            _serviceId,
            _quantity,
            _payToken, 
            _startingTime
        );
    }

    /// @notice Method for canceling listed NFT
    function cancelListing( uint256 _serviceId)
        external
        nonReentrant
        isListed(serviceId) 
    {
        _cancelListing(_serviceId, msg.sender);
    }

    /// @notice Method for updating listing of a service
    /// @param _serviceId of the service
    /// @param _quantity amount to quantity of services a seller can handle 
    /// @param new _payToken Paying token
    /// @param new _startingTime scheduling for a future sale
    function updateListing(
        uint256 _serviceId,
        address _payToken,
        uint256 _newQuantity
    ) external nonReentrant isListed(_serviceId) {
        Listing storage listedItem = listings[_serviceId];

        _validOwner(_serviceId, msg.sender);

        _validPayToken(_payToken);

        listedItem.payToken = _payToken;
        listedItem.quantity = _newQuantity;
        listings[_serviceId] = listedItem;
        emit ItemUpdated(
            msg.sender,
            _serviceId,
            _payToken,
            _newQuantity
        );
    }
   function addOrderPrice(uint256 serviceId, uint256 priceInUsd, address buyer) public _validOwner(serviceId, msg.sender) nonReentrant {
     orders_count = orders_count + 1;
     orderIdToOrder[orders_count] = Order{ 
      payable buyer, 
      payable msg.sender,
      listings[serviceId], 
      priceInUsd, 
      Completion_status.created, 
      0
    }
    emit orders_count(
      orders_count, 
      buyer
      );
   }
   //@notice function to allow buyer to complete order creation. 
   //Reverts:-
   //   -When message sender is not buyer
   //   -When value is not the set priceInUsd
   //   - When order does not exist 
   //info:-
   function completeOrderCreation(uint256 orderId, uint256 allowedTime) public payable {
     require(orderIdToOrder[orderId] != 0, "Order does not exist")
     
     require(msg.value == orderIdToOrder[orderId].priceInUsd, "Insufficient required funds")
     require(msg.sender == orderIdToOrder[orderId].buyer, "You are this order's buyer");
     
     orderIdToOrder[orderId].orderStatus = Completion_status.buyerImplemented;
     orderIdToOrder[orderId].allowedTime = block.timestamp + allowedTime days
     
     emit orderImplementedByBuyer(
       orderId, 
       msg.sender,
       allowedTime
       );
   }
   function cancelOrder(uint256 orderId) public {
     require(orderIdToOrder[orderId] != 0, "Order does not exist")
    bool validSender =  msg.sender == orderIdToOrder[orderId].buyer || msg.sender == orderIdToOrder[orderId].seller;
    bool alreadyCompleted = orderIdToOrder[orderId].orderStatus != Completion_status.completed;
     require( validSender, "You are this order's buyer or sender");
     require(alreadyCompleted, "Order already completed");
     
     orderIdToOrder[orderId].orderStatus = Completion_status.cancelled;
    
    emit orderCancelled(
      orderId
      );
     
   }
   function completeOrder(uint256 orderId) public {
     require(orderIdToOrder[orderId] != 0, "Order does not exist");
     
    bool validSender =  msg.sender == orderIdToOrder[orderId].buyer;
    
    bool alreadyCompleted = orderIdToOrder[orderId].orderStatus != Completion_status.completed;
    
     require( validSender, "You are this order's buyer");
     require(alreadyCompleted, "Order already completed");
     bool success = sendPayment(orderIdToOrder[orderId]. priceInUsd, 
    orderIdToOrder[orderId].buyer);
    
    if(success) {
      
     orderIdToOrder[orderId].orderStatus = Completion_status.completed;
    
     emit orderCompleted(orderId);
    } 
      }
      
    function sendPayment(uint256 price, address payable receiver) internal {
      return true;
    }
   
   /**
     @notice Method for getting price for pay token
     @param _payToken Paying token
     */
    function getPrice(address _payToken) public view returns (int256) {
        int256 unitPrice;
        uint8 decimals;
        
        if (decimals < 18) {
            unitPrice = unitPrice * (int256(10)**(18 - decimals));
        } else {
            unitPrice = unitPrice / (int256(10)**(decimals - 18));
        }

        return unitPrice;
    }
   /**
     @notice Method for updating platform fee
     @dev Only admin
     @param _platformFee uint16 the platform fee to set
     */
   function updatePlatformFee(uint16 _platformFee) external onlyOwner {
        platformFee = _platformFee;
        emit UpdatePlatformFee(_platformFee);
    }

    /**@notice Method for updating platform fee address
     @dev Only admin
     @param _platformFeeRecipient payable address the address to sends the funds to */
    function updatePlatformFeeRecipient(address payable _platformFeeRecipient)
        external
        onlyOwner
    {
        feeReceipient = _platformFeeRecipient;
        emit UpdatePlatformFeeRecipient(_platformFeeRecipient);
    }


    ////////////////////////////////
    ///Internal and Private/////////
    ////////////////////////////////
    function _getNow() internal view virtual returns (uint256) {
        return block.timestamp;
    }
    function _validPayToken(address _payToken) internal {
        require(
            _payToken == address(0) ||
                (addressRegistry.tokenRegistry() != address(0) &&
                    IFantomTokenRegistry(addressRegistry.tokenRegistry())
                        .enabled(_payToken)),
            "invalid pay token"
        );
    }
    function _validOwner(
        uint256 _service,
        address _owner
    ) internal {
            require(service_to_owner[_service] == _owner, "not owning service");
    }
    function _validPayToken(address _payToken) internal {
        require(
            _payToken == address(0) ||
                (addressRegistry.tokenRegistry() != address(0) &&
                    IFantomTokenRegistry(addressRegistry.tokenRegistry())
                        .enabled(_payToken)),
            "invalid pay token"
        );
    }
function _cancelListing(
        uint256 _serviceId,
        address _owner
    ) private {
        _validOwner(serviceId, _owner);
        delete(listings[_serviceId]);
        emit ListingCanceled(serviceId, _owner);
    }
}

    
}