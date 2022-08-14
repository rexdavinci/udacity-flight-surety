// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

contract FlightSuretyOracle {


  // Flight status codees
  uint8 private constant STATUS_CODE_UNKNOWN = 0;
  uint8 private constant STATUS_CODE_ON_TIME = 10;
  uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
  uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
  uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
  uint8 private constant STATUS_CODE_LATE_OTHER = 50;

  // Incremented to add pseudo-randomness at various points
  uint8 private nonce = 0;    

  // Fee to be paid when registering oracle
  uint256 public constant ORACLE_REGISTRATION_FEE = 1 ether;

  // Number of oracles that must respond for valid status
  uint256 private constant MIN_RESPONSES = 3;


  struct Oracle {
      bool isRegistered;
      uint8[3] indexes;        
  }

  // Track all registered oracles
  mapping(address => Oracle) private oracles;

  // Model for responses from oracles
  struct ResponseInfo {
      uint8 requestId;
      address requester;                              // Account that requested status
      bool isOpen;                                    // If open, oracle responses are accepted
      mapping(uint8 => address[]) responses;          // Mapping key is the status code reported
                                                      // This lets us group responses and identify
                                                      // the response that majority of the oracles
  }

  // Track all oracle responses
  mapping(bytes32 => ResponseInfo) private oracleResponses;

  // Event fired each time an oracle submits a response
  event OracleReport(address indexed airline, string flight, uint8 status, uint256 indexed timestamp);

  // Event fired when flight status request is submitted
  // Oracles track this and if they have a matching index
  // they fetch data and submit a response
  event OracleRequest(uint8 indexed requestId, address indexed airline, string flight);


  // Register an oracle with the contract
  function registerOracle() external payable {
    // Require registration fee
    require(msg.value >= ORACLE_REGISTRATION_FEE, "Insufficient Registration Fee");

    uint8[3] memory indexes = generateIndexes(msg.sender);

    oracles[msg.sender] = Oracle({ isRegistered: true, indexes: indexes });
  }


  // returns the indexes assigned to an oracle upon registration
  function getMyIndexes() view external returns(uint8[3] memory) {
      require(oracles[msg.sender].isRegistered, "Not registered as an oracle");
      return oracles[msg.sender].indexes;
  }

  // Called by oracle when a response is available to an outstanding request
  // For the response to be accepted, there must be a pending request that is open
  // and matches one of the three Indexes randomly assigned to the oracle at the
  // time of registration (i.e. uninvited oracles are not welcome)
  function _submitOracleResponse(bytes32 flightId, uint8 statusCode) internal returns(bool isPaying, bool verified) {
    require(oracleResponses[flightId].isOpen, "Invalid Submission");

    uint8 requestId = oracleResponses[flightId].requestId;
    uint8[3] memory oracleIDs = oracles[msg.sender].indexes;
    require((oracleIDs[0] == requestId) || (oracleIDs[1] == requestId) || (oracleIDs[2] == requestId), "RequestId Mismatch");


    oracleResponses[flightId].responses[statusCode].push(msg.sender);

    // Information isn't considered verified until at least MIN_RESPONSES
    // oracles respond with the *** same *** information
    verified = oracleResponses[flightId].responses[statusCode].length >= MIN_RESPONSES;
    if (verified) {
    isPaying = statusCode == STATUS_CODE_LATE_AIRLINE;
        oracleResponses[flightId].isOpen = false; // stop oracles from submitting subsequent requests
    }
    return (isPaying, verified);
  }

  // Generate a request for oracles to fetch flight information
  function _fetchFlightStatus(address requester, bytes32 flightId, address airline, string calldata flight) internal {
      uint8 requestId = getRandomIndex(requester);
      oracleResponses[flightId].requester = msg.sender;
      oracleResponses[flightId].isOpen = true;
      oracleResponses[flightId].requestId = requestId;
      emit OracleRequest(requestId, airline, flight);
  } 

  // Returns array of three non-duplicating integers from 0-9
  function generateIndexes(address account) internal returns(uint8[3] memory) {
      uint8[3] memory indexes;
      indexes[0] = getRandomIndex(account);
      
      indexes[1] = indexes[0];
      while(indexes[1] == indexes[0]) {
          indexes[1] = getRandomIndex(account);
      }

      indexes[2] = indexes[1];
      while((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
          indexes[2] = getRandomIndex(account);
      }

      return indexes;
  }

  // Returns array of three non-duplicating integers from 0-9
  function getRandomIndex(address account) internal returns (uint8) {
      uint8 maxValue = 10;

      // Pseudo random number...the incrementing nonce adds variation
      uint8 random = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number - nonce++), account))) % maxValue);

      if (nonce > 250) {
          nonce = 0;  // Can only fetch blockhashes for last 256 blocks so we adapt
      }

      return random;
  }

// endregion
}