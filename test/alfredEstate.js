const AlfredEstate = artifacts.require("AlfredEstate");

contract("AlfredEstate", accounts => {
    it("should be owned by the first account", async () => {
        let instance = await AlfredEstate.deployed();
        let owner = await instance.owner.call();
        assert.equal(
            owner,
            accounts[0],
            "Not owned by the first account"
        );
    });

});
