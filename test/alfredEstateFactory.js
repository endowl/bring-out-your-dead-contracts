const AlfredEstateFactory = artifacts.require("AlfredEstateFactory");

contract("AlfredEstateFactory", async accounts => {
    it("should create an estate at the address predicted", async () => {
        let instance = await AlfredEstateFactory.deployed();
        let predictedAddress = await instance.getEstateAddress.call(accounts[0], 0);
        let newEstateTx = await instance.newEstate("0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000", 0);

        // console.log(newEstateTx.receipt.logs[0]);
        let firstEvent = newEstateTx.receipt.logs[0].event;
        assert.equal(firstEvent, "estateCreated", "estateCreated event should fire.");
        assert.equal(newEstateTx.receipt.logs[0].args.estate, predictedAddress, "New estate not deployed at predicted address");
    });
});
