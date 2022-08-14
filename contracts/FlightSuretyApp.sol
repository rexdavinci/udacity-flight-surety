// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./FlightSuretyOracle.sol";
import "./utils/Roles.sol";

/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp is FlightSuretyOracle {
    using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)
    using Roles for Roles.Role;


    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/


    IFlightSuretyData public flightSuretyData;

    address private contractOwner;          // Account used to deploy contract
    Roles.Role private authorized;

     event FlightCovered(address indexed airline, string flight, uint256 departure);
     event InsuranceBought(address indexed passenger, address indexed airline, string flight, uint256 amount, bytes32 flightId);
     event DataContractUpdated(address indexed by, address indexed newContract);
     event UpdatedInsurance(bytes32 indexed flightId, uint256 updatedTimestamp);

     event OracleResponse(address airline, string flight, uint256 timestamp, uint8 statusCode, bool verified);

 
    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in 
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational() 
    {
         // Modify to call data contract's status
        require(this.isOperational(), "Contract is currently not operational");  
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier isAuthorized() {
        require(authorized.has(msg.sender), "Unauthorized caller");
        _;
    }

    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    /**
    * @dev Contract constructor
    *
    */
    constructor(IFlightSuretyData _flightSuretyData) {
        address deployer = msg.sender;
        authorized.add(deployer);
        setDataContract(_flightSuretyData);
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/
    // check if contract is operational
    function isOperational() public view returns(bool) {
        return flightSuretyData.isOperational();  // Modify to call data contract's status
    }

    // sets the data contract address of flightSurety
    function setDataContract(IFlightSuretyData _flightSuretyData) public isAuthorized {
        flightSuretyData = _flightSuretyData;
        emit DataContractUpdated(msg.sender, address(_flightSuretyData));
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/  

  
   /**
    * @dev Add an airline to the registration queue
    *
    */   
    function registerAirline(address airline) external requireIsOperational {
        flightSuretyData.registerAirline(msg.sender, airline);
    }

   /**
    * @dev Remove an airline from the contract
    *
    */   
    function unregisterAirline(address airline) external requireIsOperational {
        flightSuretyData.unRegisterAirline(msg.sender, airline);
    }

   /**
    * @dev Register a future flight for insuring.
    *
    */  
    function registerFlight(string calldata flight, uint256 departure) external requireIsOperational {
        address airline = msg.sender;
        bytes32 flightId = getFlightId(airline, flight, departure);
        flightSuretyData.coverFlight(airline, flightId, flight, departure);
        emit FlightCovered(airline, flight, departure);
    }

    // eneble the purchase of flight insurance by passengers
    function buyInsurance(address airline, string calldata flight, uint256 departure) external payable requireIsOperational {
        uint256 amount = msg.value;
        address passenger = msg.sender;
        require(amount > 0, "Amount too low");
        require(amount <= 1 ether, "Maximum is 1 Ether");
        bytes32 flightId = getFlightId(airline, flight, departure);
        flightSuretyData.buy{value: amount}(passenger, flightId);
        emit InsuranceBought(passenger, airline, flight, amount, flightId);
    }

    function isInsuredForFlight(address passenger, bytes32 flightId) internal view returns(bool isInsured) {
        return flightSuretyData.isValidInsurance(passenger, flightId);
    }

    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus(address airline, string calldata flight, uint256 timestamp) external requireIsOperational {
        address requester = msg.sender;
        bytes32 flightId = getFlightId(airline, flight, timestamp);
        bool insured = isInsuredForFlight(requester, flightId);
        require(insured, "Not insured for this flight");
        _fetchFlightStatus(requester, flightId, airline, flight);
    } 

    // Returns the current state of an insured flight
    function getFlightInfo(address airline, string calldata flight, uint256 departure) public view returns(
        bool insured, 
        uint8 statusCode, 
        uint256 updatedTimestamp, 
        bool verified, 
        uint256 potentialPayout,
        bytes32 flightId,
        bool paying
    ) {
        bytes32 _flightId = getFlightId(airline, flight, departure);
        ( insured, statusCode, updatedTimestamp, verified, potentialPayout, paying ) = flightSuretyData.getFlight(_flightId);
        return(insured, statusCode, updatedTimestamp, verified, potentialPayout, _flightId, paying);
    }

    // lets oracles submit a response 
    function submitResponse(address airline, string calldata flight, uint256 timestamp, uint8 statusCode) external requireIsOperational {
        bytes32 flightId = getFlightId(airline, flight, timestamp);
        (bool isPaying, bool verified) = _submitOracleResponse(flightId, statusCode);
        flightSuretyData.updateFlightInsurance(flightId, statusCode, isPaying, verified);
        emit OracleResponse(airline, flight, timestamp, statusCode, verified);
    }

    // Lets passengers claim benefits once they qualify for it
    function payBenefit(address airline, string calldata flight, uint256 departure) external requireIsOperational {
        bytes32 flightId = getFlightId(airline, flight, departure);
        flightSuretyData.pay(msg.sender, flightId);
    }

    // computes the flightId for a flight given
    function getFlightId(address airline, string calldata flight, uint256 timestamp) pure internal returns(bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }
    
    // checks the insurance package status for a passenger
    function checkPackage(address passenger, address airline, string calldata flight, uint256 departure) view public returns(bool isInsured, bytes32 flightId) {
        flightId = getFlightId(airline, flight, departure);
        return (flightSuretyData.isValidInsurance(passenger, flightId), flightId);
    }

    // shows the potential benefit a passenger can get on a specific flight
    function potentialBenefitForFlight(address airline, string calldata flight, uint256 departure) external view returns(uint256 potentialBenefit) {
        bytes32 flightId = getFlightId(airline, flight, departure);
        return flightSuretyData.getPotentialBenefit(msg.sender, flightId);
    }
}   


interface IFlightSuretyData {
    function buy(address passenger, bytes32 flightId) external payable;
    function coverFlight(address airline, bytes32 flightId, string calldata flight, uint256 departure) external;
    function getFlight(bytes32 flightId) external view returns(
        bool insured, 
        uint8 statusCode, 
        uint256 updatedTimestamp, 
        bool oracleVerifed, 
        uint256 potentialPayout,
        bool paying
    );
    function isValidInsurance(address passenger, bytes32 flightId) external view returns(bool);
    function updateFlightInsurance(bytes32 flightId, uint8 statusCode, bool isPaying, bool verified) external;
    function hasPackage(address passenger, bytes32 flightId) view external returns(bool isInsured, uint256 cost, uint256 received);
    function getPotentialBenefit(address passenger, bytes32 flightId) external view returns(uint256);
    function unRegisterAirline(address requester, address airline) external;
    function registerAirline(address requester, address airline) external;
    function pay(address passenger, bytes32 flightId) external;
    function isOperational() external view returns(bool);
    function fund() external payable;
}   
