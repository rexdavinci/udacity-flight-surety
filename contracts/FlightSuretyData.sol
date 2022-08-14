// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner;                                      // Account used to deploy contract
    bool private operational = true;                                    // Blocks all state changes throughout the contract if false
    uint256 public activeAirlines;
    uint256 public registeredAirlines;
    uint256 constant QUORUM = 4;
    uint256 public minimumVotes = activeAirlines.div(2).add(1); // 1 more than half the total
    uint256 public insuranceBenefitMultiplier = 3; // 1.5x amount paid
    uint256 public insuranceBenefitDivisor = 2; // 1.5x amount paid
    uint256 public availableFunds;
    uint256 constant public REGISTRATION_FEE = 10 ether;

    address public flightSuretyApp;

    enum Registration { UNREGISTERED, PENDING, REGISTERED, ACTIVE }
    enum VoteKind { ABSTAIN, FOR, AGAINST }
    enum ResolutionKind { MINIMUM_DEPOSIT, MINIMUM_VOTES }


    event AirlineAdded(address indexed airline, bool indexed byQuorum);
    event AirlineRemoved(address indexed airline, bool indexed byQuorum);
    event Deposit(address indexed airline, uint256 indexed amount, uint8 indexed status);

    event InsurancePaid(address indexed passenger, address indexed airline, string flight, uint256 amount);

    struct Vote {
        bool voted;
        VoteKind voteKind;
    }

    struct InsuredFlight {
        bool insured;
        bool paying;
        address airline;
        string flight;
        uint8 statusCode;
        uint256 departure;
        uint256 updatedTimestamp; 
        uint256 potentialPayout;
        bool verified;
    }

    struct Airline {
        mapping(address => Vote) votes;
        uint256 votesFor; 
        uint256 votesAgainst; 
        Registration status;
    }

    struct PassengerBenefit {
        bool insured;
        uint256 benefit;
    }

    mapping(address => Airline) public airlines;
    mapping(bytes32 => InsuredFlight) private coveredFlights;
    mapping(address => mapping(bytes32 => PassengerBenefit)) insurancePackages; // passenger-address -> flightId -> packageBenefit
    mapping(address => bool) public isAirline;

    modifier canMakeClaim(bytes32 flightId, address passenger) {
        // did passenger buy insurance packagefor this flight?
        require(insurancePackages[passenger][flightId].insured, "Invalid Claim");
        // does passenger have unclaimed benefits for this particular flight?
        require(insurancePackages[passenger][flightId].benefit > 0, "Already Claimed Or Not Available");
        _;
    }

    modifier flightIsCovered(bytes32 flightId) {
        require(coveredFlights[flightId].insured, "Flight Not Covered");
        _;
    }

    modifier isAuthorizedCaller() {
        require(msg.sender == flightSuretyApp, "Unauthorized Caller");
        _;
    }

    modifier isActiveAirline(address airline) {
        require(airlines[airline].status == Registration.ACTIVE, "Unauthorized / Inactive Airline");
        _;
    }


    /********************************************************************************************/
    /*                                     EVENT DEFINITIONS                                    */
    /********************************************************************************************/


    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor() {
        airlines[msg.sender].status = Registration.REGISTERED; // register deployer as first airline
    }

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
        require(operational, "Contract is currently not operational");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    // modifier requireContractOwner()
    // {
    //     require(msg.sender == contractOwner, "Caller is not contract owner");
    //     _;
    // }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /** @dev Recalculate the required minim votes when an airline is registered 
    *   or unregistered - will be 1 more higher than average number of active airlines
     */

    // calculates the minimum votes required to implement a decision by quorum
    function _recomputeMinimumVotes() internal {
        minimumVotes = activeAirlines.div(2).add(1);
    }

    // sets the address of the logic contract
    function authorizeCaller(address _flightSuretyApp) public isActiveAirline(msg.sender) {   
        flightSuretyApp = _flightSuretyApp;
    }  


    // ratifies the action of quorum regarding registration of another airline by the quorum
    function _executeAirlineAction(Airline storage airline, Registration status) internal {
        // reset votes covers kicking out after registration too
        airline.votesFor = 0;
        airline.votesFor = 0;
        // update airline's registration status
        airline.status = status;
    }

    /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */      
    function isOperational() public view returns(bool) {
        return operational;
    }

    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    * Any active airline can set mode in case of an emergency, it is assumed that airlines
    * will only register other reputable airlines
    */    
    function setOperatingStatus(bool mode) external isActiveAirline(msg.sender) {
        operational = mode;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    // lets an airline create an insurance cover for a flight
    function coverFlight(address airline, bytes32 flightId, string calldata flight, uint256 departure) external isAuthorizedCaller isActiveAirline(airline) {
        require(!coveredFlights[flightId].insured, "Already Covered");
        require(availableFunds >= insuranceBenefitMultiplier.mul(1 ether), "Funds Low, Fund Contract"); // should cater for at least 1 ether insurance
        coveredFlights[flightId] = InsuredFlight(true, false, airline, flight, 0, departure, block.timestamp, 0, false);
    }

    // gets the information of an insured flight
    function getFlight(bytes32 flightId) external view returns(bool insured, uint8 statusCode, uint256 updatedTimestamp, bool oracleVerifed, uint256 potentialPayout, bool paying, uint256 departure) {
        InsuredFlight memory flight = coveredFlights[flightId];
        return (flight.insured, flight.statusCode, flight.updatedTimestamp, flight.verified, flight.potentialPayout, flight.paying, flight.departure);
    }

    // updates the value of an insurance based on the response of an oracle as submitted by the logic contract
    function updateFlightInsurance(bytes32 flightId, uint8 statusCode, bool isPaying, bool verified) external requireIsOperational isAuthorizedCaller {
        coveredFlights[flightId].updatedTimestamp = block.timestamp;
        coveredFlights[flightId].statusCode = statusCode;
        coveredFlights[flightId].paying = isPaying;
        coveredFlights[flightId].verified = verified;
        if(verified && !isPaying) { // return funds to pool
            availableFunds = availableFunds.add(coveredFlights[flightId].potentialPayout);
            coveredFlights[flightId].potentialPayout = 0;
        }
    }

    // shows the potential benefit a passenger can get on a specific flight
    function getPotentialBenefit(address passenger, bytes32 flightId) isAuthorizedCaller external view returns(uint256) {
        InsuredFlight memory flight = coveredFlights[flightId];
        if(flight.verified && !flight.paying) {
            return 0;
        }
        // return potentialBenefits[passenger][flightId];
        return insurancePackages[passenger][flightId].benefit;
    }

   /**
    * @dev Add an airline to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */   
    function registerAirline(address requester, address airline) external isAuthorizedCaller {
        require(airlines[requester].status == Registration.ACTIVE, "Unauthorized Airline");
        Airline storage _airline = airlines[airline];
        require(uint8(_airline.status) <= uint8(Registration.PENDING), "Active / Registered Airline");
        bool success;

        if(activeAirlines < QUORUM) {
            success = true;
        } else {
            // propose
            bool voted = _airline.votes[requester].voted;
            // has voted before
            if(voted) {
                require(_airline.votes[requester].voteKind != VoteKind.FOR, "Previously Approved Request");
                // reduce vote 'AGAINST' count
                _airline.votesAgainst = _airline.votesAgainst.sub(1);
            }

            _airline.votes[requester].voted = true;
            _airline.votesFor = _airline.votesFor.add(1);
            _airline.votes[requester].voteKind = VoteKind.FOR;

            _airline.status = Registration.PENDING;
            // does it satisfy quorum requirement
            if(_airline.votesFor == minimumVotes) {
                success = true;
            }
        }

        if(success) {
            _executeAirlineAction(_airline, Registration.REGISTERED);
            emit AirlineAdded(airline, activeAirlines >= QUORUM);
        }
    }

   /**
    * @dev Unregister an airline from the available airlines
    *      Can only be called from FlightSuretyApp contract
    *
    */   
    function unRegisterAirline(address requester, address airline) external isAuthorizedCaller{
        require(airlines[requester].status == Registration.ACTIVE, "Unauthorized Airline");
        Airline storage _airline = airlines[airline];
        require(uint8(_airline.status) >= uint8(Registration.REGISTERED), "Unregistered / Invalid Airline");
        bool success;

        if(activeAirlines < QUORUM) {
            success = true;
        } else {
            // propose
            bool voted = _airline.votes[requester].voted;
            // has voted before
            if(voted) {
                require(_airline.votes[requester].voteKind != VoteKind.AGAINST, "Previously Approved Request");
                // reduce vote 'FOR' count
                _airline.votesFor = _airline.votesFor.sub(1);
            }

            _airline.votes[requester].voted = true;
            _airline.votesAgainst = _airline.votesAgainst.add(1);
            _airline.votes[requester].voteKind = VoteKind.AGAINST;

            // does it satisfy quorum requirement
            if(_airline.votesAgainst == minimumVotes) {
                success = true;
            }
            // update registration status
            _airline.status = Registration.PENDING;

        }

        if(success) {
            //execute
            _executeAirlineAction(_airline, Registration.UNREGISTERED);
            emit AirlineRemoved(airline, activeAirlines >= QUORUM);
        }
    }

   /**
    * @dev Buy insurance for a flight
    *
    */   
    function buy(address passenger, bytes32 flightId) external payable isAuthorizedCaller flightIsCovered(flightId) {
        require(!coveredFlights[flightId].verified, "Flight Already Concluded!");
        uint256 potentialBenefit = potentialBenefitCalculator(msg.value);
        require(availableFunds >= potentialBenefit, "Inadequate Funds For Request Amount");
        availableFunds = availableFunds.sub(potentialBenefit); // deduct the amount from what's available
        InsuredFlight storage flight = coveredFlights[flightId];

        flight.potentialPayout = flight.potentialPayout.add(potentialBenefit);
        insurancePackages[passenger][flightId].benefit = potentialBenefit;
        insurancePackages[passenger][flightId].insured = true;
    }

    // computes the benefit based on a given amount 
    function potentialBenefitCalculator(uint256 amount) public view returns(uint256) {
        return (amount.mul(insuranceBenefitMultiplier)).div(insuranceBenefitDivisor);
    }

    // checks if the package of the passenger is insured 
    function isValidInsurance(address passenger, bytes32 flightId) external view isAuthorizedCaller returns(bool isInsured) {
        return insurancePackages[passenger][flightId].insured;
    }

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay(address passenger, bytes32 flightId) external isAuthorizedCaller canMakeClaim(flightId, passenger) {
        InsuredFlight memory flight = coveredFlights[flightId];
        require((flight.paying && flight.verified), "Ineligible To Claim"); // is flight paying
        uint256 amount = insurancePackages[passenger][flightId].benefit;
        insurancePackages[passenger][flightId].benefit = 0;

        coveredFlights[flightId].potentialPayout = flight.potentialPayout.sub(amount);

        payable(passenger).transfer(amount);
        emit InsurancePaid(passenger,flight.airline, flight.flight, amount);
    }

   /**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */   
    function fund() requireIsOperational public payable {
        address airline = msg.sender;
        require(uint8(airlines[airline].status) >= uint8(Registration.REGISTERED), "Unregistered Airline"); // either registered or already active
        uint256 amount = msg.value;
        if(airlines[airline].status == Registration.REGISTERED) {
            require(amount == REGISTRATION_FEE, "Inaccurate Fee Amount"); // only if airline is paying the first time
            activeAirlines = activeAirlines.add(1);
            _recomputeMinimumVotes();
        }
        airlines[airline].status = Registration.ACTIVE;
        availableFunds = availableFunds.add(amount);
        emit Deposit(airline, amount, uint8(airlines[airline].status));
        
    }
    /**
    * @dev Fallback function for funding smart contract.
    *
    */
    receive() external  payable {
        fund();
    }


}

