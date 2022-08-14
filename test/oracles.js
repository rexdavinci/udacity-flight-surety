
var Test = require('../config/testConfig.js');
var Web3 = require('web3');
var web3 = new Web3('http://localhost:8545');

const toEth = (amount) => web3.utils.toWei(amount, "ether");
const fromEth = (amount) => web3.utils.toWei(amount, "ether");

contract('Oracles', async (accounts) => {

  const flight = 'ND1309'; // Course number
  const flight2 = 'ND1309x';
  const timestamp = Math.floor(Date.now() / 1000);

  const MIN_RESPONSES = 3;
  let oracleRegistrationFee;
  let requestId

  // Watch contract events
  const STATUS_CODE_UNKNOWN = 0;
  const STATUS_CODE_ON_TIME = 10;
  const STATUS_CODE_LATE_AIRLINE = 20;
  const STATUS_CODE_LATE_WEATHER = 30;
  const STATUS_CODE_LATE_TECHNICAL = 40;
  const STATUS_CODE_LATE_OTHER = 50;

  const airline = accounts[0]
  const passenger1 = accounts[5]
  const passenger2 = accounts[6]


  const statusCodes = {
    0: "UNKNOWN",
    10: "ON TIME",
    20: "LATE AIRLINE",
    30: "LATE WEATHER",
    40: "LATE TECHNICAL",
    50: "LATE OTHER"
  }


  // airlines (accounts[0] to accounts[4]), reserved passengers(accounts[5] to accounts[9]) => 10 accounts
  const TEST_ORACLES_COUNT = 50; // loops throughout the test will start from accounts[10] - accounts[50]
  var config;
  before('setup contract', async () => {
    config = await Test.Config(accounts);
    await config.flightSuretyData.fund({ value: toEth("10") });
    await config.flightSuretyData.authorizeCaller(config.flightSuretyApp.address);
    oracleRegistrationFee = await config.flightSuretyApp.ORACLE_REGISTRATION_FEE();
    await config.flightSuretyApp.registerFlight(flight, timestamp);
    await config.flightSuretyApp.registerFlight(flight2, timestamp);
    await config.flightSuretyApp.buyInsurance(airline, flight, timestamp, { from: passenger1, value: toEth("0.5") });
    await config.flightSuretyApp.buyInsurance(airline, flight2, timestamp, { from: passenger2, value: toEth("0.3") });
  });

  
  it('should get the accurate amount for oracle fee registration', async() => {
    oracleRegistrationFee = await config.flightSuretyApp.ORACLE_REGISTRATION_FEE();
    assert.notEqual(+oracleRegistrationFee, 0, 'Oracle registration fee should not be 0');
  })
  
  it('can register oracles', async () => {
    let reverted = false
    // ACT
    for(let a = 10; a < TEST_ORACLES_COUNT; a++) {     // start counting from account - 10  to cater for airlines' accounts and passengers' accounts
      try {
        await config.flightSuretyApp.registerOracle({ from: accounts[a], value: oracleRegistrationFee });
        const indexes = await config.flightSuretyApp.getMyIndexes({ from: accounts[a] });
        assert.equal(indexes.length, 3, "Registered oracle should have an index of 3 numbers");
      } catch(e) {
        console.log(e.message)
        reverted = true
      }
      assert.equal(reverted, false, "Successfully registered oracles should have indexes")
    }
  });

  it('can get indexes for registered oracle', async() => {
    try {
      await config.flightSuretyApp.getMyIndexes({ from: accounts[50] });
    } catch(e) {
      reverted = true
    }
    assert.equal(reverted, true, "Unregistered oracle should not have indexes")
  })

  it('(passenger) can request flight status if bought', async () => {
    // ARRANGE
  
    // ACT
    // Submit a request for oracles to get status information for a flight
    const tx = await config.flightSuretyApp.fetchFlightStatus(airline, flight, timestamp, { from: passenger1 }); 

    requestId = +tx.logs[0].args['requestId']
    assert.equal(tx.logs[0].event, 'OracleRequest', "request should emit OracleRequest")   
    assert.equal(tx.logs[0].args['flight'], flight, `event argument 'flight' should be ${flight}`)
    assert.equal(tx.logs[0].args['airline'], airline, `event argument 'airline' should be ${airline}`)
  });

  it('(oracle) can submit flight status', async () => {
    // ARRANGE
    let acceptedSubmissions = 0;

    // ACT
    // Since the Index assigned to each test account is opaque by design
    // loop through all the accounts and for each account, all its Indexes (indices?)
    // and submit a response. The contract will reject a submission if it was
    // not requested so while sub-optimal, it's a good test of that feature
    for(let a = 10; a < TEST_ORACLES_COUNT; a++) { 
      // Get oracle in formation
      let oracleIndexes = await config.flightSuretyApp.getMyIndexes.call({ from: accounts[a] });
      oracleIndexes = oracleIndexes.map(idx => +idx);
      try {
        // Submit a response...it will only be accepted if this oracle is allowed to submit corresponding requestId
        const tx = await config.flightSuretyApp.submitResponse(airline, flight, timestamp, STATUS_CODE_ON_TIME, 
          { from: accounts[a], nonce: await web3.eth.getTransactionCount(accounts[a]) }
          );
          console.log(`\t\tMatched requestId: ${requestId} in oracle's [${oracleIndexes}] Indexes`)
          console.log(`\t\tSubmitted by: ${accounts[a].slice(0, 8)}xxx `)
          acceptedSubmissions++;
          const result = tx.logs[0].args;
          console.log(`\t
            Oracle Response Available: 
            requestId: '${requestId}', status: ${statusCodes[+result.statusCode]}, flight: ${result.flight}, 
            timestamp: ${+result.timestamp}, verified: ${result.verified ? 'VERIFIED' : 'UNVERIFIED'}\n\n
            `
          );
        assert.equal(requestId, oracleIndexes[oracleIndexes.indexOf(requestId)], "Oracle with matching index should be accepted")
      } catch(e) {}
    }

    if(acceptedSubmissions >= MIN_RESPONSES) {
    try {
          const info = await config.flightSuretyApp.getFlightInfo(airline, flight, timestamp);
          assert.equal(info.paying, false, "When airplane is on time, there should be no payment for insurance benefits")
      } catch(e) {}
    }
  });

  it('(passenger) can claim insurance benefit if airline is late', async () => {
    // ARRANGE
    const balB4 = await web3.eth.getBalance(passenger2)

    // Submit a request for oracles to get status information for a flight    
    await config.flightSuretyApp.fetchFlightStatus(airline, flight2, timestamp, { from: passenger2 });

    let acceptedSubmissions = 0;

    // ACT
    // Since the Index assigned to each test account is opaque by design
    // loop through all the accounts and for each account, all its Indexes (indices?)
    // and submit a response. The contract will reject a submission if it was
    // not requested so while sub-optimal, it's a good test of that feature
    for(let a = 10; a < TEST_ORACLES_COUNT; a++) {
      let oracleIndexes = await config.flightSuretyApp.getMyIndexes.call({ from: accounts[a] });
      oracleIndexes = oracleIndexes.map(idx => +idx)
      try {
        // Submit a response...it will only be accepted if this oracle is allowed to submit corresponding requestId
        await config.flightSuretyApp.submitResponse(airline, flight2, timestamp, STATUS_CODE_LATE_AIRLINE, 
          { from: accounts[a], nonce: await web3.eth.getTransactionCount(accounts[a]) });
          acceptedSubmissions++
      } catch(e) {}
    }


    if(acceptedSubmissions >= MIN_RESPONSES) {
      // insurance should be paid
      await config.flightSuretyApp.payBenefit(airline, flight2, timestamp, { from: passenger2 });
      const bal = await web3.eth.getBalance(passenger2)
      const paid = +bal > +balB4
      assert.equal(paid, true, "New balance should be greater than previous after benefit payment")
      
      // should not allow dual withdrawal
      let reverted = false
      
      try {
        // insurance should be paid again
        await config.flightSuretyApp.payBenefit(airline, flight2, timestamp, { from: passenger2 });
        const balNow = await web3.eth.getBalance(passenger2)
        const paidAgain = +balNow > +bal;

        assert.equal(paidAgain, false, "Benefit should not be paid twice")
      } catch (e) {
        reverted = true
      }

      assert.equal(reverted, true, "Should not claim benefit after it has been paid")
    }
  });

});


const getNonce = async (account) => web3.eth.getTransactionCount(account)