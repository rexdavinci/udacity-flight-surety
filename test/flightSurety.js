var Test = require('../config/testConfig.js');
const Web3 = require('web3');
const web3 = new Web3('http://localhost:8545');

// const BN = web3.utils.toBN;
const toEth = (amount) => web3.utils.toWei(amount, "ether");
const fromEth = (amount) => web3.utils.fromWei(amount, "ether");

contract('Flight Surety Tests', async (accounts) => {

    const airline1 = accounts[0];
    const airline2 = accounts[1];
    const airline3 = accounts[2];
    const airline4 = accounts[3];
    const airline5 = accounts[4];

    const passenger1 = accounts[5];
  let registrationFee = 0;

  const flight = 'ND1309'; // Course number
  const timestamp = Math.floor(Date.now() / 1000);

  const REGISTRATION_STATUS = {
    0: 'UNREGISTERED',
    1: 'PENDING',
    2: 'REGISTERED',
    3: 'ACTIVE'

  }

  var config;
  before('setup contract', async () => {
    config = await Test.Config(accounts);
    registrationFee = await config.flightSuretyData.REGISTRATION_FEE();
  });
  
  
  /****************************************************************************************/
  /* Operations and Settings                                                              */
  /****************************************************************************************/

  it(`(multiparty) has correct initial isOperational() value`, async function () {

    // Get operating status
    let status = await config.flightSuretyApp.isOperational();
    assert.equal(status, true, "Incorrect initial operating status value");

  });

  it('should have updated the logic contract address', async() => {
    const dataContract =  await config.flightSuretyApp.flightSuretyData()    
    assert.equal(dataContract, config.flightSuretyData.address, "Data contract should have been defined during deploy")
  })
  
  it('(multiparty) can let a registered airline fund and change status to ACTIVE', async() => {
    
    const airlineB4 = await config.flightSuretyData.airlines(airline1)   
    await config.flightSuretyData.fund({ value: registrationFee  })  
    const airlineNow =  await config.flightSuretyData.airlines(airline1) 
    
    const bal = await web3.eth.getBalance(config.flightSuretyData.address)
    const bal2 = await web3.eth.getBalance(config.flightSuretyApp.address)

    assert.equal(REGISTRATION_STATUS[+airlineB4[2]], REGISTRATION_STATUS[2], "First Airline should have REGISTERED status before funding")
    assert.equal(REGISTRATION_STATUS[+airlineNow[2]], REGISTRATION_STATUS[3], "First Airline should have ACTIVE after funding")
  })

  it(`(multiparty) will not let an airline without 'ACTIVE' status call authorizeCaller() function`, async() => { 
    const logicContractB4 =  await config.flightSuretyData.flightSuretyApp()   
    let reverted = false;
    
    try {
      await config.flightSuretyData.authorizeCaller(config.flightSuretyApp.address, { from: airline2 })   
    } catch(e) {
      reverted = true;
    }
    assert.equal(reverted, true, "An inactive airline should not change the app logic address")
    await config.flightSuretyData.authorizeCaller(config.flightSuretyApp.address)   
    const logicContractAfter =  await config.flightSuretyData.flightSuretyApp()   
    assert.equal(logicContractB4, '0x0000000000000000000000000000000000000000', "Logic contract should be zero address before setting")
    assert.notEqual(logicContractAfter, '0x0000000000000000000000000000000000000000', "Logic contract should be updated by ACTIVE airline")
  })

  it(`(multiparty) can block access to setOperatingStatus() for non-Contract Owner account`, async function () {

      // Ensure that access is denied for non-Contract Owner account
      let accessDenied = false;
      try 
      {
          await config.flightSuretyApp.setOperatingStatus(false, { from: airline2 });
      }
      catch(e) {
          accessDenied = true;
      }
      assert.equal(accessDenied, true, "Access not restricted to Contract Owner");
            
  });

  it(`(multiparty) can allow access to setOperatingStatus() by active airline`, async function () {

      // Ensure that access is allowed for Contract Owner account
      let accessDenied = false;
      try 
      {
          await config.flightSuretyData.setOperatingStatus(false);
      }
      catch(e) {
          accessDenied = true;
      }
      assert.equal(accessDenied, false, "Access not restricted to Contract Owner");
      
  });

  it(`(multiparty) can block access to functions using requireIsOperational when operating status is false`, async function () {

      await config.flightSuretyData.setOperatingStatus(false);

      let reverted = false;
      try 
      {
          await config.flightSuretyData.fetchFlightStatus(airline1, flight, departure);
      }
      catch(e) {
          reverted = true;
      }
      assert.equal(reverted, true, "Access not blocked for requireIsOperational");      

      // Set it back for other tests to work
      await config.flightSuretyData.setOperatingStatus(true);

  });

  it('(airline) cannot register an Airline using registerAirline() if it is not (ACTIVE)', async () => {
    
    // ARRANGE
    let reverted = false;

    // ACT
    try {
        await config.flightSuretyApp.registerAirline(airline2, { from: airline2  });
      }
      catch(e) {
        reverted = true
      }
      
      const airline = await config.flightSuretyData.airlines(airline2); 
    
    // ASSERT
    assert.equal(reverted, true, "Airline should not be able to register another airline if it hasn't funded (ACTIVE)");
    assert.equal(REGISTRATION_STATUS[+airline[2]], REGISTRATION_STATUS[0], "Unregistered airlines should have a default registration status corresponding to UNREGISTERED");

  });

  it(`(airline) existing 'ACTIVE' airlines may register a new airline using registerAirline()`, async () => {
    let reverted = false;
    try {
        await config.flightSuretyApp.registerAirline(airline2);
        await activateAndRegister(airline2, airline3,  config.flightSuretyData, config.flightSuretyApp, registrationFee); 
    } catch(e) {
        reverted = true;
    }
    const airline2Status = await config.flightSuretyData.airlines(airline2);
    const airline3Status = await config.flightSuretyData.airlines(airline3);
    //  // ASSERT
    assert.equal(reverted, false, "An airline with funded status should be able to register a new airline");
    assert.equal(REGISTRATION_STATUS[+airline2Status[2]], REGISTRATION_STATUS[3], "Funded Airlines should have an updated status corresponding to ACTIVE");
    assert.equal(REGISTRATION_STATUS[+airline3Status[2]], REGISTRATION_STATUS[2], "Newly registered airlines should have a registered status corresponding to REGISTERED");

  })


  it(`(multiparty) should add new airline registration to registration queue once quorum is established`, async () => {
    let reverted = false;
    try {

        // register airline3
        await activateAndRegister(airline3, airline4, config.flightSuretyData, config.flightSuretyApp, registrationFee); 
        // register airline4
        await activateAndRegister(airline4, airline5, config.flightSuretyData, config.flightSuretyApp, registrationFee); 
        // register airline5 

    } catch(e) {
        reverted = true
    }
    const airline5Status = await config.flightSuretyData.airlines(airline5);
     // ASSERT
    assert.equal(reverted, false, "An airline with funded status should be able to register a new airline");
    assert.equal(REGISTRATION_STATUS[+airline5Status[2]], REGISTRATION_STATUS[1], "Newly registered airline should have status PENDING in a quorum");

  })

  it(`(multiparty) can let quorum add a new airline with PENDING status`, async () => {
    
    await config.flightSuretyApp.registerAirline(airline5, { from: airline2 }) // airline 2 approves
    await config.flightSuretyApp.registerAirline(airline5, { from: airline3 }) // airline 3 approves
    const airline = await config.flightSuretyData.airlines(airline5);
     // ASSERT
    assert.equal(REGISTRATION_STATUS[+airline[2]], REGISTRATION_STATUS[2], "Confirmed airline should have status updated to REGISTERED");

  })

  it(`(multiparty) rejects payment of registration fee if not equal to required amount`, async () => {
    let reverted = false
    try {
        await config.flightSuretyData.fund({ value: toEth("10"), from: airline5 });
    } catch(e) {
        reverted = true;
    }
    assert.equal(reverted, false, `Registration fee must be ${+fromEth(String(+registrationFee))} ETH`);
  })

  it(`(airline) can register a flight`, async () => {

    await config.flightSuretyApp.registerFlight(flight, timestamp, { from: airline2 })
    const flightInfo = await config.flightSuretyApp.getFlightInfo(airline2, flight, timestamp);
    assert.equal(flightInfo[0], true, "Registered flight was not insured correctly");
  })

  it(`(passenger) can buy insurance package on a registered flight`, async () => {
    const amount = toEth("0.2");

    await config.flightSuretyApp.buyInsurance(airline2, flight, timestamp, { from: passenger1, value: amount })
    const isInsured = await config.flightSuretyApp.checkPackage(passenger1, airline2, flight, timestamp)
    assert.equal(isInsured[0], true, "Passenger package should be insured after purchase")
  })
});

const activateAndRegister = async (existingAirline, newAirline, dataContract, appContract, registrationFee) => {
    await dataContract.fund({ value: registrationFee, from: existingAirline, nonce: Number(await getNonce(existingAirline)) });
    await appContract.registerAirline(newAirline, { from: existingAirline, nonce: Number(await getNonce(existingAirline)) });
}


const getNonce = async (account) => web3.eth.getTransactionCount(account)
