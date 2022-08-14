const Web3 = require('web3')
const web3 = new Web3('http://localhost:8545');

const FlightSuretyApp = artifacts.require("FlightSuretyApp");
const FlightSuretyData = artifacts.require("FlightSuretyData");
const fs = require('fs');

module.exports = function(deployer) {
    deployer.deploy(FlightSuretyData) // deploy data
    .then((dataInstance) => {
        return dataInstance.fund({ value: web3.utils.toBN(10e18) }) // fund to activate airline account
        .then(() => {
            return deployer.deploy(FlightSuretyApp, dataInstance.address) // deploy logic
            .then((appInstance) => {
                return dataInstance.authorizeCaller(appInstance.address) // authorize logic
                // .then(() => {
                //     const flight = 'ND1309'; 
                //     const timestamp = Math.floor(Date.now() / 1000);
                //     return appInstance.registerFlight(flight, timestamp) // register flight
                    .then(() => {
                        let config = {
                            localhost: {
                                url: 'http://localhost:8545',
                                dataAddress: FlightSuretyData.address,
                                appAddress: FlightSuretyApp.address
                            }
                        }
                        fs.writeFileSync(__dirname + '/../src/dapp/config.json',JSON.stringify(config, null, '\t'), 'utf-8');
                        fs.writeFileSync(__dirname + '/../src/server/config.json',JSON.stringify(config, null, '\t'), 'utf-8');
                    })
                })

                // web3.eth.getAccounts((err, accts) => {

                // })
            })

        })
}

// module.exports = function(deployer) {
//     deployer.deploy(FlightSuretyData)
//     .then((dataInstance) => {
//         return dataInstance.fund({ value: web3.utils.toBN(10e18)})
//         .then(() => {
//             return deployer.deploy(FlightSuretyApp, dataInstance.address)
//             .then((appInstance) => {
//                 const flight = 'ND1309'; // Course number
//                 const timestamp = Math.floor(Date.now() / 1000);

//                 web3.eth.getAccounts((err, accts) => {
//                     return appInstance.registerFlight(flight, timestamp)
//                     .then(() => {
//                         // return appInstance.registerFlight()
//                         return dataInstance.authorizeCaller(appInstance.address).then(() => {
//                             let config = {
//                                 localhost: {
//                                     url: 'http://localhost:8545',
//                                     dataAddress: FlightSuretyData.address,
//                                     appAddress: FlightSuretyApp.address
//                                 }
//                             }
//                             fs.writeFileSync(__dirname + '/../src/dapp/config.json',JSON.stringify(config, null, '\t'), 'utf-8');
//                             fs.writeFileSync(__dirname + '/../src/server/config.json',JSON.stringify(config, null, '\t'), 'utf-8');
//                         })
//                     })

//                 })
//             })

//         })
//     })
// }