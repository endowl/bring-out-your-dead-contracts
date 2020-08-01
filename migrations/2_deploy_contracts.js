var AlfredEstate = artifacts.require("AlfredEstate");
var AlfredEstateFactory = artifacts.require("AlfredEstateFactory");

module.exports = function(deployer) {
    deployer.deploy(AlfredEstate);
    deployer.deploy(AlfredEstateFactory);
};
