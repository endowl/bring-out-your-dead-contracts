var BringOutYourDead = artifacts.require("BringOutYourDead");
var BringOutYourDeadFactory = artifacts.require("BringOutYourDeadFactory");

module.exports = function(deployer) {
    deployer.deploy(BringOutYourDead);
    deployer.deploy(BringOutYourDeadFactory);
};
