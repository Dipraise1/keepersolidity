const TokenLock = artifacts.require("TokenLock");

module.exports = function(deployer) {
  deployer.deploy(TokenLock, "ADDRESS_OF_YOUR_ERC20_TOKEN");
};