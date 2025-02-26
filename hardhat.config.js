/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require('dotenv').config()
require('@nomiclabs/hardhat-ethers')
module.exports = {
  solidity: '0.8.28',
  settings: {
    viaIR: true,
    optimizer: {
      enabled: true,
      runs: 200,
      details: {
        yulDetails: {
          optimizerSteps: "u",
        },
      },
    },
  }
}
